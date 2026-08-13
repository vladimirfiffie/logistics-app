import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/delivery.dart';
import '../services/app_haptics.dart';
import 'barcode_scan_sheet.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';
import 'widgets/signature_pad.dart';

/// What the driver captured when closing out a stop.
typedef ProofOfDelivery = ({
  String? recipientName,
  String? photoPath,
  String? signaturePath,
  int parcelsScanned,
});

/// Bottom sheet for confirming a delivery: who signed for it and a photo of
/// where it was left.
class CompleteDeliverySheet extends StatefulWidget {
  const CompleteDeliverySheet({
    super.key,
    required this.delivery,
    this.requirePhoto = false,
    this.signatureMode = SignatureMode.optional,
  });

  final Delivery delivery;

  /// Whether the pad is hidden, offered, or demanded.
  final SignatureMode signatureMode;

  /// When set, the stop cannot be closed until a photo has been taken. The
  /// enforcement lives here rather than after the sheet closes, so the driver
  /// is told before they fill it in, not after they tap the button.
  final bool requirePhoto;

  /// Returns the captured proof, or null if the driver backed out.
  static Future<ProofOfDelivery?> show(
    BuildContext context,
    Delivery delivery, {
    bool requirePhoto = false,
    SignatureMode signatureMode = SignatureMode.optional,
  }) {
    return showAppSheet<ProofOfDelivery>(
      context,
      // A swipe-away here would discard a captured photo and a typed name.
      dismissible: false,
      builder: (_) => CompleteDeliverySheet(
        delivery: delivery,
        requirePhoto: requirePhoto,
        signatureMode: signatureMode,
      ),
    );
  }

  @override
  State<CompleteDeliverySheet> createState() => _CompleteDeliverySheetState();
}

class _CompleteDeliverySheetState extends State<CompleteDeliverySheet> {
  final _recipientController = TextEditingController();
  final _signatureKey = GlobalKey<SignaturePadState>();
  String? _photoPath;
  bool _isCapturing = false;
  bool _isSigning = false;
  bool _showSignature = false;
  bool _hasSigned = false;
  String? _captureError;

  /// Carried in from the stop, so a driver who scanned three of six parcels
  /// onto the trolley earlier does not start again at the door.
  late int _parcelsScanned;

  /// A required signature opens the pad straight away — there is no sense
  /// making the driver tap to reveal something they cannot skip.
  @override
  void initState() {
    super.initState();
    _showSignature = widget.signatureMode == SignatureMode.required;
    _parcelsScanned = widget.delivery.parcelsScanned;
  }

  Future<void> _scanParcels() async {
    final counted = await BarcodeScanSheet.countParcels(
      context,
      expected: widget.delivery.parcelCount,
      alreadyScanned: _parcelsScanned,
    );
    if (counted == null || !mounted) return;
    setState(
      () => _parcelsScanned = counted.clamp(0, widget.delivery.parcelCount),
    );
  }

  bool get _signatureMissing =>
      widget.signatureMode == SignatureMode.required && !_hasSigned;

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    setState(() {
      _isCapturing = true;
      _captureError = null;
    });
    try {
      // The proof photo goes through the system camera app, which normally
      // needs no permission of its own. It does now: once an app *declares*
      // android.permission.CAMERA — which this one does, for scanning parcel
      // labels — Android throws a SecurityException on ACTION_IMAGE_CAPTURE
      // unless that permission has actually been granted. So the scanner
      // arriving would have quietly broken proof photos for any driver who
      // had never scanned anything.
      final camera = await Permission.camera.request();
      if (!camera.isGranted) {
        if (mounted) {
          setState(
            () => _captureError =
                'The camera permission is refused, so a photo cannot be '
                'taken. You can grant it in system settings.',
          );
        }
        return;
      }

      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (shot == null) return;
      final stored = await _persist(shot);
      await AppHaptics.captured();
      if (mounted) setState(() => _photoPath = stored);
    } catch (error) {
      if (mounted) {
        setState(() => _captureError = 'Could not open the camera: $error');
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  /// image_picker drops the shot in a cache directory the OS is free to purge.
  /// Proof of delivery has to outlive that, so copy it into app documents.
  Future<String> _persist(XFile shot) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, 'proofs'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final target = p.join(
      folder.path,
      '${widget.delivery.reference}_${DateTime.now().millisecondsSinceEpoch}'
      '${p.extension(shot.path)}',
    );
    await File(shot.path).copy(target);
    return target;
  }

  /// Rasterising the signature is the one slow step here, so it happens on
  /// confirm rather than on every stroke.
  Future<void> _confirm() async {
    setState(() => _isSigning = true);
    String? signature;
    try {
      signature = await _signatureKey.currentState?.save(
        reference: widget.delivery.reference,
      );
    } catch (error) {
      // A signature that will not save must not block the delivery: the photo
      // and the name are still proof, and the driver is at the door.
      debugPrint('could not save signature: $error');
    }
    if (!mounted) return;
    setState(() => _isSigning = false);

    final name = _recipientController.text.trim();
    Navigator.of(context).pop((
      recipientName: name.isEmpty ? null : name,
      photoPath: _photoPath,
      signaturePath: signature,
      parcelsScanned: _parcelsScanned,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Confirm delivery',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.delivery.reference} · ${widget.delivery.customerName}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _recipientController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Received by',
                hintText: 'Name of the person who took it',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            if (widget.signatureMode != SignatureMode.off) ...[
              const SizedBox(height: 16),
              _SignatureSlot(
                padKey: _signatureKey,
                expanded: _showSignature,
                required: widget.signatureMode == SignatureMode.required,
                onToggle: () =>
                    setState(() => _showSignature = !_showSignature),
                onChanged: (signed) => setState(() => _hasSigned = signed),
              ),
            ],
            const SizedBox(height: 16),
            _ParcelSlot(
              expected: widget.delivery.parcelCount,
              scanned: _parcelsScanned,
              onScan: _scanParcels,
              onClear: () => setState(() => _parcelsScanned = 0),
            ),
            const SizedBox(height: 16),
            _PhotoSlot(
              path: _photoPath,
              isBusy: _isCapturing,
              required: widget.requirePhoto,
              onCapture: _capturePhoto,
              onClear: () => setState(() => _photoPath = null),
            ),
            if (_captureError != null) ...[
              const SizedBox(height: 8),
              Text(
                _captureError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (_signatureMissing)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'A signature is required before this stop can be closed.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (widget.requirePhoto && _photoPath == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Your depot requires a photo before this stop can be '
                  'closed.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed:
                  (widget.requirePhoto && _photoPath == null) || _isSigning
                  ? null
                  : _confirm,
              icon: _isSigning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Mark as delivered'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scanning the parcels off at the door.
///
/// Optional, always — a driver with one parcel in their hand does not need a
/// camera to know it is one parcel. It earns its place on a six-box drop,
/// where "did I bring them all in?" is a real question and the answer is
/// otherwise a guess.
class _ParcelSlot extends StatelessWidget {
  const _ParcelSlot({
    required this.expected,
    required this.scanned,
    required this.onScan,
    required this.onClear,
  });

  final int expected;
  final int scanned;
  final VoidCallback onScan;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final all = scanned >= expected;

    if (scanned == 0) {
      return OutlinedButton.icon(
        onPressed: onScan,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(
          'Scan the $expected ${expected == 1 ? 'parcel' : 'parcels'} '
          '(optional)',
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: all
            ? context.deliveredContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            all ? Icons.check_circle : Icons.inventory_2_outlined,
            color: all ? context.onDeliveredContainer : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              all
                  ? 'All $expected scanned'
                  : '$scanned of $expected scanned — '
                        '${expected - scanned} still on the van',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: all ? context.onDeliveredContainer : null,
              ),
            ),
          ),
          if (!all)
            TextButton(onPressed: onScan, child: const Text('Scan more')),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Clear the count',
          ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.path,
    required this.isBusy,
    required this.required,
    required this.onCapture,
    required this.onClear,
  });

  final String? path;
  final bool isBusy;
  final bool required;
  final VoidCallback onCapture;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (path != null) {
      return Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path!),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 180,
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Text('Photo unavailable'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: IconButton.filledTonal(
              onPressed: onClear,
              icon: const Icon(Icons.close),
              tooltip: 'Remove photo',
            ),
          ),
        ],
      );
    }

    return OutlinedButton.icon(
      onPressed: isBusy ? null : onCapture,
      icon: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.photo_camera_outlined),
      label: Text(
        isBusy
            ? 'Opening camera…'
            : required
            ? 'Add proof photo (required)'
            : 'Add proof photo (optional)',
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        // Reads as an outstanding task rather than an optional extra.
        side: required ? BorderSide(color: scheme.error, width: 1.5) : null,
        foregroundColor: required ? scheme.error : null,
      ),
    );
  }
}

/// The signature pad, collapsed until asked for.
///
/// Most drops do not need one — it is a depot-by-depot thing — and an
/// always-open pad would push the camera button off a small screen.
class _SignatureSlot extends StatelessWidget {
  const _SignatureSlot({
    required this.padKey,
    required this.expanded,
    required this.required,
    required this.onToggle,
    required this.onChanged,
  });

  final GlobalKey<SignaturePadState> padKey;
  final bool expanded;
  final bool required;
  final VoidCallback onToggle;

  /// Fired with whether the pad now holds anything, so the parent can enable
  /// or block the confirm button without polling the pad's state.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!expanded) {
      return OutlinedButton.icon(
        onPressed: onToggle,
        icon: const Icon(Icons.draw_outlined),
        label: const Text('Add a signature (optional)'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          required ? 'Signature (required)' : 'Signature',
          style: TextStyle(
            color: required ? scheme.error : scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SignaturePad(
          key: padKey,
          onChanged: onChanged,
          borderColor: required ? scheme.error : null,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                padKey.currentState?.clear();
                onChanged(false);
              },
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('Clear'),
            ),
            // A required signature has no "remove": the only way past it is
            // to sign.
            if (!required)
              TextButton.icon(
                onPressed: () {
                  padKey.currentState?.clear();
                  onChanged(false);
                  onToggle();
                },
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Remove'),
              ),
          ],
        ),
      ],
    );
  }
}

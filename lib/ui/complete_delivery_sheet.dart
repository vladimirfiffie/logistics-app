import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/delivery.dart';

/// What the driver captured when closing out a stop.
typedef ProofOfDelivery = ({String? recipientName, String? photoPath});

/// Bottom sheet for confirming a delivery: who signed for it and a photo of
/// where it was left.
class CompleteDeliverySheet extends StatefulWidget {
  const CompleteDeliverySheet({super.key, required this.delivery});

  final Delivery delivery;

  /// Returns the captured proof, or null if the driver backed out.
  static Future<ProofOfDelivery?> show(
    BuildContext context,
    Delivery delivery,
  ) {
    return showModalBottomSheet<ProofOfDelivery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CompleteDeliverySheet(delivery: delivery),
    );
  }

  @override
  State<CompleteDeliverySheet> createState() => _CompleteDeliverySheetState();
}

class _CompleteDeliverySheetState extends State<CompleteDeliverySheet> {
  final _recipientController = TextEditingController();
  String? _photoPath;
  bool _isCapturing = false;
  String? _captureError;

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
      final shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (shot == null) return;
      final stored = await _persist(shot);
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
            const SizedBox(height: 16),
            _PhotoSlot(
              path: _photoPath,
              isBusy: _isCapturing,
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
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop((
                recipientName: _recipientController.text.trim().isEmpty
                    ? null
                    : _recipientController.text.trim(),
                photoPath: _photoPath,
              )),
              icon: const Icon(Icons.check),
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

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.path,
    required this.isBusy,
    required this.onCapture,
    required this.onClear,
  });

  final String? path;
  final bool isBusy;
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
      label: Text(isBusy ? 'Opening camera…' : 'Add proof photo (optional)'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}

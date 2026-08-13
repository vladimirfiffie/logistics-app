import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/app_haptics.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';

/// Reads parcel labels.
///
/// Two jobs, one camera. [BarcodeScanSheet.findStop] reads a single label and
/// hands it back — the driver picks a parcel out of the van and lands on its
/// stop. [BarcodeScanSheet.countParcels] stays open and counts distinct labels
/// off against the number expected, which is what happens at a door with six
/// boxes on a trolley.
///
/// The camera is a preview inside the app rather than the system camera the
/// proof photo uses, so this is the one place that needs the camera
/// permission. A refusal is a dead end for scanning and nothing else: every
/// screen that offers it still works entirely by hand.
class BarcodeScanSheet extends StatefulWidget {
  const BarcodeScanSheet({
    super.key,
    required this.title,
    required this.subtitle,
    this.expected = 1,
    this.alreadyScanned = 0,
    this.continuous = false,
  });

  final String title;
  final String subtitle;

  /// How many labels [continuous] mode is counting towards.
  final int expected;

  /// Labels already counted off before this sheet opened.
  final int alreadyScanned;

  /// Keep reading until the driver is done, rather than closing on the first
  /// label.
  final bool continuous;

  /// Reads one label. Resolves to the raw barcode value, or null if the
  /// driver backed out.
  static Future<String?> findStop(
    BuildContext context, {
    String title = 'Scan a parcel',
    String subtitle = 'Point the camera at the label to open its stop.',
  }) async {
    final result = await showAppSheet<_ScanResult>(
      context,
      maxHeightFactor: 0.85,
      builder: (_) => BarcodeScanSheet(title: title, subtitle: subtitle),
    );
    return result?.codes.isEmpty ?? true ? null : result!.codes.first;
  }

  /// Reads as many labels as the driver cares to present and hands back every
  /// distinct one, in the order they were read.
  ///
  /// This is the loading-the-van case: a driver working through a cage wants
  /// to know which stops these parcels belong to and whether any of them are
  /// not on today's round at all.
  static Future<List<String>?> scanMany(
    BuildContext context, {
    String title = 'Scan parcels',
    String subtitle =
        'Read as many labels as you like. Each one is matched against your '
        'run when you finish.',
  }) async {
    final result = await showAppSheet<_ScanResult>(
      context,
      maxHeightFactor: 0.85,
      builder: (_) => BarcodeScanSheet(
        title: title,
        subtitle: subtitle,
        // No target to count towards: the driver decides when they are done.
        expected: 0,
        continuous: true,
      ),
    );
    return result?.codes;
  }

  /// Counts labels off against [expected]. Resolves to how many distinct
  /// labels were read in total, including [alreadyScanned], or null if the
  /// driver backed out without scanning anything new.
  static Future<int?> countParcels(
    BuildContext context, {
    required int expected,
    int alreadyScanned = 0,
  }) async {
    final result = await showAppSheet<_ScanResult>(
      context,
      maxHeightFactor: 0.85,
      builder: (_) => BarcodeScanSheet(
        title: 'Scan the parcels',
        subtitle:
            'Read each label as it comes off the van. Nothing is uploaded — '
            'the count stays on the stop.',
        expected: expected,
        alreadyScanned: alreadyScanned,
        continuous: true,
      ),
    );
    if (result == null) return null;
    return result.codes.length + alreadyScanned;
  }

  @override
  State<BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

/// What the sheet read. A list rather than a count so continuous mode can
/// reject the same label twice — a parcel held under the camera for a second
/// too long is otherwise two parcels.
class _ScanResult {
  const _ScanResult(this.codes);
  final List<String> codes;
}

class _BarcodeScanSheetState extends State<BarcodeScanSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Labels are printed black-on-white and read at arm's length in a van;
    // the torch is the driver's call, not the app's.
    torchEnabled: false,
  );

  final _seen = <String>[];
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _count => _seen.length + widget.alreadyScanned;

  void _onDetect(BarcodeCapture capture) {
    // A detection can land in the same frame the sheet is closing in — the
    // camera does not stop the instant the driver taps Cancel — and popping a
    // route from a widget that is already gone throws.
    if (!mounted) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      if (_seen.contains(value)) continue;

      _seen.add(value);
      AppHaptics.delivered();

      if (!widget.continuous) {
        Navigator.of(context).pop(_ScanResult(_seen));
        return;
      }
      setState(() {});
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done =
        widget.continuous && widget.expected > 0 && _count >= widget.expected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: Icons.qr_code_scanner,
          ),
          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 260,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    // A camera that will not start — permission refused, or
                    // another app holding it — must say so rather than
                    // leaving a black rectangle on the screen.
                    errorBuilder: (context, error) => Container(
                      color: scheme.surfaceContainerHighest,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.no_photography_outlined,
                            size: 40,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            switch (error.errorCode) {
                              MobileScannerErrorCode.permissionDenied =>
                                'The camera permission is refused, so labels '
                                    'cannot be scanned. Everything here still '
                                    'works by hand.',
                              MobileScannerErrorCode.unsupported =>
                                'This phone cannot scan barcodes.',
                              _ =>
                                'The camera could not start. Close anything '
                                    'else using it and try again.',
                            },
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // A frame to aim with. The scanner reads the whole image;
                  // this is only there to tell the driver where to point.
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 220,
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton.filledTonal(
                      onPressed: () async {
                        await _controller.toggleTorch();
                        if (mounted) setState(() => _torchOn = !_torchOn);
                      },
                      icon: Icon(
                        _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                      ),
                      tooltip: 'Torch',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (widget.continuous)
            Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.inventory_2_outlined,
                  color: done ? context.delivered : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    // With no target — the loading-the-van case — there is
                    // nothing to be "of", so it just counts up.
                    widget.expected <= 0
                        ? '$_count ${_count == 1 ? 'label' : 'labels'} scanned'
                        : '$_count of ${widget.expected} '
                              '${widget.expected == 1 ? 'parcel' : 'parcels'} '
                              'scanned',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: done ? context.delivered : null,
                    ),
                  ),
                ),
                if (_seen.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_seen.clear),
                    child: const Text('Start over'),
                  ),
              ],
            )
          else
            Text(
              'Hold the label inside the frame.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),

          const SizedBox(height: 18),

          if (widget.continuous)
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ScanResult([..._seen])),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(
                done
                    ? 'All scanned'
                    : _count == 0
                    ? 'Done'
                    : 'Done — $_count scanned',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

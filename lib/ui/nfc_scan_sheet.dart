import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/van_tag.dart';
import '../services/app_haptics.dart';
import '../services/nfc_service.dart';
import 'widgets/app_sheet.dart';

/// What the driver chose from the tag sheet.
sealed class NfcSheetResult {
  const NfcSheetResult();
}

/// A tag was read successfully.
class NfcSheetTag extends NfcSheetResult {
  const NfcSheetTag(this.tag);
  final VanTag tag;
}

/// They skipped the tag and want to carry on anyway.
class NfcSheetManual extends NfcSheetResult {
  const NfcSheetManual();
}

/// Optional tag reader.
///
/// NFC is a shortcut here, never a requirement — every phone without the
/// hardware, every driver who has not stuck a tag in the van, and every tag
/// that will not read has to end up somewhere sensible. So the sheet always
/// offers a way through without a tag, and says plainly when the hardware
/// cannot help.
class NfcScanSheet extends StatefulWidget {
  const NfcScanSheet({
    super.key,
    required this.title,
    required this.manualLabel,
    this.subtitle,
  });

  final String title;

  /// Wording for the escape hatch, e.g. "Start without a tag".
  final String manualLabel;

  final String? subtitle;

  /// Returns null if the driver simply dismissed the sheet.
  static Future<NfcSheetResult?> show(
    BuildContext context, {
    required String title,
    required String manualLabel,
    String? subtitle,
  }) {
    return showAppSheet<NfcSheetResult>(
      context,
      maxHeightFactor: 0.7,
      builder: (_) => NfcScanSheet(
        title: title,
        manualLabel: manualLabel,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<NfcScanSheet> createState() => _NfcScanSheetState();
}

class _NfcScanSheetState extends State<NfcScanSheet> {
  late final NfcService _nfc;
  NfcReadiness? _readiness;
  String? _problem;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _nfc = context.read<NfcService>();
    _begin();
  }

  @override
  void dispose() {
    // The platform session outlives the widget unless it is closed, and a
    // stale session blocks the next one.
    _nfc.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final readiness = await _nfc.readiness();
    if (!mounted) return;
    setState(() => _readiness = readiness);
    if (readiness != NfcReadiness.ready) return;

    setState(() {
      _scanning = true;
      _problem = null;
    });

    final result = await _nfc.scanOnce();
    if (!mounted) return;

    switch (result) {
      case NfcScanRecognised(:final tag):
        await AppHaptics.delivered();
        if (mounted) Navigator.of(context).pop(NfcSheetTag(tag));
      case NfcScanForeign():
        await AppHaptics.error();
        if (mounted) {
          setState(() {
            _scanning = false;
            _problem =
                "That tag isn't set up for this app. Pair it first in "
                'Settings → Van tag.';
          });
        }
      case NfcScanFailed(:final error):
        await AppHaptics.error();
        if (mounted) {
          setState(() {
            _scanning = false;
            _problem = '$error';
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readiness = _readiness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: Icons.nfc,
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 130,
            child: Center(
              child: switch (readiness) {
                null => const CircularProgressIndicator(),
                NfcReadiness.ready => _Radar(active: _scanning),
                _ => Icon(
                  Icons.nfc_outlined,
                  size: 56,
                  color: scheme.onSurfaceVariant,
                ),
              },
            ),
          ),

          const SizedBox(height: 16),
          Text(
            switch ((readiness, _problem, _scanning)) {
              (null, _, _) => 'Checking NFC…',
              (NfcReadiness.ready, final String problem, _) => problem,
              (NfcReadiness.ready, null, true) =>
                'Hold the back of your phone against the tag.',
              (NfcReadiness.ready, null, false) => 'Ready when you are.',
              (final NfcReadiness other, _, _) => other.message,
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _problem == null ? scheme.onSurfaceVariant : scheme.error,
            ),
          ),

          const SizedBox(height: 24),

          if (readiness == NfcReadiness.ready && !_scanning)
            OutlinedButton.icon(
              onPressed: _begin,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),

          if (readiness == NfcReadiness.disabled)
            Text(
              'Turn NFC on in system settings, then try again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),

          const SizedBox(height: 10),
          // Always present, in every state. The tag is a convenience and the
          // driver must never be stuck behind one.
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(const NfcSheetManual()),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: Text(widget.manualLabel),
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

/// Pulsing rings while the reader is live, so the sheet does not look frozen
/// during the long wait for a tap.
class _Radar extends StatelessWidget {
  const _Radar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final icon = Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        color: active
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.nfc,
        size: 40,
        color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
    );

    if (!active) return icon;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .scaleXY(
              begin: 0.6,
              end: 1,
              duration: 1400.ms,
              curve: Curves.easeOut,
            )
            .fadeOut(duration: 1400.ms),
        icon,
      ],
    );
  }
}

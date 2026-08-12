import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/van_tag.dart';
import '../services/app_haptics.dart';
import '../services/nfc_service.dart';
import 'widgets/app_sheet.dart';
import 'widgets/outcome_colors.dart';

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

/// Writes a van tag, with the same radar the reader uses.
///
/// Writing used to be a list row that flipped to a spinner and then fired a
/// snackbar, which is a poor way to run something where the driver has to
/// physically hold a sticker against the back of the phone for a few seconds.
/// This is the same sheet the clock-on reader gets, and it ends in one of
/// three plain answers: the tag is ready, this particular tag will never work,
/// or something went wrong and is worth another go.
class NfcWriteSheet extends StatefulWidget {
  const NfcWriteSheet({super.key, required this.label});

  /// The van or round name that goes on the tag.
  final String label;

  /// Resolves true when a tag was written.
  static Future<bool?> show(BuildContext context, {required String label}) {
    return showAppSheet<bool>(
      context,
      maxHeightFactor: 0.75,
      builder: (_) => NfcWriteSheet(label: label),
    );
  }

  @override
  State<NfcWriteSheet> createState() => _NfcWriteSheetState();
}

class _NfcWriteSheetState extends State<NfcWriteSheet> {
  late final NfcService _nfc;
  NfcReadiness? _readiness;
  NfcWriteResult? _result;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _nfc = context.read<NfcService>();
    _begin();
  }

  @override
  void dispose() {
    _nfc.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    final readiness = await _nfc.readiness();
    if (!mounted) return;
    setState(() => _readiness = readiness);
    if (readiness != NfcReadiness.ready) return;

    setState(() {
      _writing = true;
      _result = null;
    });

    final result = await _nfc.writeVanTag(VanTag(label: widget.label));
    if (!mounted) return;

    await (result is NfcWriteDone
        ? AppHaptics.delivered()
        : AppHaptics.error());
    if (!mounted) return;
    setState(() {
      _writing = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final readiness = _readiness;
    final result = _result;
    final written = result is NfcWriteDone;

    // Incompatible is not a failure to retry: this tag will refuse again.
    final retryable =
        readiness == NfcReadiness.ready &&
        !written &&
        result is! NfcWriteIncompatible &&
        !_writing;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: written ? 'Tag ready' : 'Write a van tag',
            subtitle: written
                ? null
                : 'Writes "${widget.label}" onto a blank tag, so tapping it '
                      'clocks you on.',
            icon: written ? Icons.check_circle : Icons.nfc,
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 130,
            child: Center(
              child: switch ((readiness, result)) {
                (null, _) => const CircularProgressIndicator(),
                (_, NfcWriteDone()) => Icon(
                  Icons.check_circle,
                  size: 72,
                  color: context.delivered,
                ),
                (_, NfcWriteIncompatible()) => Icon(
                  Icons.do_not_disturb_on_outlined,
                  size: 60,
                  color: scheme.error,
                ),
                (NfcReadiness.ready, _) => _Radar(active: _writing),
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
            switch ((readiness, result, _writing)) {
              (null, _, _) => 'Checking NFC…',
              (_, NfcWriteDone(), _) =>
                'This tag now reads as "${widget.label}". Stick it somewhere '
                    'you can reach from the driver\'s seat — tapping it starts '
                    'your shift.',
              (_, NfcWriteIncompatible(:final reason), _) =>
                "That tag isn't compatible. $reason",
              (_, NfcWriteFailed(:final reason), _) => reason,
              (NfcReadiness.ready, _, true) =>
                'Hold the back of your phone against the tag and keep it '
                    'there.',
              (NfcReadiness.ready, _, false) => 'Ready when you are.',
              (final NfcReadiness other, _, _) => other.message,
            },
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: switch (result) {
                NfcWriteDone() => context.delivered,
                NfcWriteIncompatible() || NfcWriteFailed() => scheme.error,
                _ => scheme.onSurfaceVariant,
              },
            ),
          ),

          const SizedBox(height: 24),

          if (written)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Done'),
            )
          else ...[
            if (result is NfcWriteIncompatible)
              FilledButton.tonalIcon(
                onPressed: _begin,
                icon: const Icon(Icons.nfc),
                label: const Text('Try a different tag'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            if (retryable)
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_writing ? 'Cancel' : 'Close'),
            ),
          ],
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

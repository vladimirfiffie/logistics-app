import 'package:flutter/material.dart';

import '../models/delivery.dart';
import '../services/app_haptics.dart';
import 'widgets/app_sheet.dart';

/// Why a stop could not be completed, and what happens to the parcel now.
class FailedStop {
  const FailedStop({required this.reason, required this.action});

  final String reason;
  final FailureAction action;
}

/// Asks why a stop could not be completed, and what to do about it.
///
/// The presets are the reasons that actually recur on a round; "Other" opens a
/// free-text field so nothing gets forced into the wrong bucket. The second
/// half is the part that used to be missing: a parcel that could not be left
/// is going back to the door or back to the depot, and the driver holding it
/// is the one who knows which.
class FailureReasonSheet extends StatefulWidget {
  const FailureReasonSheet({super.key});

  static const presets = <String>[
    'Nobody home',
    'Address not found',
    'Refused by customer',
    'Access blocked',
    'Damaged in transit',
    'Ran out of time',
  ];

  /// Returns the reason and what happens next, or null if dismissed.
  static Future<FailedStop?> show(BuildContext context) =>
      showAppSheet<FailedStop>(
        context,
        maxHeightFactor: 0.9,
        builder: (_) => const FailureReasonSheet(),
      );

  @override
  State<FailureReasonSheet> createState() => _FailureReasonSheetState();
}

class _FailureReasonSheetState extends State<FailureReasonSheet> {
  String? _selected;

  /// Carding and coming back tomorrow is what happens to most failed drops,
  /// so it is what the sheet opens on.
  FailureAction _action = FailureAction.cardedRetryTomorrow;

  final _otherController = TextEditingController();

  bool get _isOther => _selected == 'Other';

  String? get _result {
    if (_isOther) {
      final text = _otherController.text.trim();
      return text.isEmpty ? null : text;
    }
    return _selected;
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(
              title: "Couldn't deliver",
              subtitle: 'Pick the closest reason.',
              icon: Icons.report_gmailerrorred_outlined,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in [...FailureReasonSheet.presets, 'Other'])
                  ChoiceChip(
                    label: Text(reason),
                    selected: _selected == reason,
                    onSelected: (_) {
                      AppHaptics.select();
                      setState(() => _selected = reason);
                    },
                  ),
              ],
            ),
            if (_isOther) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _otherController,
                autofocus: true,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What happened?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],

            const SizedBox(height: 20),
            Text(
              'WHAT HAPPENS TO IT',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            RadioGroup<FailureAction>(
              groupValue: _action,
              onChanged: (action) {
                if (action == null) return;
                AppHaptics.select();
                setState(() => _action = action);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in FailureAction.values)
                    RadioListTile<FailureAction>(
                      value: action,
                      contentPadding: EdgeInsets.zero,
                      title: Text(action.label),
                      subtitle: Text(action.detail),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            FilledButton(
              onPressed: _result == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(FailedStop(reason: _result!, action: _action)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Record'),
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

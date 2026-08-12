import 'package:flutter/material.dart';

import 'widgets/app_sheet.dart';

/// Asks why a stop could not be completed.
///
/// The presets are the reasons that actually recur on a round; "Other" opens a
/// free-text field so nothing gets forced into the wrong bucket.
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

  /// Returns the chosen reason, or null if dismissed.
  static Future<String?> show(BuildContext context) =>
      showAppSheet<String>(context, builder: (_) => const FailureReasonSheet());

  @override
  State<FailureReasonSheet> createState() => _FailureReasonSheetState();
}

class _FailureReasonSheetState extends State<FailureReasonSheet> {
  String? _selected;
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
                    onSelected: (_) => setState(() => _selected = reason),
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
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _result == null
                  ? null
                  : () => Navigator.of(context).pop(_result),
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

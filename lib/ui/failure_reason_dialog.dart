import 'package:flutter/material.dart';

/// Asks why a stop could not be completed.
///
/// The presets are the reasons that actually recur on a round; "Other" opens a
/// free-text field so nothing gets forced into the wrong bucket.
class FailureReasonDialog extends StatefulWidget {
  const FailureReasonDialog({super.key});

  static const presets = <String>[
    'Nobody home',
    'Address not found',
    'Refused by customer',
    'Access blocked',
    'Damaged in transit',
    'Ran out of time',
  ];

  /// Returns the chosen reason, or null if dismissed.
  static Future<String?> show(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const FailureReasonDialog(),
  );

  @override
  State<FailureReasonDialog> createState() => _FailureReasonDialogState();
}

class _FailureReasonDialogState extends State<FailureReasonDialog> {
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
    return AlertDialog(
      title: const Text("Couldn't deliver"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in [...FailureReasonDialog.presets, 'Other'])
                  ChoiceChip(
                    label: Text(reason),
                    selected: _selected == reason,
                    onSelected: (_) => setState(() => _selected = reason),
                  ),
              ],
            ),
            if (_isOther) ...[
              const SizedBox(height: 12),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _result == null
              ? null
              : () => Navigator.of(context).pop(_result),
          child: const Text('Record'),
        ),
      ],
    );
  }
}

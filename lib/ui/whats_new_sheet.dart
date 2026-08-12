import 'package:flutter/material.dart';

import '../release_notes.dart';
import 'formatters.dart';
import 'widgets/app_sheet.dart';

/// "What's new" sheet, shown once after the app updates.
///
/// Renders the same [ReleaseNote] the GitHub release body is generated from,
/// so the notes a driver reads in the app and the notes on the release page
/// cannot disagree.
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.note});

  final ReleaseNote note;

  static Future<void> show(BuildContext context, ReleaseNote note) {
    return showAppSheet<void>(
      context,
      maxHeightFactor: 0.85,
      builder: (_) => WhatsNewSheet(note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: "What's new",
            subtitle: note.headline,
            icon: Icons.auto_awesome,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                note.version,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatDate(note.date.toLocal()),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),

          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _Section(
                  title: "What's new",
                  icon: Icons.star_outline,
                  items: note.highlights,
                ),
                _Section(
                  title: 'Fixed',
                  icon: Icons.build_outlined,
                  items: note.fixes,
                ),
                if (note.minor.isNotEmpty) ...[
                  const _SectionTitle(title: 'Also', icon: Icons.more_horiz),
                  for (final line in note.minor)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 7, left: 2),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: scheme.outline,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              line,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled run of changes. Renders nothing at all when empty, so a release
/// with no fixes does not show an empty "Fixed" heading.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<ReleaseChange> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title, icon: icon),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  // One paragraph rather than two lines: the bold title and
                  // its explanation read as a sentence, and wrap together.
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: item.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (item.detail case final String detail)
                          TextSpan(
                            text: ' — $detail',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

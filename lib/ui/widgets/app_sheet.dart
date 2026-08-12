import 'package:flutter/material.dart';

/// Single entry point for every modal sheet in the app.
///
/// Going through one function keeps the drag handle, corner radius, maximum
/// height and scroll behaviour identical everywhere — the thing that makes a
/// sheet-heavy app feel deliberate rather than like a pile of one-off modals.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,

  /// Let the driver drag the sheet closed. Turn off for a sheet that must be
  /// resolved by a button, so a stray swipe cannot discard input.
  bool dismissible = true,

  /// Fraction of the screen the sheet may grow to.
  double maxHeightFactor = 0.9,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Sheets here hold text fields and long scrolling content, both of which
    // need the full height rather than the default half-screen cap.
    isScrollControlled: true,
    showDragHandle: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
      // Keeps the sheet a readable column on tablets and landscape phones
      // instead of a very wide, very short strip.
      maxWidth: 640,
    ),
    builder: builder,
  );
}

/// Title row for a sheet: a heading, optional trailing widget, and consistent
/// spacing beneath the drag handle.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle case final String subtitle) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing case final Widget trailing) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }
}

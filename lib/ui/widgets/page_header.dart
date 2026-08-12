import 'package:flutter/material.dart';

/// The large title at the top of a tab.
///
/// Material's `SliverAppBar.large` renders its title in `headlineMedium`,
/// which reads as a label rather than as the name of the page. These are the
/// four top-level destinations and there is nothing else competing at the top
/// of them now that the action icons are gone, so the title is set a step
/// larger and heavier.
class PageHeaderBar extends StatelessWidget {
  const PageHeaderBar(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar.large(
      title: Text(title),
      // Applies collapsed as well as expanded: `SliverAppBar.large` does not
      // scale the title between the two states, it moves it. A single line at
      // this size still clears the 64dp collapsed toolbar.
      titleTextStyle: theme.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Clears the status bar at the top of a tab.
///
/// The tabs used to open with a large app bar, which is what kept their first
/// row out from under the clock and the notch. The bar is gone — it cost a
/// third of the screen to repeat a word already printed on the tab underneath
/// — so the inset it was providing has to be put back explicitly.
class SliverStatusBarInset extends StatelessWidget {
  const SliverStatusBarInset({super.key, this.extra = 12});

  /// Breathing room below the status bar, on top of the system inset.
  final double extra;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(height: MediaQuery.paddingOf(context).top + extra),
    );
  }
}

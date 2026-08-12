import 'package:flutter/material.dart';

/// The colours an outcome is drawn in: green for a delivered stop, red for one
/// that could not be left.
///
/// Fixed rather than pulled from the colour scheme. Material derives `tertiary`
/// sixty degrees round the wheel from the accent, which makes a delivered stop
/// purple under Fleet blue, orange under Hi-vis and red — the failure colour —
/// under Cargo red. Green means delivered in every accent, and it is worth
/// spending the one hardcoded palette in the app on.
///
/// Each pair is a fill and something legible on top of it, the same shape as
/// `colorScheme.tertiaryContainer` / `onTertiaryContainer`, so the call sites
/// that used those swap over one for one.
abstract final class OutcomeColors {
  /// The mark itself, on a plain surface.
  static const success = Color(0xFF2E7D32);
  static const successDark = Color(0xFF66BB6A);

  static const failure = Color(0xFFC62828);
  static const failureDark = Color(0xFFEF5350);

  static const _successContainer = Color(0xFFCCEBCD);
  static const _onSuccessContainer = Color(0xFF10380F);
  static const _successContainerDark = Color(0xFF1D3A20);
  static const _onSuccessContainerDark = Color(0xFFBCE7BC);

  static Color markFor({required bool failed, required Brightness brightness}) {
    final dark = brightness == Brightness.dark;
    if (failed) return dark ? failureDark : failure;
    return dark ? successDark : success;
  }

  static Color deliveredOn(Brightness brightness) =>
      brightness == Brightness.dark ? successDark : success;

  static Color deliveredContainer(Brightness brightness) =>
      brightness == Brightness.dark ? _successContainerDark : _successContainer;

  static Color onDeliveredContainer(Brightness brightness) =>
      brightness == Brightness.dark
      ? _onSuccessContainerDark
      : _onSuccessContainer;
}

/// Reads the palette off the current theme's brightness, so a call site says
/// `context.deliveredContainer` rather than three lines of ternary.
extension DeliveredColors on BuildContext {
  Brightness get _brightness => Theme.of(this).brightness;

  /// Green on a plain surface: icons, figures, a tick.
  Color get delivered => OutcomeColors.deliveredOn(_brightness);

  /// Green as a filled card or chip.
  Color get deliveredContainer => OutcomeColors.deliveredContainer(_brightness);

  Color get onDeliveredContainer =>
      OutcomeColors.onDeliveredContainer(_brightness);
}

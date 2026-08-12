import 'package:flutter/foundation.dart';

/// An NFC tag stuck in a vehicle, used to start and end a shift by tapping.
///
/// The tag carries a small text record rather than just being identified by
/// its hardware id. Two reasons: a blank tag's id tells you nothing if the app
/// is reinstalled, and a written record means the driver can read the tag with
/// any NFC app and see what it is instead of an opaque serial.
@immutable
class VanTag {
  const VanTag({required this.label, this.hardwareId});

  /// What the driver calls this vehicle, e.g. `LT21 KXR` or `Round 4`.
  final String label;

  /// The tag's own serial, when the platform exposed one. Not all tags have a
  /// stable id, so this is a bonus rather than the identity.
  final String? hardwareId;

  /// Marks the record as ours. A tag from a hotel keycard or a bus poster
  /// will decode as text perfectly well, so the payload needs a shape we can
  /// recognise and reject.
  static const scheme = 'logistics-van';

  /// The text written to the tag, e.g. `logistics-van:v1:LT21 KXR`.
  ///
  /// Versioned so a later format change can be told apart from a corrupt read
  /// rather than guessed at.
  String get payload => '$scheme:v1:$label';

  /// Parses a tag payload, or null if this is not one of ours.
  static VanTag? tryParse(String? text, {String? hardwareId}) {
    if (text == null) return null;
    final trimmed = text.trim();

    // Split into at most 3 so a label containing a colon survives.
    final parts = trimmed.split(':');
    if (parts.length < 3) return null;
    if (parts[0] != scheme) return null;
    if (parts[1] != 'v1') return null;

    final label = parts.sublist(2).join(':').trim();
    if (label.isEmpty) return null;

    return VanTag(label: label, hardwareId: hardwareId);
  }

  @override
  bool operator ==(Object other) =>
      other is VanTag && other.label == label && other.hardwareId == hardwareId;

  @override
  int get hashCode => Object.hash(label, hardwareId);

  @override
  String toString() => 'VanTag($label)';
}

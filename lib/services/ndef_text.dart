import 'dart:convert';
import 'dart:typed_data';

/// Encoder/decoder for NDEF "Text" records (type `T`, well-known TNF).
///
/// The layout is defined by the NFC Forum text record spec:
///
/// ```
/// byte 0      status: bit 7 = encoding (0 UTF-8, 1 UTF-16)
///                     bits 0-5 = length of the language code
/// bytes 1..n  language code, ASCII, e.g. "en"
/// bytes n+1.. the text itself
/// ```
///
/// Written by hand rather than pulled from a package because it is twenty
/// lines, and getting the status byte wrong is the single most common way an
/// NFC tag ends up unreadable by other apps.
class NdefText {
  const NdefText._();

  /// Bit 7 of the status byte. We only ever write UTF-8.
  static const _utf16Flag = 0x80;

  /// Bits 0-5 hold the language code length; bit 6 is reserved.
  static const _languageLengthMask = 0x3F;

  /// Builds the payload for a text record.
  ///
  /// Throws [ArgumentError] for a language code that cannot fit the 6-bit
  /// length field, which would silently corrupt the record.
  static Uint8List encode(String text, {String language = 'en'}) {
    final languageBytes = ascii.encode(language);
    if (languageBytes.length > _languageLengthMask) {
      throw ArgumentError.value(
        language,
        'language',
        'language code must be at most $_languageLengthMask bytes',
      );
    }

    final textBytes = utf8.encode(text);
    return Uint8List.fromList([
      languageBytes.length, // UTF-8, so the encoding bit stays clear.
      ...languageBytes,
      ...textBytes,
    ]);
  }

  /// Reads the text back out, or null if [payload] is not a well-formed text
  /// record.
  ///
  /// Returns null rather than throwing: tags in the wild contain all sorts,
  /// and a malformed one is a "not our tag" rather than a crash.
  static String? decode(Uint8List payload) {
    if (payload.isEmpty) return null;

    final status = payload.first;
    final languageLength = status & _languageLengthMask;

    // The record must be long enough for its own declared language code.
    if (payload.length < 1 + languageLength) return null;

    final textBytes = payload.sublist(1 + languageLength);
    try {
      return (status & _utf16Flag) != 0
          ? _decodeUtf16(textBytes)
          : utf8.decode(textBytes);
    } catch (_) {
      return null;
    }
  }

  /// Reads the language code, or null when the payload is malformed.
  static String? language(Uint8List payload) {
    if (payload.isEmpty) return null;
    final length = payload.first & _languageLengthMask;
    if (payload.length < 1 + length) return null;
    try {
      return ascii.decode(payload.sublist(1, 1 + length));
    } catch (_) {
      return null;
    }
  }

  /// We never write UTF-16, but other writers do, so reading has to cope.
  /// Big-endian is the default; a BOM overrides it.
  static String _decodeUtf16(List<int> bytes) {
    if (bytes.length.isOdd) throw const FormatException('truncated UTF-16');

    var offset = 0;
    var littleEndian = false;
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        littleEndian = true;
        offset = 2;
      } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        offset = 2;
      }
    }

    final units = <int>[];
    for (var i = offset; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }
}

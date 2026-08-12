import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../models/van_tag.dart';
import 'ndef_text.dart';

/// Why an NFC operation could not run.
enum NfcReadiness {
  ready,

  /// The device has no NFC hardware at all.
  unsupported,

  /// Hardware is present but switched off in system settings.
  disabled;

  String get message => switch (this) {
    NfcReadiness.ready => 'NFC is available.',
    NfcReadiness.unsupported => 'This phone has no NFC hardware.',
    NfcReadiness.disabled => 'NFC is switched off in system settings.',
  };
}

/// What came back from holding a tag against the phone.
sealed class NfcScanResult {
  const NfcScanResult();
}

/// A tag written by this app.
class NfcScanRecognised extends NfcScanResult {
  const NfcScanRecognised(this.tag);
  final VanTag tag;
}

/// A perfectly valid tag that is not ours — a travel card, a shop poster.
class NfcScanForeign extends NfcScanResult {
  const NfcScanForeign(this.text);

  /// Whatever text it held, if any. Null for a tag with no NDEF data.
  final String? text;
}

class NfcScanFailed extends NfcScanResult {
  const NfcScanFailed(this.error);
  final Object error;
}

/// Wraps `nfc_manager` so nothing else in the app imports it — the same trick
/// as [LocationService], and what makes the controllers testable without a
/// phone to tap things against.
class NfcService {
  NfcService();

  /// Guards against two overlapping sessions, which the platform rejects.
  bool _sessionOpen = false;

  bool get isScanning => _sessionOpen;

  Future<NfcReadiness> readiness() async {
    try {
      return switch (await NfcManager.instance.checkAvailability()) {
        NfcAvailability.enabled => NfcReadiness.ready,
        NfcAvailability.disabled => NfcReadiness.disabled,
        NfcAvailability.unsupported => NfcReadiness.unsupported,
      };
    } catch (error) {
      debugPrint('nfc: availability check failed — $error');
      return NfcReadiness.unsupported;
    }
  }

  /// Waits for one tag and reports what it was.
  ///
  /// Always resolves — a timeout or a platform error comes back as
  /// [NfcScanFailed] rather than hanging a button in a spinner forever.
  Future<NfcScanResult> scanOnce({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_sessionOpen) {
      return const NfcScanFailed('A scan is already running.');
    }

    final completer = Completer<NfcScanResult>();
    _sessionOpen = true;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        alertMessageIos: 'Hold your phone against the tag',
        onDiscovered: (tag) async {
          if (completer.isCompleted) return;
          completer.complete(await _read(tag));
        },
      );
    } catch (error) {
      _sessionOpen = false;
      return NfcScanFailed(error);
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return const NfcScanFailed('No tag was detected.');
    } finally {
      await _stop();
    }
  }

  /// Writes [tag]'s payload onto the next tag presented.
  ///
  /// Returns null on success, or a human-readable reason it failed — the
  /// caller has to explain this to someone holding a phone against a sticker,
  /// so "unwritable tag" beats a stack trace.
  Future<String?> writeVanTag(
    VanTag tag, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_sessionOpen) return 'A scan is already running.';

    final completer = Completer<String?>();
    _sessionOpen = true;

    try {
      await NfcManager.instance.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        alertMessageIos: 'Hold your phone against the tag to write it',
        onDiscovered: (discovered) async {
          if (completer.isCompleted) return;
          completer.complete(await _write(discovered, tag));
        },
      );
    } catch (error) {
      _sessionOpen = false;
      return '$error';
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return 'No tag was detected.';
    } finally {
      await _stop();
    }
  }

  Future<void> cancel() => _stop();

  Future<NfcScanResult> _read(NfcTag tag) async {
    try {
      final ndef = NdefAndroid.from(tag);
      if (ndef == null) return const NfcScanForeign(null);

      final message = await ndef.getNdefMessage() ?? ndef.cachedNdefMessage;
      final text = _firstText(message);

      final parsed = VanTag.tryParse(text, hardwareId: _hardwareId(tag));
      return parsed == null ? NfcScanForeign(text) : NfcScanRecognised(parsed);
    } catch (error) {
      return NfcScanFailed(error);
    }
  }

  Future<String?> _write(NfcTag discovered, VanTag tag) async {
    try {
      final ndef = NdefAndroid.from(discovered);
      if (ndef == null) {
        return 'That tag cannot store text. Use an NDEF-formatted tag '
            '(NTAG213 or similar).';
      }
      if (!ndef.isWritable) return 'That tag is locked and cannot be written.';

      final message = NdefMessage(
        records: [
          NdefRecord(
            typeNameFormat: TypeNameFormat.wellKnown,
            type: Uint8List.fromList('T'.codeUnits),
            identifier: Uint8List(0),
            payload: NdefText.encode(tag.payload),
          ),
        ],
      );

      if (message.byteLength > ndef.maxSize) {
        return 'That tag is too small — it holds ${ndef.maxSize} bytes and '
            'this needs ${message.byteLength}.';
      }

      await ndef.writeNdefMessage(message);
      return null;
    } catch (error) {
      return '$error';
    }
  }

  /// The first text record in the message, ignoring URLs and other types.
  static String? _firstText(NdefMessage? message) {
    if (message == null) return null;
    for (final record in message.records) {
      final isText =
          record.typeNameFormat == TypeNameFormat.wellKnown &&
          record.type.length == 1 &&
          record.type.first == 0x54; // 'T'
      if (!isText) continue;
      final text = NdefText.decode(record.payload);
      if (text != null) return text;
    }
    return null;
  }

  static String? _hardwareId(NfcTag tag) {
    try {
      final id = NfcTagAndroid.from(tag)?.id;
      if (id == null || id.isEmpty) return null;
      return id
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
    } catch (_) {
      return null;
    }
  }

  Future<void> _stop() async {
    if (!_sessionOpen) return;
    _sessionOpen = false;
    try {
      await NfcManager.instance.stopSession();
    } catch (error) {
      debugPrint('nfc: could not stop session — $error');
    }
  }
}

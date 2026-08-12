import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/models/shift.dart';
import 'package:logistics_app/models/van_tag.dart';
import 'package:logistics_app/services/ndef_text.dart';
import 'package:logistics_app/state/shift_controller.dart';

import 'fakes.dart';

void main() {
  group('NDEF text records', () {
    test('round-trips plain text', () {
      final payload = NdefText.encode('logistics-van:v1:LT21 KXR');

      expect(NdefText.decode(payload), 'logistics-van:v1:LT21 KXR');
      expect(NdefText.language(payload), 'en');
    });

    test('the status byte encodes the language length, not the text', () {
      final payload = NdefText.encode('hello', language: 'en');

      // Byte 0 is the status byte: UTF-8 (bit 7 clear) and a 2-byte language
      // code. Getting this wrong is what makes a tag unreadable elsewhere.
      expect(payload.first, 2);
      expect(payload.sublist(1, 3), ascii.encode('en'));
      expect(payload.sublist(3), utf8.encode('hello'));
    });

    test('handles a longer language code', () {
      final payload = NdefText.encode('bonjour', language: 'fr-CA');

      expect(payload.first, 5);
      expect(NdefText.language(payload), 'fr-CA');
      expect(NdefText.decode(payload), 'bonjour');
    });

    test('survives non-ASCII text', () {
      final payload = NdefText.encode('Café — Ravensmere ✓');

      expect(NdefText.decode(payload), 'Café — Ravensmere ✓');
    });

    test('rejects a language code too long for the 6-bit length field', () {
      expect(
        () => NdefText.encode('x', language: 'a' * 64),
        throwsArgumentError,
      );
    });

    group('malformed payloads decode to null, not a crash', () {
      test('empty', () {
        expect(NdefText.decode(Uint8List(0)), isNull);
        expect(NdefText.language(Uint8List(0)), isNull);
      });

      test('declares a longer language code than it contains', () {
        // Status byte says 20 bytes of language; only 2 follow.
        final payload = Uint8List.fromList([20, ...ascii.encode('en')]);

        expect(NdefText.decode(payload), isNull);
        expect(NdefText.language(payload), isNull);
      });

      test('invalid UTF-8 in the text', () {
        final payload = Uint8List.fromList([2, ...ascii.encode('en'), 0xFF]);

        expect(NdefText.decode(payload), isNull);
      });
    });

    test('reads UTF-16 written by another app', () {
      // Bit 7 set, 2-byte language, then big-endian UTF-16 for "hi".
      final payload = Uint8List.fromList([
        0x80 | 2,
        ...ascii.encode('en'),
        0x00, 0x68, // h
        0x00, 0x69, // i
      ]);

      expect(NdefText.decode(payload), 'hi');
    });
  });

  group('VanTag', () {
    test('round-trips through its payload', () {
      const tag = VanTag(label: 'LT21 KXR');

      expect(tag.payload, 'logistics-van:v1:LT21 KXR');
      expect(VanTag.tryParse(tag.payload)?.label, 'LT21 KXR');
    });

    test('keeps a label containing a colon', () {
      const tag = VanTag(label: 'Round 4: north');

      expect(VanTag.tryParse(tag.payload)?.label, 'Round 4: north');
    });

    test('carries the hardware id through when the platform gave one', () {
      final parsed = VanTag.tryParse(
        'logistics-van:v1:Van 2',
        hardwareId: '04:A2:B7',
      );

      expect(parsed?.hardwareId, '04:A2:B7');
    });

    test('rejects tags that are not ours', () {
      // A hotel keycard, a bus stop poster, a URL record — all decode as text
      // perfectly well, so the scheme prefix is what keeps them out.
      expect(VanTag.tryParse('https://example.com'), isNull);
      expect(VanTag.tryParse('some random text'), isNull);
      expect(VanTag.tryParse('logistics-van'), isNull);
      expect(VanTag.tryParse('logistics-van:v1'), isNull);
      expect(VanTag.tryParse('other-app:v1:Van 2'), isNull);
      expect(VanTag.tryParse(null), isNull);
    });

    test('rejects a future format rather than guessing at it', () {
      expect(VanTag.tryParse('logistics-van:v2:Van 2'), isNull);
    });

    test('rejects an empty label', () {
      expect(VanTag.tryParse('logistics-van:v1:'), isNull);
      expect(VanTag.tryParse('logistics-van:v1:   '), isNull);
    });

    test('a written tag reads back through the full NDEF round trip', () {
      // The path a real tag takes: encode to payload bytes, decode, parse.
      const original = VanTag(label: 'LT21 KXR');
      final bytes = NdefText.encode(original.payload);
      final parsed = VanTag.tryParse(NdefText.decode(bytes));

      expect(parsed?.label, original.label);
    });
  });

  group('ShiftController', () {
    late FakeDeliveryRepository repository;
    late ShiftController controller;

    setUp(() {
      repository = FakeDeliveryRepository();
      controller = ShiftController(repository);
    });

    // The controller runs a one-second ticker while a shift is open.
    tearDown(() => controller.dispose());

    test('starts and ends a shift', () async {
      await controller.load();
      expect(controller.isOnShift, isFalse);

      final shift = await controller.start(vehicleLabel: 'LT21 KXR');

      expect(shift, isNotNull);
      expect(controller.isOnShift, isTrue);
      expect(controller.current!.vehicleLabel, 'LT21 KXR');

      final ended = await controller.end();

      expect(ended!.isActive, isFalse);
      expect(controller.isOnShift, isFalse);
    });

    test('records whether a tag or a button started it', () async {
      await controller.load();
      await controller.start(startedByTag: true);

      // A tag tap is evidence the driver was physically at the vehicle; a
      // button press is not, so the difference is worth keeping.
      expect(controller.current!.startedByTag, isTrue);
    });

    test('refuses a second concurrent shift', () async {
      await controller.load();
      await controller.start();

      final second = await controller.start();

      expect(second, isNull);
      expect(repository.shifts, hasLength(1));
    });

    test('ending when not clocked on is a no-op', () async {
      await controller.load();

      expect(await controller.end(), isNull);
    });

    test('picks up a shift left open by a previous launch', () async {
      await repository.startShift(vehicleLabel: 'Van 9');

      await controller.load();

      expect(controller.isOnShift, isTrue);
      expect(controller.current!.vehicleLabel, 'Van 9');
    });

    test('totals only finished shifts', () async {
      await controller.load();
      await controller.start();
      await controller.end();
      await controller.start();

      // The running one has no final duration yet, so it must not be counted.
      expect(controller.history, hasLength(2));
      expect(controller.totalWorked, isNot(Duration.zero));
    });

    test('ticks while on shift so the elapsed clock is not frozen', () async {
      await controller.load();
      await controller.start();

      var ticks = 0;
      controller.addListener(() => ticks++);
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      // Shift.duration is measured against DateTime.now(), so without a tick
      // of its own the card reads "0s" for the whole shift.
      expect(ticks, greaterThan(0));
      expect(controller.elapsed, greaterThan(Duration.zero));
    });

    test('stops ticking once clocked off', () async {
      await controller.load();
      await controller.start();
      await controller.end();

      var ticks = 0;
      controller.addListener(() => ticks++);
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(ticks, 0);
    });

    test('adopts a shift opened behind the controller\'s back', () async {
      // load() never ran, or failed — so the controller believes nobody is
      // clocked on while storage disagrees. Clocking on used to fail silently
      // here and leave the button doing nothing at all.
      await repository.startShift(vehicleLabel: 'Van 9');

      final started = await controller.start();

      expect(started, isNotNull);
      expect(controller.isOnShift, isTrue);
      expect(controller.current!.vehicleLabel, 'Van 9');
      expect(controller.error, isNull);
      expect(repository.shifts, hasLength(1), reason: 'no duplicate shift');
    });

    test('reports why a clock-on failed', () async {
      await controller.load();
      repository.failOnStartShift = true;

      final started = await controller.start();

      expect(started, isNull);
      expect(controller.error, isNotNull);
      expect(controller.isOnShift, isFalse);
    });
  });

  group('Shift', () {
    test('round-trips through its map form', () {
      final shift = Shift(
        id: 's1',
        startedAt: DateTime(2026, 8, 12, 8),
        endedAt: DateTime(2026, 8, 12, 16, 30),
        vehicleLabel: 'LT21 KXR',
        startedByTag: true,
      );

      final restored = Shift.fromMap(shift.toMap());

      expect(restored.id, shift.id);
      expect(restored.startedAt, shift.startedAt);
      expect(restored.endedAt, shift.endedAt);
      expect(restored.vehicleLabel, 'LT21 KXR');
      expect(restored.startedByTag, isTrue);
      expect(restored.duration, const Duration(hours: 8, minutes: 30));
    });

    test('an open shift has no end and stays active', () {
      final shift = Shift(id: 's1', startedAt: DateTime(2026, 8, 12, 8));

      expect(Shift.fromMap(shift.toMap()).isActive, isTrue);
      expect(Shift.fromMap(shift.toMap()).startedByTag, isFalse);
    });
  });
}

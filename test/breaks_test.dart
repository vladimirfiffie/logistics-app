import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/data/app_database.dart';
import 'package:logistics_app/data/local_delivery_repository.dart';
import 'package:logistics_app/models/shift_break.dart';
import 'package:logistics_app/state/shift_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fakes.dart';

void main() {
  sqfliteFfiInit();

  group('ShiftController breaks', () {
    late FakeDeliveryRepository repository;
    late ShiftController controller;

    setUp(() {
      repository = FakeDeliveryRepository();
      controller = ShiftController(repository);
    });

    tearDown(() => controller.dispose());

    test('a break subtracts from worked time but not from the shift', () async {
      await controller.load();
      await controller.start();
      await controller.startBreak(kind: BreakKind.meal);

      expect(controller.isOnBreak, isTrue);
      expect(controller.currentBreak!.kind, BreakKind.meal);
      // The shift clock keeps running; only the worked figure is reduced.
      expect(
        controller.elapsed,
        greaterThanOrEqualTo(controller.workedElapsed),
      );
    });

    test('refuses a second concurrent break', () async {
      await controller.load();
      await controller.start();
      await controller.startBreak();

      expect(await controller.startBreak(), isNull);
      expect(repository.breaks, hasLength(1));
    });

    test('cannot take a break off the clock', () async {
      await controller.load();

      expect(await controller.startBreak(), isNull);
      expect(repository.breaks, isEmpty);
    });

    test('ending a break puts the driver back on the clock', () async {
      await controller.load();
      await controller.start();
      await controller.startBreak();

      final finished = await controller.endBreak();

      expect(finished, isNotNull);
      expect(finished!.isActive, isFalse);
      expect(controller.isOnBreak, isFalse);
      expect(controller.breaks, hasLength(1));
    });

    test('ending when no break is running is a no-op', () async {
      await controller.load();
      await controller.start();

      expect(await controller.endBreak(), isNull);
    });

    test('clocking off closes a break left running', () async {
      await controller.load();
      await controller.start();
      await controller.startBreak();

      await controller.end();

      // Otherwise the open break counts against every later total.
      expect(
        repository.breaks.values.every((taken) => !taken.isActive),
        isTrue,
      );
      expect(controller.isOnBreak, isFalse);
    });

    test('a new shift starts with no breaks carried over', () async {
      await controller.load();
      await controller.start();
      await controller.startBreak();
      await controller.end();

      await controller.start();

      expect(controller.breaks, isEmpty);
      expect(controller.breakElapsed, Duration.zero);
    });
  });

  group('breaks in storage', () {
    late Database db;
    late LocalDeliveryRepository repository;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        ),
      );
      await AppDatabase.createSchemaForTesting(db);
      repository = LocalDeliveryRepository(db);
    });

    tearDown(() => db.close());

    test('round-trips a break through SQLite', () async {
      final shift = await repository.startShift(vehicleLabel: 'LT21 KXR');
      final taken = await repository.startBreak(shift.id, kind: BreakKind.meal);

      final open = await repository.activeBreak(shift.id);

      expect(open!.id, taken.id);
      expect(open.kind, BreakKind.meal);
      expect(open.shiftId, shift.id);
      expect(open.isActive, isTrue);
    });

    test('refuses to re-end a break', () async {
      final shift = await repository.startShift();
      final taken = await repository.startBreak(shift.id);
      await repository.endBreak(taken.id);

      expect(repository.endBreak(taken.id), throwsStateError);
    });

    test('refuses to re-end a shift', () async {
      final shift = await repository.startShift();
      await repository.endShift(shift.id);

      // Rewriting a clocked-off shift's end time would corrupt a timesheet.
      expect(repository.endShift(shift.id), throwsStateError);
    });

    test('clocking off closes any break still running', () async {
      final shift = await repository.startShift();
      await repository.startBreak(shift.id);

      await repository.endShift(shift.id);

      expect(await repository.activeBreak(shift.id), isNull);
    });

    test('breaks are fetched for many shifts in one query', () async {
      final first = await repository.startShift();
      await repository.startBreak(first.id);
      await repository.endShift(first.id);
      final second = await repository.startShift();
      await repository.startBreak(second.id, kind: BreakKind.meal);

      final grouped = await repository.breaksForShifts([first.id, second.id]);

      expect(grouped[first.id], hasLength(1));
      expect(grouped[second.id], hasLength(1));
      expect(grouped[second.id]!.single.kind, BreakKind.meal);
    });

    test('an empty id list does not query at all', () async {
      expect(await repository.breaksForShifts(const []), isEmpty);
    });

    test('deleting a shift takes its breaks with it', () async {
      final shift = await repository.startShift();
      await repository.startBreak(shift.id);

      await repository.deleteEverything();

      expect(await repository.fetchShifts(), isEmpty);
      expect(await repository.breaksForShift(shift.id), isEmpty);
    });
  });

  group('ShiftBreak', () {
    test('round-trips through its map form', () {
      final taken = ShiftBreak(
        id: 'b1',
        shiftId: 's1',
        startedAt: DateTime(2026, 8, 12, 12),
        endedAt: DateTime(2026, 8, 12, 12, 30),
        kind: BreakKind.meal,
      );

      final restored = ShiftBreak.fromMap(taken.toMap());

      expect(restored.id, 'b1');
      expect(restored.shiftId, 's1');
      expect(restored.startedAt, taken.startedAt);
      expect(restored.endedAt, taken.endedAt);
      expect(restored.kind, BreakKind.meal);
      expect(restored.duration, const Duration(minutes: 30));
    });

    test('an unknown kind falls back rather than throwing', () {
      expect(BreakKind.fromName('siesta'), BreakKind.rest);
      expect(BreakKind.fromName(null), BreakKind.rest);
    });
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/trip.dart';
import '../models/trip_point.dart';

/// Writes the day's work out as files the driver owns.
///
/// Mileage is the usual reason to want this: a claim needs a record, and until
/// now the only copy lived in a SQLite file inside the app's private storage.
/// Nothing is uploaded — the files land in the app's documents directory and
/// the driver decides where they go from there.
class ExportService {
  const ExportService(this._repository);

  final DeliveryRepository _repository;

  /// One row per stop, with the distance recorded getting to it.
  ///
  /// CSV rather than anything richer because it opens in a spreadsheet, which
  /// is what an expenses form wants.
  Future<File> exportStopsCsv({DateTime? on}) async {
    final deliveries = await _repository.fetchDeliveries();
    final trips = await _repository.fetchTrips();

    final tripByDelivery = <String, Trip>{};
    for (final trip in trips) {
      // Newest wins if a stop was attempted more than once.
      final existing = tripByDelivery[trip.deliveryId];
      if (existing == null || trip.startedAt.isAfter(existing.startedAt)) {
        tripByDelivery[trip.deliveryId] = trip;
      }
    }

    final rows = <String>[
      _csvRow(const [
        'Reference',
        'Customer',
        'Address',
        'Scheduled',
        'Status',
        'Completed',
        'Recipient',
        'Parcels',
        'Distance (m)',
        'Driving time (s)',
        'Failure reason',
      ]),
    ];

    final wanted = on == null
        ? deliveries
        : deliveries.where((stop) => _sameDay(stop.scheduledFor, on));

    for (final stop in wanted) {
      final trip = tripByDelivery[stop.id];
      rows.add(
        _csvRow([
          stop.reference,
          stop.customerName,
          stop.address,
          stop.scheduledFor.toIso8601String(),
          stop.status.label,
          stop.completedAt?.toIso8601String() ?? '',
          stop.recipientName ?? '',
          '${stop.parcelCount}',
          trip == null ? '' : trip.distanceMeters.toStringAsFixed(1),
          trip == null ? '' : '${trip.duration.inSeconds}',
          stop.failureReason ?? '',
        ]),
      );
    }

    return _write(
      'stops-${_stamp(on ?? DateTime.now())}.csv',
      rows.join('\r\n'),
    );
  }

  /// The recorded trails as a single GPX file, one track per trip.
  ///
  /// GPX because every mapping tool reads it, so the driver can put their day
  /// on a map without this app being involved.
  Future<File> exportTrailsGpx({DateTime? on}) async {
    final trips = await _repository.fetchTrips();
    final deliveries = <String, Delivery>{
      for (final stop in await _repository.fetchDeliveries()) stop.id: stop,
    };

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Logistics" '
        'xmlns="http://www.topografix.com/GPX/1/1">',
      );

    for (final trip in trips) {
      if (on != null && !_sameDay(trip.startedAt, on)) continue;
      final points = await _repository.pointsForTrip(trip.id);
      if (points.isEmpty) continue;

      final stop = deliveries[trip.deliveryId];
      final name = stop == null
          ? 'Trip ${trip.id}'
          : '${stop.reference} — ${stop.customerName}';

      buffer
        ..writeln('  <trk>')
        ..writeln('    <name>${_xml(name)}</name>')
        ..writeln('    <trkseg>');
      for (final point in points) {
        buffer.writeln(_trackPoint(point));
      }
      buffer
        ..writeln('    </trkseg>')
        ..writeln('  </trk>');
    }

    buffer.writeln('</gpx>');
    return _write(
      'trails-${_stamp(on ?? DateTime.now())}.gpx',
      buffer.toString(),
    );
  }

  String _trackPoint(TripPoint point) {
    final lat = point.latitude.toStringAsFixed(7);
    final lon = point.longitude.toStringAsFixed(7);
    return '      <trkpt lat="$lat" lon="$lon">\n'
        '        <ele>${point.altitude.toStringAsFixed(1)}</ele>\n'
        '        <time>${point.recordedAt.toUtc().toIso8601String()}</time>\n'
        '      </trkpt>';
  }

  Future<File> _write(String filename, String contents) async {
    final directory = await getApplicationDocumentsDirectory();
    final exports = Directory(p.join(directory.path, 'exports'));
    if (!exports.existsSync()) await exports.create(recursive: true);

    final file = File(p.join(exports.path, filename));
    await file.writeAsString(contents, flush: true);
    debugPrint('exported ${file.path}');
    return file;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _stamp(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  /// RFC 4180: quote every field, and double any quote inside it. Addresses
  /// contain commas, and a customer called O'Brien & Sons "Ltd" must not
  /// shift every later column by one.
  @visibleForTesting
  static String csvRow(List<String> values) => _csvRow(values);

  static String _csvRow(List<String> values) =>
      values.map((value) => '"${value.replaceAll('"', '""')}"').join(',');

  @visibleForTesting
  static String xmlEscape(String value) => _xml(value);

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

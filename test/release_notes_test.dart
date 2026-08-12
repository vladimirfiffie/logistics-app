import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/release_notes.dart';
import 'package:logistics_app/services/app_preferences.dart';

/// Reads `version:` out of pubspec.yaml without pulling in a YAML parser.
String _pubspecVersion() {
  final line = File(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((line) => line.startsWith('version:'));
  return line.split(':')[1].trim().split('+').first;
}

void main() {
  group('release notes data', () {
    test('the newest note matches the version in pubspec.yaml', () {
      // If this fails, someone bumped the app version without writing notes
      // (or vice versa) — the release body and the in-app sheet would then
      // describe a different build than the one being shipped.
      expect(currentRelease.version, _pubspecVersion());
    });

    test('notes are ordered newest first', () {
      for (var i = 1; i < releaseNotes.length; i++) {
        expect(
          releaseNotes[i - 1].date.isAfter(releaseNotes[i].date) ||
              releaseNotes[i - 1].date == releaseNotes[i].date,
          isTrue,
          reason:
              '${releaseNotes[i - 1].version} should not predate '
              '${releaseNotes[i].version}',
        );
      }
    });

    test('every entry has a version, headline and at least one change', () {
      for (final note in releaseNotes) {
        expect(note.version, isNotEmpty);
        expect(note.headline, isNotEmpty);
        expect(note.changes, isNotEmpty);
        expect(note.tag, startsWith('v'));
      }
    });

    test('versions are unique', () {
      final versions = releaseNotes.map((note) => note.version).toList();
      expect(versions.toSet(), hasLength(versions.length));
    });

    test('prerelease flag follows the hyphen rule', () {
      ReleaseNote noteFor(String version) => ReleaseNote(
        version: version,
        date: DateTime.utc(2026, 1, 1),
        headline: 'x',
        changes: const ['y'],
      );

      expect(noteFor('1.0.0-beta.1').isPrerelease, isTrue);
      expect(noteFor('1.0.0-rc.2').isPrerelease, isTrue);
      expect(noteFor('1.0.0').isPrerelease, isFalse);
      expect(noteFor('2.3.4').isPrerelease, isFalse);
    });
  });

  group('releaseNoteFor', () {
    test('accepts both the bare version and the tag form', () {
      final version = currentRelease.version;
      expect(releaseNoteFor(version), same(currentRelease));
      expect(releaseNoteFor('v$version'), same(currentRelease));
    });

    test('returns null for an unknown tag', () {
      expect(releaseNoteFor('v0.0.0-manual'), isNull);
      expect(releaseNoteFor('nonsense'), isNull);
    });
  });

  group('shouldShowWhatsNew', () {
    test('never on a fresh install', () {
      expect(
        shouldShowWhatsNew(
          lastSeenVersion: null,
          currentVersion: '1.0.0',
          isFreshInstall: true,
        ),
        isFalse,
      );
    });

    test('not for someone who has never seen a version recorded', () {
      expect(
        shouldShowWhatsNew(
          lastSeenVersion: null,
          currentVersion: '1.0.0',
          isFreshInstall: false,
        ),
        isFalse,
      );
    });

    test('shows once when the version moved on', () {
      expect(
        shouldShowWhatsNew(
          lastSeenVersion: '1.0.0-beta.1',
          currentVersion: '1.0.0-beta.2',
          isFreshInstall: false,
        ),
        isTrue,
      );
    });

    test('does not show again on the same version', () {
      expect(
        shouldShowWhatsNew(
          lastSeenVersion: '1.0.0-beta.2',
          currentVersion: '1.0.0-beta.2',
          isFreshInstall: false,
        ),
        isFalse,
      );
    });
  });
}

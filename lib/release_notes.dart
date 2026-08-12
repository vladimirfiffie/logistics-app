/// Release notes, written once and rendered in two places: the in-app
/// "What's new" sheet and the GitHub release body.
///
/// This file must stay free of Flutter imports — `tool/generate_release_notes`
/// imports it under plain `dart run`, which has no Flutter SDK available.
library;

class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.headline,
    required this.changes,
  });

  /// Must match `version:` in pubspec.yaml minus the `+build` suffix.
  /// A test enforces this for the newest entry.
  final String version;

  final DateTime date;

  /// One line summarising the release, shown as the sheet's subtitle.
  final String headline;

  /// User-facing bullets. Write what changed for a driver, not what changed
  /// in the code.
  final List<String> changes;

  /// Tag form, e.g. `v1.0.0-beta.1`.
  String get tag => 'v$version';

  /// A hyphen means a prerelease: `1.0.0-beta.1` yes, `1.0.0` no. The release
  /// workflow applies the same rule to decide GitHub's prerelease flag.
  bool get isPrerelease => version.contains('-');
}

/// Newest first. The first entry is the current version.
final releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.0.0-beta.1',
    date: DateTime.utc(2026, 8, 11),
    headline: 'First beta: your round, tracked end to end.',
    changes: [
      'Track a delivery from start to doorstep, with your route recorded as '
          'you drive.',
      'Tracking keeps running with the screen off or while you are in your '
          'nav app, and shows a notification the whole time so it can never '
          'run unnoticed.',
      'Live view shows distance to go, distance driven, elapsed time, speed '
          'and GPS accuracy.',
      'Close out a stop with the recipient name and a photo, or record why it '
          'could not be delivered.',
      'Sort the day by time slot or by which stop is nearest.',
      'Get a notification when you come within range of a stop, so you do '
          'not miss it while your nav app is on screen.',
      'A home screen with the day at a glance: progress, distance driven, '
          'what is next, and driving conditions.',
      'History keeps every closed stop with the distance and time it took.',
      'Themes, accent colours, an AMOLED black mode, miles or kilometres, '
          'haptics and GPS accuracy are all yours to set.',
      'Your stops, routes and photos never leave the phone. The weather card '
          'is the one exception, and it can be switched off.',
    ],
  ),
];

/// The version this build is showing notes for.
ReleaseNote get currentRelease => releaseNotes.first;

/// Looks up notes by version or tag; accepts `1.0.0` and `v1.0.0` alike.
ReleaseNote? releaseNoteFor(String versionOrTag) {
  final wanted = versionOrTag.startsWith('v')
      ? versionOrTag.substring(1)
      : versionOrTag;
  for (final note in releaseNotes) {
    if (note.version == wanted) return note;
  }
  return null;
}

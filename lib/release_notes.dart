/// Release notes, written once and rendered in two places: the in-app
/// "What's new" sheet and the GitHub release body.
///
/// This file must stay free of Flutter imports — `tool/generate_release_notes`
/// imports it under plain `dart run`, which has no Flutter SDK available.
library;

/// One line of a changelog: a short bold [title] and an optional plain
/// [detail].
///
/// Split rather than one string so both renderers can emphasise the same part.
/// Embedding markdown in the text would work on GitHub and show up as literal
/// asterisks in the app.
class ReleaseChange {
  const ReleaseChange(this.title, [this.detail]);

  /// A few words. Rendered bold.
  final String title;

  /// The sentence explaining it, if it needs one.
  final String? detail;
}

class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.headline,
    this.highlights = const [],
    this.fixes = const [],
    this.minor = const [],
  });

  /// Must match `version:` in pubspec.yaml minus the `+build` suffix.
  /// A test enforces this for the newest entry.
  final String version;

  final DateTime date;

  /// One line summarising the release, shown as the sheet's subtitle.
  final String headline;

  /// The reasons to care about this release. Keep it to a handful — if
  /// everything is a highlight, nothing is.
  final List<ReleaseChange> highlights;

  /// Things that were broken and now are not.
  final List<ReleaseChange> fixes;

  /// Everything else. Worth recording, not worth a driver's attention.
  final List<String> minor;

  /// Tag form, e.g. `v1.0.0-beta.1`.
  String get tag => 'v$version';

  /// A hyphen means a prerelease: `1.0.0-beta.1` yes, `1.0.0` no. The release
  /// workflow applies the same rule to decide GitHub's prerelease flag.
  bool get isPrerelease => version.contains('-');

  /// Used to guard against an entry that says nothing.
  bool get isEmpty => highlights.isEmpty && fixes.isEmpty && minor.isEmpty;
}

/// Newest first. The first entry is the current version.
///
/// Entries are append-only. A released version's notes are what shipped under
/// that number, so later work goes into a new entry rather than being folded
/// back into the last one.
final releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.0.0-beta.3',
    date: DateTime.utc(2026, 8, 12),
    headline: 'Clock on with a tap.',
    highlights: [
      ReleaseChange(
        'Clock on and off',
        'Your shift is tracked separately from the individual drops, so the '
            'app knows how long you were actually working — not just the time '
            'spent driving between stops.',
      ),
      ReleaseChange(
        'Tap a tag to start',
        'Stick an NFC tag in the van and tap it to clock on. Completely '
            'optional: there is always a button, and phones without NFC are '
            'not left out.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'The photo requirement is honest',
        'With "require a proof photo" switched on, the button said optional '
            'and then refused the delivery afterwards. It now says required '
            'and tells you before you fill anything in.',
      ),
      ReleaseChange(
        'Failed stops confirm too',
        'Recording a stop as undelivered dropped you back to the list with no '
            'sign it had registered.',
      ),
    ],
    minor: [
      'Onboarding asks for your name and van, and can write an NFC tag for '
          'you on the spot.',
      'Pair a van tag any time from Settings.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.2',
    date: DateTime.utc(2026, 8, 11),
    headline: 'A home screen, driving conditions, and a lot more control.',
    highlights: [
      ReleaseChange(
        'A new Home screen',
        'How the day is going, how far you have driven, what is next, and one '
            'tap to get on with it.',
      ),
      ReleaseChange(
        'Driving conditions',
        'With a warning when there is ice, fog, snow, heavy rain, or wind '
            'strong enough to matter in a high-sided van.',
      ),
      ReleaseChange(
        'Arrival alerts',
        'A notification when you come within range of a stop, so you do not '
            'miss it while your nav app is on screen.',
      ),
      ReleaseChange(
        'Slide to complete',
        'A bump in the cab can no longer close out the wrong stop. Switch it '
            'back to a tap in Settings.',
      ),
      ReleaseChange(
        'Make it yours',
        'Themes, six accent colours, an AMOLED black mode, miles or '
            'kilometres, haptics, and a GPS setting that trades battery for '
            'detail.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'The location button works',
        'Tapping it on the live map did nothing until you had driven far '
            'enough for a new fix.',
      ),
      ReleaseChange(
        'The slider unsticks',
        'Backing out of the completion sheet left it stuck at the end, so the '
            'stop could never be closed.',
      ),
    ],
    minor: [
      'Closing out a stop now shows what that trip took, and where you are '
          'heading next.',
      'Put your name and van on the app so the home screen greets you '
          'properly.',
      'Add more stops from the manifest when you need a bigger round to test '
          'with.',
      'Replay the introduction any time from Settings.',
      'Require a proof photo before a stop can be closed, if your depot works '
          'that way.',
      'Your stops, routes and photos still never leave the phone. The weather '
          'card is the one exception, and it can be switched off.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.1',
    date: DateTime.utc(2026, 8, 11),
    headline: 'First beta: your round, tracked end to end.',
    highlights: [
      ReleaseChange(
        'Track a delivery end to end',
        'From starting the stop to the doorstep, with your route recorded as '
            'you drive.',
      ),
      ReleaseChange(
        'Keeps running in your pocket',
        'Tracking survives the screen going off or you switching to your nav '
            'app, and shows a notification the whole time so it can never run '
            'unnoticed.',
      ),
      ReleaseChange(
        'Proof at the door',
        'Close out a stop with a name and a photo, or record why it could not '
            'be delivered.',
      ),
    ],
    minor: [
      'Live view shows distance to go, distance driven, elapsed time, speed '
          'and GPS accuracy.',
      'Sort the day by time slot or by which stop is nearest.',
      'History keeps every closed stop with the distance and time it took.',
      'Everything stays on the device. Nothing is uploaded.',
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

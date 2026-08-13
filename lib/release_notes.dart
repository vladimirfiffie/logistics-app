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
    version: '1.0.0-beta.8',
    date: DateTime.utc(2026, 8, 12),
    headline: 'The end of the day, and a live view that gets out of the way.',
    highlights: [
      ReleaseChange(
        'The day, added up',
        'Clocking off no longer flashes a line of grey text at you. It shows '
            'the hours you worked with the breaks taken out, what you '
            'delivered, how far it took and what it came to.',
      ),
      ReleaseChange(
        'How far, and how long',
        'The live view says how much is left to the stop and roughly how long '
            'it will take, worked out from the pace you are actually driving '
            'rather than the speed at the moment you look.',
      ),
      ReleaseChange(
        'Fold the panel away',
        'Pull the trip panel down to a single line — the stop and the '
            'distance left — and the map gets the rest of the screen. A tap '
            'brings it back.',
      ),
      ReleaseChange(
        "Arriving looks like arriving",
        'Pull up at the stop and the panel turns green, leads with the '
            'customer, and puts the two buttons you actually need at the top '
            'of it. If you had folded it away, it opens itself.',
      ),
      ReleaseChange(
        'Single or multiple parcels',
        'Adding stops asks whether you want one box per drop, three to nine, '
            'or a mix — the two cases are different jobs at the door.',
      ),
    ],
    minor: [
      'Parcels on board are not shown while you are clocked off.',
      'The accuracy and fix count stand down from the live panel once you '
          'are at the door, where they have nothing to say.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.7',
    date: DateTime.utc(2026, 8, 12),
    headline: 'Scan the parcel, chase the failed drop, count the money.',
    highlights: [
      ReleaseChange(
        'Scan the parcel, find the stop',
        'Point the camera at a label and land on its stop — no reading a '
            'reference off the screen with a box in each hand. At the door, '
            'scan the parcels off one by one so you know all six went in.',
      ),
      ReleaseChange(
        'A failed stop goes somewhere',
        'Say what happens to it: carded and back tomorrow morning, another go '
            'in two hours, or back to the depot. The first two put it on your '
            'run again as a second attempt, and the failed one stays in your '
            'history.',
      ),
      ReleaseChange(
        'What the day was worth',
        'Put in an hourly rate and a rate per mile, and your timesheet adds '
            'up the hours, the mileage claim and the total for each week. '
            'Leave them empty and no money appears anywhere.',
      ),
      ReleaseChange(
        'Call or text the customer',
        'A number on the stop, with a button to ring it and a button that '
            'opens a message already written. Sending it is your tap — the '
            'app never messages anyone on its own.',
      ),
      ReleaseChange(
        'Search your history',
        'Find a stop by reference, customer, street, label or who signed for '
            'it, and narrow it to today, this week or this month.',
      ),
      ReleaseChange(
        'A route that keeps your slots',
        'Best route no longer moves an afternoon booking ahead of a morning '
            'one — it reorders within a time window only, and it unpicks the '
            'doubling-back the old ordering was prone to.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'Starting a stop checks the clock',
        'It began recording whether or not you had clocked on, so the '
            'distance was kept and the hours were not. It now offers to clock '
            'you on first — or to carry on without, if that is what you meant.',
      ),
    ],
    minor: [
      'The home screen holds back the progress ring and the day\'s figures '
          'until there is a day to report, so first thing in the morning it '
          'shows your shift and your next stop.',
      'Setup ends with a page listing your name, van, theme and units, and '
          'takes you back to any of them with a tap.',
      'Pick light, dark or follow-my-phone during setup rather than hunting '
          'for it afterwards.',
      'A stop being tried for the second time says so on the manifest.',
      'Your timesheet shows the distance driven on each shift, whether or not '
          'you have set any rates.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.6',
    date: DateTime.utc(2026, 8, 12),
    headline: 'More screen, greener ticks, and settings you can find.',
    highlights: [
      ReleaseChange(
        'Every page starts at the top',
        'The big title bar above each tab is gone, and with it the grey slab '
            'that slid in the moment you dragged the page. The screen is for '
            'your round, not for a word already printed on the tab underneath.',
      ),
      ReleaseChange(
        'History, rebuilt',
        'Grouped under Today and Yesterday, with a card for how the day went '
            'and a card per stop carrying the outcome, the time, who signed '
            'for it and how far you drove to get there.',
      ),
      ReleaseChange(
        'Delivered is green',
        'A closed-out stop was coming out purple, orange or red depending on '
            'your accent colour. Green means delivered now — on the chip, on '
            'the stop, in history and on your timesheet — whatever theme you '
            'run.',
      ),
      ReleaseChange(
        'Settings you can find',
        'One list of sixty rows is now twelve categories, each on its own '
            'screen and each saying what is set inside it. Checking a value '
            'usually no longer means opening anything.',
      ),
      ReleaseChange(
        'Writing a van tag shows its working',
        'Tapping "write a van tag" opens the same reader you clock on with: '
            'hold the sticker there, and it tells you the tag is ready, or '
            'that this particular tag will never work and why.',
      ),
      ReleaseChange(
        'Just the map',
        'Long press the live map to clear everything off it, and long press '
            'again to bring it back. Useful on a windscreen mount, where the '
            'panel covers the road you are looking at.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'No grey bar on a pull-down',
        'Dragging any page down slid a grey block in behind the title. It was '
            'the app bar tinting itself, and it is gone everywhere.',
      ),
      ReleaseChange(
        'Back to work asks first',
        'Ending a break was one tap with no confirmation, on the same button '
            'that starts one — and the minutes are already on your timesheet '
            'by the time you notice.',
      ),
    ],
    minor: [
      'Units are called Metric and Imperial, in setup and in Settings, rather '
          'than "km / km-h" and "mi / mph".',
      'Setup says what your unit choice does to the weather card as you pick '
          'it.',
      'History counts your trips and total driving alongside the distance.',
      'The tag writer replaces the row that spun and then fired a message you '
          'had already stopped looking at.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.5',
    date: DateTime.utc(2026, 8, 12),
    headline: 'Timesheets, breaks, exports and a route that plans itself.',
    highlights: [
      ReleaseChange(
        'Your timesheet',
        'Every shift you have worked, grouped by week, with breaks subtracted '
            'so the total is what you are actually paid for. In Settings, '
            'under Shift.',
      ),
      ReleaseChange(
        'Take a break',
        'One tap to pause the clock and one to start again. Rest, lunch or '
            'other, and the app can nudge you if you have been going too '
            'long.',
      ),
      ReleaseChange(
        'Export your day',
        'Stops and mileage as a spreadsheet, your recorded routes as GPX. '
            'Both share straight out to wherever your expenses go.',
      ),
      ReleaseChange(
        'A route that plans itself',
        'Sort the run by best route and the app orders the remaining stops '
            'nearest-first, telling you how much shorter it is. A suggestion '
            '— your slots and the roads still win.',
      ),
      ReleaseChange(
        'Sign at the door',
        'Capture a signature alongside the photo. Off, optional or required, '
            'whichever way your depot works.',
      ),
      ReleaseChange(
        'Know you are on the clock',
        'An ongoing notification for as long as your shift is running, so the '
            'answer is in the shade rather than three taps away.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'Cleared history clears the photos',
        'Clearing history left every proof photo and signature behind on the '
            'phone, filling up storage with images of deliveries that no '
            'longer exist.',
      ),
      ReleaseChange(
        'Long shifts stay quick',
        'The recorded trail was copied in full on every GPS fix, so a ten-hour '
            'round got slower the longer you worked.',
      ),
      ReleaseChange(
        'No repeat arrival alerts',
        'If the app was killed mid-trip, coming back told you again about a '
            'stop you had already reached.',
      ),
      ReleaseChange(
        'Coming-up numbers are right',
        'The list under "coming up" numbered from two, so every stop was '
            'labelled as the one after it.',
      ),
      ReleaseChange(
        'Arrival alerts admit when blocked',
        'The switch stayed on after the notification permission was refused, '
            'promising alerts that could never arrive.',
      ),
    ],
    minor: [
      'Search the run by reference, customer or street.',
      'Pick your own units for temperature, wind and rain, and your own date '
          'and time formats.',
      'Start the next stop straight after closing one — as a button on the '
          'summary, or automatically.',
      'Settings is organised into sections and subsections rather than one '
          'long list.',
      'A clocked-off shift can no longer have its end time rewritten.',
    ],
  ),
  ReleaseNote(
    version: '1.0.0-beta.4',
    date: DateTime.utc(2026, 8, 12),
    headline: 'The clock, the stop button, and units that are yours.',
    highlights: [
      ReleaseChange(
        'Set the units you read',
        'Temperature is its own choice now instead of following miles and '
            'kilometres — pick Celsius or Fahrenheit outright. Dates come in '
            'five formats, and the clock does 12- or 24-hour.',
      ),
      ReleaseChange(
        'The van tag has a proper home',
        'Settings tells you whether this phone can do NFC, lets you write a '
            'tag, reads one back so you can check it works, and lets you turn '
            'the tag prompt off entirely.',
      ),
      ReleaseChange(
        'Less clutter at the top',
        'The icons above each page are gone. Settings is a card on Home, '
            '"add stops" is a button on the manifest, and sorting is a row of '
            'chips — now including A to Z.',
      ),
    ],
    fixes: [
      ReleaseChange(
        'Your shift clock runs',
        'It sat at "0s" all day. It now counts up while you are clocked on.',
      ),
      ReleaseChange(
        'Clocking on says what happened',
        'If it failed it did so silently, leaving the button looking dead. '
            'Clocking off asks first and tells you how long you worked.',
      ),
      ReleaseChange(
        'Stop recording actually stops',
        'The stop stayed "In transit" with nothing recording behind it. '
            'Stopping now asks first, offers to keep sharing, confirms when it '
            'is done, and puts the stop back on the manifest.',
      ),
      ReleaseChange(
        'Finished stops keep their distance',
        'Closing out a stop was deleting the route it had just recorded, so '
            'the distance you drove to it vanished the moment you delivered.',
      ),
    ],
    minor: [
      'Clocking off stops a trip that is still recording, rather than leaving '
          'the GPS running after your day has ended.',
      'The arrival alert clears itself when the trip it belongs to finishes.',
      'The weather card shows what the temperature feels like.',
    ],
  ),
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

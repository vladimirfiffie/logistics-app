# Logistics — driver app

A Flutter delivery-driver app that records where you drive. Pick a stop from
the day's manifest, start the trip, and the app tracks your route in the
background, keeping a running distance and time against that stop until you
close it out with a name and a photo.

Delivery data is stored on the device in SQLite. There is no backend for your
stops, routes or photos.

Two features do use the network: map tiles come from OpenStreetMap (which sees
requests for images, not your position), and the optional weather card sends
your approximate position to Open-Meteo. That card can be switched off in
Settings.

## What's in it

- **Home** — the day at a glance: progress ring, distance driven, what's next,
  and driving conditions with a warning for ice, fog, snow or strong wind.
- **Manifest** — the day's stops, sortable by time slot or by how far away
  they are, with a live "GPS locked" indicator and parcel counts.
- **Live tracking** — an OpenStreetMap view with your breadcrumb trail, the
  destination pin, and readouts for distance to go, distance driven, elapsed
  time, speed, fix accuracy and the number of fixes recorded.
- **Proof of delivery** — recipient name plus an optional photo, copied out of
  the camera cache into app storage so it survives a cache purge.
- **Failed stops** — a reason is recorded from a preset list or free text.
- **Arrival alerts** — a notification when you come within a set radius of the
  stop, because the phone is usually showing a nav app rather than this one.
- **History** — closed stops with the distance and time recorded getting to
  each one, and totals for the day.
- **Settings** — theme, accent colour, AMOLED black, miles or kilometres,
  GPS accuracy preset, keep-screen-on, slide-to-confirm, haptics, arrival
  alerts, proof-photo enforcement, permissions, and data clearing.

## Running it

```sh
flutter pub get
flutter run
```

On first launch the app explains what it records, asks for location, then
seeds a starter manifest of six stops scattered a few kilometres around
wherever you are. Decline location and it seeds around a fallback origin
instead. The seed only ever runs against an empty database.

## Layout

```
lib/
  models/       Delivery, Trip, TripPoint — plain data + map serialisation
  data/         DeliveryRepository (interface) and its SQLite implementation
  services/     LocationService (the only place geolocator is touched),
                NotificationService, WeatherService, AppHaptics
  state/        DeliveryController, TrackingController (ChangeNotifier)
  ui/           screens, shared widgets, formatters
```

Two seams are worth knowing about:

- **`DeliveryRepository`** is the only storage contract the UI knows. Pointing
  the app at a real dispatch backend means writing another implementation and
  changing the one construction site in `lib/main.dart`.
- **`LocationService`** wraps geolocator so nothing else imports the plugin,
  which is what lets the controllers be tested against a fake GPS.

## Tests

```sh
flutter test
```

48 tests covering the SQLite repository (against in-memory SQLite via
`sqflite_common_ffi`), both controllers against fakes, the seeding rules, the
model serialisation, and the display formatters. The tracking tests cover the
things that are easy to get wrong: the odometer excluding low-accuracy fixes,
a failed write not tearing down a live trip, and a trip left open by a killed
process being picked back up on launch.

## Android permissions

| Permission | Why |
| --- | --- |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Recording the route |
| `ACCESS_BACKGROUND_LOCATION` | Fixes with the screen off; requested separately from the live view |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION` | The tracking service |
| `POST_NOTIFICATIONS` | Android 13+ gates the tracking notification |
| `INTERNET` | Map tiles from OpenStreetMap |

Tracking always runs as a foreground service with a persistent notification,
so it can't run unnoticed. Recording only happens between starting a trip and
closing the stop.

## Signing

**Debug builds need no keystore.** `flutter run` and `flutter build apk
--debug` sign with the SDK's auto-generated debug key. That covers development
and sideloading onto your own device, and it's all CI builds.

You need a keystore only to ship a **release** build — Play Store upload, or
an APK for someone else's device. Right now `android/app/build.gradle.kts`
still has the scaffold's `signingConfig = signingConfigs.getByName("debug")`
under `release`, so a release build technically succeeds but is signed with
the debug key, which Play rejects.

To set one up:

```sh
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (already gitignored, along with `*.jks`
and `*.keystore` — keep it that way):

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/home/you/upload-keystore.jks
```

and wire it into the `release` block per
[the Flutter signing guide](https://docs.flutter.dev/deployment/android#signing-the-app).
Losing this file means losing the ability to update the app on Play, so back
it up somewhere that isn't this repo.

## CI

`.github/workflows/build.yml` runs on every push and PR, in two jobs:

- **analyze & test** — format check, `flutter analyze --fatal-infos`,
  `flutter test`. No Android toolchain, so it fails in about a minute.
- **split apks** — builds one APK per ABI and uploads them as a workflow
  artifact. Gated behind the first job.

Grab the APKs from the run's **Artifacts** section in the Actions tab.

### Releases

`.github/workflows/release.yml` builds split **and** universal APKs and
publishes them to GitHub Releases. Three ways in, all ending in the same
place:

**1. Bump the version and push to main — the usual route.** Edit `version:` in
`pubspec.yaml`, add a matching `lib/release_notes.dart` entry, push. If no
release exists for that version yet, one is cut. Needs no tag push, so it
works without git credentials.

**2. From the Actions tab.** **Release** → **Run workflow** → enter a version
in `tag`. Also credential-free; the tag is created server-side.

**3. By pushing a tag:**

```sh
git tag v1.0.0-beta.1 && git push origin v1.0.0-beta.1
```

Note `git push` alone never sends tags — you have to name the tag (or pass
`--tags`). That is the usual reason a tag-triggered release "doesn't happen":
the branch went up and the tag didn't.

A cheap `decide` job runs first and works out whether there is anything to
publish, so an ordinary push that didn't touch the version costs ten seconds
rather than a six-minute Gradle build. If the version is already released it
logs a notice saying so and stops.

**A hyphen in the tag makes it a prerelease.** `v1.0.0-beta.1` is a
prerelease; `v1.0.0` is a full release and gets GitHub's "Latest" badge. This
matters more than it looks — if *every* release is flagged prerelease, then
`/releases/latest` returns 404 and the releases page degrades into a bare
list of tags.

Until an upload keystore exists, everything published here is debug-signed
and sideload-only, so keep cutting hyphenated tags.

### Release notes

`lib/release_notes.dart` is the single source. It feeds both:

- the in-app **What's new** sheet, shown once after an update (and reachable
  any time from the icon in History's app bar), and
- the GitHub release body, rendered by
  `dart run tool/generate_release_notes.dart <tag>` during the release job.

So writing a release means adding one `ReleaseNote` entry and bumping
`version:` in pubspec.yaml. A test fails if those two disagree, which is what
stops the app from claiming one version while the release page describes
another. That file deliberately imports no Flutter, because the `tool/` script
runs under plain `dart run` with no Flutter SDK.

An unknown tag is not fatal — it emits a placeholder body and warns on stderr,
so a `v0.0.0-manual` build still publishes.

Every tag is marked prerelease deliberately: while the APKs are debug-signed
they are sideload-only, and calling that a stable release would be a lie.
Wire up signing as described above before cutting anything stable. The job
uses the built-in `GITHUB_TOKEN`, so there is nothing to configure.

Three files come out, named for the tag (or the short commit sha on branch
builds):

| File | For |
| --- | --- |
| `arm64-v8a` | Almost every phone made since ~2017. **Start here.** |
| `armeabi-v7a` | Older 32-bit devices. |
| `x86_64` | Emulators and x86 Chromebooks. |

Splitting avoids shipping all three architectures' native code to every
device, which is most of the download for a Flutter app. Installing the wrong
one fails with `INSTALL_FAILED_NO_MATCHING_ABIS` — that's the wrong file, not
a broken build.

These are release builds signed with the **debug** key, since no upload
keystore exists yet. They sideload fine (`adb install <file>`) but cannot go
to Google Play until signing is wired up as described above.

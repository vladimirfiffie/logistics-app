/// Renders the GitHub release body for a tag, from the same data the in-app
/// "What's new" sheet uses, so the two cannot drift.
///
///     dart run tool/generate_release_notes.dart v1.0.0-beta.1 > RELEASE_NOTES.md
library;

import 'dart:io';

import 'package:logistics_app/release_notes.dart';

const _installNotice = '''
> **Debug-signed — sideload only.**
> These APKs are signed with the Android debug key, not an upload key, so they
> install for testing but cannot be published to Google Play.
> See `README.md` > Signing.
''';

const _abiTable = '''
### Which file do I want?

| File | For |
| --- | --- |
| `universal` | Works on anything. Pick this if unsure. |
| `arm64-v8a` | Almost every phone since ~2017. Smallest sensible choice. |
| `armeabi-v7a` | Older 32-bit devices. |
| `x86_64` | Emulators and x86 Chromebooks. |

Install with `adb install <file>`, or copy it to the device and allow installs
from unknown sources. Installing the wrong ABI fails with
`INSTALL_FAILED_NO_MATCHING_ABIS` — that is the wrong file, not a broken build.
''';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/generate_release_notes.dart <tag>');
    exit(64); // EX_USAGE
  }

  final tag = args.single;
  final note = releaseNoteFor(tag);
  final buffer = StringBuffer()..writeln(_installNotice);

  if (note == null) {
    // Deliberately not fatal: manual builds (v0.0.0-manual) and hotfix tags
    // are legitimate. But say so loudly rather than emitting a body that
    // looks authored when nobody wrote one.
    stderr.writeln(
      'warning: no release note for "$tag" in lib/release_notes.dart — '
      'emitting a placeholder body.',
    );
    buffer
      ..writeln('## $tag')
      ..writeln()
      ..writeln(
        'No release notes were written for this build. See the commit log '
        'for what changed.',
      );
  } else {
    final date = note.date.toIso8601String().split('T').first;
    buffer
      ..writeln('## ${note.tag} — $date')
      ..writeln()
      ..writeln(note.headline)
      ..writeln();
    for (final change in note.changes) {
      buffer.writeln('- $change');
    }
  }

  buffer
    ..writeln()
    ..write(_abiTable);

  stdout.write(buffer);
}

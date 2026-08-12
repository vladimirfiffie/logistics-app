import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/services/export_service.dart';

void main() {
  group('CSV escaping', () {
    test('quotes every field so a comma cannot shift a column', () {
      expect(
        ExportService.csvRow(const ['LG-1', '14 Bridgewater Road, Unit 3']),
        '"LG-1","14 Bridgewater Road, Unit 3"',
      );
    });

    test('doubles embedded quotes rather than breaking the row', () {
      // A customer called O'Brien & Sons "Ltd" is not exotic, and getting
      // this wrong silently corrupts every later column.
      expect(
        ExportService.csvRow(const ['O\'Brien & Sons "Ltd"']),
        '"O\'Brien & Sons ""Ltd"""',
      );
    });

    test('keeps empty fields as empty columns', () {
      expect(ExportService.csvRow(const ['a', '', 'c']), '"a","","c"');
    });

    test('survives a newline inside a field', () {
      // RFC 4180 allows this inside quotes, which is why every field is
      // quoted rather than only the ones that look risky.
      expect(
        ExportService.csvRow(const ['line one\nline two']),
        '"line one\nline two"',
      );
    });
  });

  group('XML escaping', () {
    test('escapes the five characters that would break a GPX file', () {
      expect(
        ExportService.xmlEscape('Fish & Chips <"Ltd"> \'x\''),
        'Fish &amp; Chips &lt;&quot;Ltd&quot;&gt; &apos;x&apos;',
      );
    });

    test('escapes ampersands before the entities it introduces', () {
      // Getting the order wrong yields "&amp;lt;" for a bare "<".
      expect(ExportService.xmlEscape('<'), '&lt;');
      expect(ExportService.xmlEscape('&'), '&amp;');
      expect(ExportService.xmlEscape('&lt;'), '&amp;lt;');
    });

    test('leaves ordinary text alone', () {
      expect(ExportService.xmlEscape('LG-1040 Harlow'), 'LG-1040 Harlow');
    });
  });
}

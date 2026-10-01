import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/telemetry/pdf_builder.dart';
import 'package:pcx_telemetry_app/core/telemetry/ride_report_pdf.dart';
import 'package:pcx_telemetry_app/core/trip/trip_manager.dart';

TripRecord trip(Map<String, dynamic> o) => TripRecord.fromJson({
      'id': 't1',
      'startTime': '2026-01-01T01:00:00.000Z',
      'endTime': '2026-01-01T01:42:00.000Z',
      'durationMin': 42.0,
      'distanceKm': 18.4,
      'avgSpeedKmh': 26.3,
      'maxSpeedKmh': 74.0,
      'fuelConsumedL': 3.2,
      'avgKml': 57.5,
      'tripCostIdr': 41440,
      'maxEctC': 94.0,
      'maxLeanLeftDeg': 41.0,
      'maxLeanRightDeg': 44.5,
      'hardBrakingCount': 2,
      'routePolyline': 'abc',
      'timelineData': '[]',
      'synced': true,
      ...o,
    });

String asText(List<int> bytes) => String.fromCharCodes(bytes);

void main() {
  group('PdfReport — file structure', () {
    test('produces a non-empty file with the %PDF magic header', () {
      final bytes = buildRideReportPdf(trip({}));
      expect(bytes.isNotEmpty, isTrue);
      expect(asText(bytes.sublist(0, 5)), '%PDF-');
    });

    test('ends with a well-formed EOF marker', () {
      final bytes = buildRideReportPdf(trip({}));
      expect(asText(bytes.sublist(bytes.length - 6)), '%%EOF\n');
    });

    test('declares the correct object count in the xref table', () {
      final bytes = buildRideReportPdf(trip({}));
      final text = asText(bytes);
      expect(text.contains('xref\n0 7\n'), isTrue,
          reason: 'catalog, pages, page, two fonts, one content stream');
    });

    test('every startxref offset points at the matching object header', () {
      // A wrong offset makes the file unopenable rather than merely ugly, and
      // it is invisible unless you actually parse the table.
      final bytes = buildRideReportPdf(trip({}));
      final text = asText(bytes);

      final startxrefIdx = text.lastIndexOf('startxref\n');
      expect(startxrefIdx, greaterThan(0));
      final xrefPos = int.parse(
          text.substring(startxrefIdx + 10, text.lastIndexOf('%%EOF')).trim());

      expect(asText(bytes.sublist(xrefPos, xrefPos + 4)), 'xref');

      // Parse the table and confirm each offset lands on "<n> 0 obj".
      final tableStart = xrefPos + 4;
      final entries = RegExp(r'(\d{10}) 00000 n').allMatches(text).toList();
      expect(entries.length, 6, reason: 'objects 1..6');
      for (final m in entries) {
        final off = int.parse(m.group(1)!);
        final at = asText(bytes.sublist(off, off + 8));
        expect(at, matches(RegExp(r'^\d+ 0 obj')),
            reason: 'offset $off should start an object header, got "$at"');
      }
      expect(tableStart, greaterThan(0));
    });

    test('the content stream length matches the bytes written', () {
      final bytes = buildRideReportPdf(trip({}));
      final text = asText(bytes);
      final m = RegExp(r'<< /Length (\d+) >>\nstream\n').firstMatch(text);
      expect(m, isNotNull, reason: 'a length declaration is required');

      final declared = int.parse(m!.group(1)!);
      final streamStart = m.end;
      final endMarker = text.indexOf('\nendstream', streamStart);
      final actual = endMarker - streamStart;
      expect(actual, declared,
          reason: 'a wrong Length makes viewers refuse to open the file');
    });

    test('an empty report still produces a valid file', () {
      final bytes = buildRideReportPdf(trip({
        'distanceKm': 0.0,
        'durationMin': 0.0,
        'maxEctC': 0.0,
        'fuelConsumedL': 0.0,
      }));
      expect(bytes.isNotEmpty, isTrue);
      expect(asText(bytes.sublist(0, 5)), '%PDF-');
      expect(asText(bytes.sublist(bytes.length - 6)), '%%EOF\n');
    });
  });

  group('PdfReport — escaping', () {
    test('parentheses in the content cannot terminate a PDF string', () {
      // A route name or a bike nickname with brackets would otherwise produce a
      // malformed file that fails to open, with no error at build time.
      final p = PdfReport();
      p.line('Test (with) parens \\ and more', 12);
      final text = asText(p.build());

      expect(text.contains(r'Test \(with\) parens'), isTrue);
      expect(text.contains(r'\(with\)'), isTrue);
    });

    test('a backslash is escaped rather than consumed', () {
      final p = PdfReport();
      p.line(r'C:\path\to', 12);
      final text = asText(p.build());
      expect(text.contains(r'C:\\path\\to'), isTrue);
    });
  });

  group('PdfReport — honesty', () {
    test('a pre-Sprint-3 trip omits the braking section entirely', () {
      final text = asText(buildRideReportPdf(trip({})));
      // It must not claim the rider never engine-braked.
      expect(text.contains('PENANGANAN KECEPATAN'), isFalse);
      expect(text.contains('Engine brake'), isFalse);
    });

    test('a trip with braking data includes the split', () {
      final text = asText(buildRideReportPdf(trip({
        'engineBrakingCount': 9,
        'serviceBrakingCount': 3,
        'engineBrakeSeconds': 28.5,
      })));
      expect(text.contains('PENANGANAN KECEPATAN'), isTrue);
      expect(text.contains('Engine brake'), isTrue);
      expect(text.contains('9 kali'), isTrue);
      expect(text.contains('28.5 detik'), isTrue);
      expect(text.contains('75%'), isTrue,
          reason: '9 of 12 events were engine braking');
    });

    test('an unmeasured coolant temp omits the engine section', () {
      final text = asText(buildRideReportPdf(trip({'maxEctC': 0.0})));
      expect(text.contains('Suhu radiator'), isFalse);
    });

    test('an overheat figure is still reported, in red', () {
      final text = asText(buildRideReportPdf(trip({'maxEctC': 108.0})));
      expect(text.contains('108 C'), isTrue);
    });
  });

  group('PdfReport — overflow', () {
    test('rows stop at the bottom margin instead of drawing off-page', () {
      final p = PdfReport();
      var placed = 0;
      for (var i = 0; i < 400; i++) {
        if (p.row('Label $i', 'Value $i')) {
          placed++;
        } else {
          break;
        }
      }
      expect(placed, greaterThan(20));
      expect(placed, lessThan(80),
          reason: 'an A4 page fits ~60 rows at 10pt, not 400');
      expect(p.hasRoom, isFalse);
    });

    test('the report builder itself never throws on a sparse trip', () {
      for (final t in [
        trip({}),
        trip({'distanceKm': 0.0, 'fuelConsumedL': 0.0, 'maxEctC': 0.0}),
        trip({'engineBrakingCount': 999, 'serviceBrakingCount': 1}),
      ]) {
        expect(() => buildRideReportPdf(t), returnsNormally);
      }
    });
  });
}
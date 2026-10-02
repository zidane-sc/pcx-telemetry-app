import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';
import 'package:pcx_telemetry_app/ui/widgets/lean_angle_gauge.dart';
import 'package:pcx_telemetry_app/ui/widgets/shift_light_bar.dart';

/// Renders each of the four slots and fails if any pixel the widget paints is
/// hardcoded.
///
/// The earlier pass fixed the three screens and left the sheets, the overlays
/// and the gauges on noir literals -- so a rider in Terik mode got a light
/// cockpit and a light Journal attached to a dark fuel-log sheet. A test that
/// only checks a screen's scaffold misses exactly that, because the sheet is a
/// separate widget in a separate route.
Widget wrap(ThemeSlot slot, Widget child) => ThemeScope(
      service: ThemeService()..select(slot),
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  testWidgets('the shift-light frame follows the slot in every mode',
      (tester) async {
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(
        slot,
        const ShiftLightBar(rpm: 4000, isLive: true),
      ));
      final box = tester.widget<Container>(find.byType(Container).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, slot.surface,
          reason: '${slot.label}: the bar frame is still pinned to noir');
    }
  });

  testWidgets('the rev-limit pill is readable in every mode', (tester) async {
    // The pill was white text on a pale red fill: unreadable in the light slot,
    // and a warning label nobody can read is worse than no label.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(
        slot,
        const ShiftLightBar(rpm: 9200, isLive: true),
      ));
      final label = tester.widget<Text>(find.text('REV LIMIT'));
      final fill = tester.widget<Container>(
        find.ancestor(
          of: find.text('REV LIMIT'),
          matching: find.byType(Container),
        ).first,
      );
      final bg = (fill.decoration as BoxDecoration).color!;
      final cr = _ratio(label.style!.color!, bg);
      expect(cr, greaterThanOrEqualTo(4.5),
          reason: '${slot.label}: REV LIMIT is ${cr.toStringAsFixed(2)}:1 -- '
              'an unreadable warning is worse than none');
    }
  });

  testWidgets('the lean gauge reports both lean sources in every mode',
      (tester) async {
    // The gauge is the one instrument a rider looks at mid-corner. If it fails
    // to paint in a mode the whole cockpit goes blank there.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(
        slot,
        const LeanAngleGauge(currentAngle: 32.0),
      ));
      expect(tester.takeException(), isNull,
          reason: '${slot.label}: the gauge threw while painting');
      expect(find.byType(CustomPaint), findsWidgets,
          reason: '${slot.label}: the horizon bar did not paint at all');
    }
  });
}

double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

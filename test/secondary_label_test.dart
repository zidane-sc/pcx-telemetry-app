import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/screens/trips_screen.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';
import 'package:pcx_telemetry_app/ui/widgets/shift_light_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The cockpit was the last screen standing on literals, and it is the one that
/// mattered: a rider on a phone holder in Terik mode was reading telemetry
/// labels at white@40% over a white background, which is the exact case where
/// the label disappears but the coloured number beside it stays.
Widget wrap(ThemeSlot slot, Widget child) => ThemeScope(
      service: ThemeService()..select(slot),
      child: MaterialApp(home: Scaffold(body: child)),
    );

double ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() {
    // ThemeService persists on every select(); the real platform channel never
    // answers inside the fake-async test zone.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a secondary label survives on the light surface', (tester) async {
    // Stands in for the RPM/TPS/LOAD/TIMING labels in the telemetry ribbon.
    // The failure it guards: white at 40% over #F1F5F9 measures 1.4:1, so the
    // label explaining the number was invisible while the number was not.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(
        slot,
        Builder(builder: (context) {
          final s = ThemeScope.slotOf(context);
          return Text('RPM', style: TextStyle(color: s.dim(0.4), fontSize: 9));
        }),
      ));
      final label = tester.widget<Text>(find.text('RPM'));
      final cr = ratio(label.style!.color!, slot.surface);
      expect(cr, greaterThanOrEqualTo(4.5),
          reason: '${slot.label}: a secondary label at '
              '${cr.toStringAsFixed(2)}:1 is decoration, not information');
    }
  });

  test('every slot gives its instrument channels distinct values', () {
    // RPM, TPS, LOAD and TIMING are told apart by hue, and each sits next to a
    // text label naming it. What must not happen is two channels resolving to
    // the same colour, because then hue stops being a usable signal. Their
    // contrast against each other is deliberately low -- Noir's teal and green
    // differ by 1.14:1 and always have, which is fine: the label beside each
    // number identifies the channel, not the colour alone.
    //
    // onAccent and elevated are excluded: Terik's are both white, correctly,
    // because a sheet on a white surface is meant to blend into it.
    for (final slot in ThemeSlot.values) {
      final channels = <Color>[
        slot.positive,
        slot.accent,
        slot.warning,
        slot.danger,
        slot.timing,
      ];
      expect(channels.toSet().length, channels.length,
          reason: '${slot.label}: two channels resolve to the same colour, so '
              'one carries no information the other does not');
    }
  });

  testWidgets('the four slots render the journal without an exception',
      (tester) async {
    // The whole point of the exercise: switching slot must not break anything.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(slot, const TripsScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${slot.label} threw');
    }
  });

  testWidgets('the shift light still renders when the RPM is live',
      (tester) async {
    // Theming must not have cost the bar its function. A shift light that never
    // lights is worse than one in the wrong palette.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(
        slot,
        const ShiftLightBar(rpm: 7000, isLive: true),
      ));
      await tester.pump();
      expect(find.byType(ShiftLightBar), findsOneWidget, reason: slot.label);
      expect(tester.takeException(), isNull, reason: '${slot.label} threw');
    }
  });
}
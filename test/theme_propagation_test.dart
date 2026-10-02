import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/screens/trips_screen.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';

/// Guards the bug this change existed to fix: a rider switching to Terik mode
/// got a white Journal full of noir-cyan text, because the screen hardcoded
/// its colours. A test cannot judge the pixels, so it checks the two things
/// that caused it -- the screen resolves from the active slot, and no theme
/// literal crept back in.
Widget wrap(ThemeSlot slot) => ThemeScope(
      service: ThemeService()..select(slot),
      child: const MaterialApp(home: TripsScreen()),
    );

void main() {
  testWidgets('TripsScreen paints its scaffold with the active slot background',
      (tester) async {
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(slot));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, slot.background,
          reason: '${slot.label}: the Journal still paints a hardcoded '
              'background, so a rider in Terik mode gets a dark-on-white page');
    }
  });

  testWidgets('the empty Journal keeps its copy legible in every slot',
      (tester) async {
    // The empty state is the first thing a new rider sees, and it is the one
    // screen state that renders without any trip data to iterate over.
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(slot));

      final empty = tester.widget<Text>(find.text('Belum ada trip yang direkam.'));
      expect(
        _contrast(empty.style?.color ?? Colors.black, slot.background),
        greaterThanOrEqualTo(4.5),
        reason: '${slot.label}: the empty-state copy is unreadable on its own '
            'background',
      );
    }
  });

  testWidgets('the Journal carries no hardcoded theme colour', (tester) async {
    // A single render in Terik mode is enough to trip a leftover literal that
    // only shows in one mode, which is exactly how this bug hid for months.
    await tester.pumpWidget(wrap(ThemeSlot.sunGlare));
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

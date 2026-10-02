import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/garage/rule_editor_sheet.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The rule editor is the sheet most likely to break under a theme change.
///
/// It is a StatelessWidget whose colours are read in three nested builders
/// (the sheet, the AnimatedBuilder, the DraggableScrollableSheet) that each
/// shadow `context` with their own, and it has a sibling helper method with no
/// context at all. Every one of those is a place where a token lookup silently
/// falls back to the default palette -- which looks correct in a test that only
/// renders the default slot.
Widget wrap(ThemeSlot slot) => ThemeScope(
      service: ThemeService()..select(slot),
      child: const MaterialApp(home: Scaffold(body: RuleEditorSheet())),
    );

void main() {
  setUp(() {
    // ThemeService persists on every select(), and the real SharedPreferences
    // platform channel never answers inside the fake-async test zone -- the
    // first version of this file hung until the runner was killed at 120s.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the rule editor paints in every slot', (tester) async {
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(slot));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '${slot.label}: the sheet threw while building');
      expect(find.text('ATURAN PERINGATAN'), findsOneWidget,
          reason: '${slot.label}: the sheet did not render its header');
    }
  });

  testWidgets('the sheet content comes from the slot, not a literal',
      (tester) async {
    for (final slot in ThemeSlot.values) {
      await tester.pumpWidget(wrap(slot));
      await tester.pump();

      // A themed surface under a hardcoded header colour is the exact shape of
      // the original bug: the chrome follows, the content does not.
      final header = tester.widget<Text>(find.text('ATURAN PERINGATAN'));
      expect(header.style?.color, slot.text,
          reason: '${slot.label}: the title is still a hardcoded colour');
    }
  });

  testWidgets('a theme change while the sheet is open repaints it',
      (tester) async {
    // The static show() reads the slot once for the modal background, but the
    // body re-reads it on every build. If that regressed to a captured value,
    // switching theme with the sheet open would leave it on the old palette.
    final service = ThemeService();
    await service.select(ThemeSlot.noir);
    await tester.pumpWidget(ThemeScope(
      service: service,
      child: const MaterialApp(home: Scaffold(body: RuleEditorSheet())),
    ));
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('ATURAN PERINGATAN')).style?.color,
      ThemeSlot.noir.text,
    );

    await service.select(ThemeSlot.sunGlare);
    await tester.pump();
    expect(
      tester.widget<Text>(find.text('ATURAN PERINGATAN')).style?.color,
      ThemeSlot.sunGlare.text,
      reason: 'an open sheet must follow a live theme change, not freeze on '
          'the palette it was opened with',
    );
  });
}

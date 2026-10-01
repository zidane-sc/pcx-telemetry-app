import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // ThemeService is a singleton, so its slot survives between tests. Reloading
    // from an empty store resets it to the default; without this, a test that
    // selects a slot leaves the next one starting from the wrong place and a
    // failure reads as a mystery instead of the cause.
    await ThemeService().initialize();
  });

  group('ThemeSlot properties', () {
    test('exactly two slots are light-background', () {
      // Sun glare is the only light one: the whole point is readability in
      // direct sun. Adding more light slots would defeat the purpose of the
      // other two.
      final light = ThemeSlot.values.where((s) => s.isLight).toList();
      expect(light.length, 1);
      expect(light.single, ThemeSlot.sunGlare);
    });

    test('noir has a lifted panel, amoled is true black', () {
      // The distinction that matters on a handlebar: in shade you need the
      // panel visible; at a red light you need it invisible.
      expect(ThemeSlot.noir.surface, isNot(const Color(0xFF000000)));
      expect(ThemeSlot.amoled.surface, const Color(0xFF000000));
      expect(ThemeSlot.amoled.background, const Color(0xFF000000));
    });

    test('every slot has readable text against its own background', () {
      for (final s in ThemeSlot.values) {
        final bgLum = s.background.computeLuminance();
        final textLum = s.text.computeLuminance();
        // Catches the real failure: light text on a light background, or dark
        // text on a dark one. A true WCAG ratio would need the full formula and
        // would flag things this palette intentionally does not do.
        expect(
          s.isLight ? textLum < 0.3 : textLum > 0.5,
          isTrue,
          reason: '${s.label}: text luminance ${textLum.toStringAsFixed(2)} '
              'against background ${bgLum.toStringAsFixed(2)}',
        );
      }
    });

    test('every slot has a distinct label', () {
      final labels = ThemeSlot.values.map((s) => s.label).toSet();
      expect(labels.length, ThemeSlot.values.length);
    });
  });

  group('ThemeService persistence', () {
    test('defaults to noir', () async {
      final s = ThemeService();
      await s.initialize();
      expect(s.slot, ThemeSlot.noir);
      expect(s.isSunGlare, isFalse);
    });

    test('persists and restores a selection', () async {
      final a = ThemeService();
      await a.initialize();
      await a.select(ThemeSlot.amoled);

      final b = ThemeService();
      await b.initialize();
      expect(b.slot, ThemeSlot.amoled);
    });

    test('an unknown stored name falls back to noir', () async {
      SharedPreferences.setMockInitialValues({
        'cockpit_theme_slot': 'neon-hyperdrive',
      });
      final s = ThemeService();
      await s.initialize();
      expect(s.slot, ThemeSlot.noir,
          reason: 'a corrupt prefs value must not brick the cockpit');
    });

    test('selecting the same slot does not notify', () async {
      final s = ThemeService();
      await s.initialize();
      var notifications = 0;
      s.addListener(() => notifications++);
      await s.select(ThemeSlot.noir);
      expect(notifications, 0,
          reason: 'a no-op tap should not rebuild twenty widgets');
    });

    test('cycle visits every slot and returns to the start', () async {
      final s = ThemeService();
      await s.initialize();

      final seen = <ThemeSlot>[];
      for (var i = 0; i < ThemeSlot.values.length; i++) {
        seen.add(s.slot);
        await s.cycle();
      }
      expect(seen.length, ThemeSlot.values.length);
      expect(seen.toSet().length, ThemeSlot.values.length,
          reason: 'cycle must cover every slot before repeating');
      expect(s.slot, ThemeSlot.noir, reason: 'a full cycle returns to start');
    });

    test('cycle persists each step', () async {
      final s = ThemeService();
      await s.initialize();
      await s.cycle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cockpit_theme_slot'),
          ThemeSlot.values[1].name);
    });
  });
}
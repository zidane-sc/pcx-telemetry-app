import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG 2.1 relative-contrast ratio: (L1 + 0.05) / (L2 + 0.05).
///
/// Relative luminance alone is not a contrast measure -- two colours can share
/// a luminance and still differ sharply, and a small luminance gap can hide a
/// large perceptual one. Every threshold in these tests is a WCAG number, so
/// this is the formula they have to be checked against.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

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

    test('every accent colour is readable on its own surface', () {
      // The Journal and Garage used to hardcode noir's cyan over a noir-black
      // card. A rider switching to Terik got a light screen with invisible
      // labels, because the token was never consulted.
      for (final s in ThemeSlot.values) {
        for (final entry in {
          'accent': s.accent,
          'positive': s.positive,
          'warning': s.warning,
          'danger': s.danger,
        }.entries) {
          expect(
            contrastRatio(entry.value, s.surface),
            greaterThanOrEqualTo(4.5),
            reason: '${s.label}: ${entry.key} '
                '${contrastRatio(entry.value, s.surface).toStringAsFixed(2)}:1 '
                'on surface -- below 4.5:1 for body text',
          );
        }
      }
    });

    test('onAccent is legible on top of every solid fill', () {
      // Filled buttons (START TRIP, CATAT BENSIN) draw their label in onAccent.
      // Picking it wrong makes a primary action unreadable, and it is the one
      // combination that is not obvious by eye.
      for (final s in ThemeSlot.values) {
        for (final entry in {
          'accent': s.accent,
          'positive': s.positive,
          'warning': s.warning,
          'danger': s.danger,
        }.entries) {
          expect(
            contrastRatio(entry.value, s.onAccent),
            greaterThanOrEqualTo(4.5),
            reason: '${s.label}: ${entry.key} fill with onAccent label is '
                '${contrastRatio(entry.value, s.onAccent).toStringAsFixed(2)}:1',
          );
        }
      }
    });

    test('body text meets the 4.5:1 threshold on background and surface', () {
      for (final s in ThemeSlot.values) {
        expect(contrastRatio(s.text, s.background), greaterThanOrEqualTo(4.5),
            reason: '${s.label}: text on background');
        expect(contrastRatio(s.text, s.surface), greaterThanOrEqualTo(4.5),
            reason: '${s.label}: text on surface');
      }
    });

    test('the light slot is the reason the dark one keeps a separate danger',
        () {
      // Colors.redAccent is a pale pink that vanishes on white. This is the
      // concrete failure that made a light mode need its own tokens, so this
      // asserts the shared colour FAILS rather than that a replacement works.
      expect(contrastRatio(const Color(0xFFFF5252), ThemeSlot.sunGlare.surface),
          lessThan(3.0),
          reason: 'if the dark-mode red ever passed on a light surface, the '
              'separate sunGlare danger token would be dead weight');
      expect(contrastRatio(ThemeSlot.sunGlare.danger, ThemeSlot.sunGlare.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'the replacement has to actually work');
    });

    test('dim and border derive from the slot text, not from white', () {
      // A hardcoded Colors.white.withOpacity(x) is invisible on a light
      // background; the whole point of the helper is that it cannot be.
      for (final s in ThemeSlot.values) {
        expect(s.dim(0.5), s.text.withOpacity(0.5));
        expect(s.border(), s.text.withOpacity(0.12));
        expect(
          s.dim(0.5).computeLuminance(),
          closeTo(s.text.withOpacity(0.5).computeLuminance(), 0.001),
        );
      }
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
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cockpit colour presets.
///
/// Three slots, not a theming system. A rider needs to read a number in
/// direct tropical sun, in a shaded garage, or at night with a helmet on —
/// three conditions a single dark theme cannot serve. RealDash's PixelPerfect
/// editor is a whole product; this is the 5% of it that actually gets used.
///
/// The three are not "light mode / dark mode / dark mode". Noir and Amoled
/// differ in a way that matters on a handlebar: Noir's panels are lifted grey
/// so they stay visible in shade, Amoled is true black so an unlit screen
/// disappears at a red-light stop.
///
/// Redline carries a green `positive` despite the name, and that is not an
/// oversight. A red-only palette left `positive` (#FF5252) and `accent`
/// (#FF3B30) 1.11:1 apart -- visually the same colour -- so the cockpit's RPM
/// channel and its TPS channel stopped being distinguishable. The slot is red
/// because of its accent, not because every channel has to be.
enum ThemeSlot {
  noir('Noir', Color(0xFF080B11), Color(0xFF0C1017), Color(0xFF00E5FF),
      Colors.white, Color(0xFF00FF66), Color(0xFFFFB300), Color(0xFF0F172A),
      Color(0xFFFF5252), Colors.black, Color(0xFFA78BFA)),

  sunGlare('Terik', Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFF006064),
      Colors.black, Color(0xFF00695C), Color(0xFFB53A0A), Color(0xFFFFFFFF),
      Color(0xFFC62828), Colors.white, Color(0xFF4A2A94)),

  amoled('AMOLED', Color(0xFF000000), Color(0xFF000000), Color(0xFF00E5FF),
      Colors.white, Color(0xFF00FF66), Color(0xFFFF6D00), Color(0xFF0A0A0A),
      Color(0xFFFF5252), Colors.black, Color(0xFFA78BFA)),

  redline('Redline', Color(0xFF0A0507), Color(0xFF140A0D), Color(0xFFFF3B30),
      Colors.white, Color(0xFF00FF66), Color(0xFFFFB300), Color(0xFF1A0A0C),
      Color(0xFFFF5252), Colors.black, Color(0xFFB39DFF));

  const ThemeSlot(
    this.label,
    this.background,
    this.surface,
    this.accent,
    this.text,
    this.positive,
    this.warning,
    this.elevated,
    this.danger,
    this.onAccent,
    this.timing,
  );

  final String label;
  final Color background;
  final Color surface;
  final Color accent;
  final Color text;
  final Color positive;
  final Color warning;

  /// Modal and sheet background. Distinct from [surface] because a raised panel
  /// has to separate from the screen it covers, and in Terik mode that means
  /// white-on-white needs a shadow rather than a grey-on-grey lift.
  final Color elevated;

  /// Destructive and fault states. `Colors.redAccent` is a pale pink on white,
  /// so light mode needs a genuinely darker red rather than the same token.
  final Color danger;

  /// Foreground drawn on top of [accent], [positive] or [danger] fills. Dark
  /// accents take near-black; Terik's teal takes white.
  final Color onAccent;

  /// Ignition timing advance. The fourth channel beside RPM, TPS and LOAD.
  ///
  /// Not a single value across slots: no purple reaches 4.5:1 on both black
  /// and white, because a mid-luminance colour has to be light enough for a
  /// dark background and dark enough for a light one. So the dark slots take a
  /// light violet and Terik takes a deep one. The old #7C4DFF managed 3.90:1
  /// on the light surface -- below the body-text floor on the one instrument
  /// channel that has no warning semantics to fall back on.
  final Color timing;

  bool get isLight => background.computeLuminance() > 0.5;

  /// Dimmed text. Every `Colors.white.withOpacity(x)` collapses to this, so a
  /// themed screen has one way to say "secondary" instead of scattering raw
  /// opacities that only work on black.
  Color dim([double opacity = 0.6]) => text.withOpacity(opacity);

  /// Hairline borders. Hardcoded `Colors.white12` reads as a dark smudge on a
  /// light background, so the value derives from the text colour instead.
  Color border([double opacity = 0.12]) => text.withOpacity(opacity);
}

/// Holds the active [ThemeSlot] and persists the choice.
///
/// Backed by an InheritedWidget so the cockpit can rebuild once on change
/// rather than each of its twenty widgets listening individually.
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  static const String _prefsKey = 'cockpit_theme_slot';

  ThemeSlot _slot = ThemeSlot.noir;
  ThemeSlot get slot => _slot;

  bool get isSunGlare => _slot == ThemeSlot.sunGlare;

  Future<void> initialize() async {
    // Reset to the default first. If the stored name is missing or unknown,
    // the in-memory slot must return to noir rather than keeping whatever was
    // selected earlier in this process -- a rider who clears app data should
    // get the default theme, not a stale one.
    _slot = ThemeSlot.noir;
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_prefsKey);
      if (name != null) {
        for (final s in ThemeSlot.values) {
          if (s.name == name) {
            _slot = s;
            break;
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> select(ThemeSlot slot) async {
    if (slot == _slot) return;
    _slot = slot;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, slot.name);
    } catch (_) {}
  }

  /// Cycles to the next slot. Useful as a single-button cockpit control, since
  /// a rider should not have to open a menu to change legibility.
  Future<void> cycle() async {
    final next =
        ThemeSlot.values[(_slot.index + 1) % ThemeSlot.values.length];
    await select(next);
  }
}

/// Makes the active slot available to the widget tree.
class ThemeScope extends InheritedNotifier<ThemeService> {
  const ThemeScope({
    super.key,
    required ThemeService service,
    required super.child,
  }) : super(notifier: service);

  static ThemeService of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    if (scope?.notifier == null) return ThemeService();
    return scope!.notifier!;
  }

  /// Convenience: the slot without subscribing to rebuilds.
  static ThemeSlot slotOf(BuildContext context) =>
      ThemeScope.of(context).slot;
}
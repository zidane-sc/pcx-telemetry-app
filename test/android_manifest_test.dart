import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Manifest structure guards.
///
/// These exist because the server has no Android SDK, so an AAPT error only
/// surfaces in CI after a 6-minute round trip. Each case below is a mistake
/// that has actually been made and shipped here.
///
/// <queries> is the important one: it is a direct child of <manifest>, and
/// placing it inside <application> fails the release build with
/// `AAPT: error: unexpected element <queries> found in <manifest><application>`.
void main() {
  final manifestFile = File(
      'android/app/src/main/AndroidManifest.xml');
  final filePathsXml = File('android/app/src/main/res/xml/file_paths.xml');

  /// Strips `<!-- ... -->` comments before matching.
  ///
  /// Required, not cosmetic: these files document the traps they guard against
  /// in prose that quotes the very strings being searched for. A raw substring
  /// search matches the warning instead of the code.
  String stripComments(String xml) =>
      xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  String manifest() => stripComments(manifestFile.readAsStringSync());

  /// Whether an element sits between <application> and </application>.
  bool insideApplication(String element) {
    final m = manifest();
    final appIdx = m.indexOf('<application');
    if (appIdx < 0) return false;
    final appEnd = m.indexOf('</application>');
    if (appEnd < 0) return false;
    final idx = m.indexOf(element);
    return idx > appIdx && idx < appEnd;
  }

  test('the manifest exists and declares a package', () {
    expect(manifestFile.existsSync(), isTrue);
    expect(manifest(), contains('package='));
  });

  group('package visibility', () {
    test('<queries> is NOT inside <application>', () {
      expect(
        insideApplication('<queries>'),
        isFalse,
        reason:
            'AAPT rejects <queries> there: "unexpected element <queries> found in '
            '<manifest><application>". Build failed on this in Sprint 4.',
      );
    });

    test('<queries> exists at manifest level', () {
      expect(manifest(), contains('<queries>'));
      expect(
        manifest().indexOf('<queries>'),
        greaterThan(manifest().indexOf('</application>')),
      );
    });

    test('it declares both the share and SMS intents', () {
      expect(manifest(), contains('android:name="android.intent.action.SEND"'));
      expect(manifest(), contains('android:scheme="smsto"'));
    });
  });

  group('FileProvider', () {
    test('is declared inside <application>', () {
      expect(insideApplication('<provider'), isTrue,
          reason: 'FileProvider must be an <application> child');
    });

    test('is not exported', () {
      final idx = manifest().indexOf('<provider');
      final block = manifest().substring(idx, manifest().indexOf('>', idx));
      expect(block, contains('android:exported="false"'),
          reason: 'an exported provider hands the whole cache dir to any app');
    });

    test('is scoped to the file_paths resource', () {
      expect(manifest(), contains('@xml/file_paths'));
    });
  });

  group('file_paths.xml', () {
    test('exists and exposes only the cache dir', () {
      expect(filePathsXml.existsSync(), isTrue);
      final xml = stripComments(filePathsXml.readAsStringSync());
      expect(xml, contains('cache-path'));
    });

    test('does not expose external or root storage', () {
      final xml = stripComments(filePathsXml.readAsStringSync());
      expect(xml, isNot(contains('external-path')),
          reason: 'external-path grants read access to all shared storage');
      expect(xml, isNot(contains('root-path')));
      expect(xml, isNot(contains('<files-path')),
          reason: 'files-path is not needed for shareable output');
    });

    test('the comment warning does not count as an exposure', () {
      // Guards the guard: the file documents these strings on purpose, so a
      // test that forgot to strip comments would pass for the wrong reason or
      // fail for the wrong one.
      final raw = filePathsXml.readAsStringSync();
      expect(raw, contains('external-path'),
          reason: 'the prose warning is expected to be there');
      expect(stripComments(raw), isNot(contains('external-path')),
          reason: 'but it must not count as an exposed path');
    });
  });

  group('MainActivity channel contract', () {
    final kotlinFile =
        File('android/app/src/main/kotlin/com/zidane/pcx_telemetry_app/MainActivity.kt');

    /// Kotlin comments document the same traps in the same way.
    String kotlin() => stripComments(
        kotlinFile.existsSync()
            ? kotlinFile.readAsStringSync()
            : '');

    test('declares both channels the Dart side invokes', () {
      expect(kotlinFile.existsSync(), isTrue);
      final kt = kotlin();
      expect(kt, contains('pcx_telemetry_app/tts'),
          reason: 'VoiceAlertService depends on this');
      expect(kt, contains('pcx_telemetry_app/actions'),
          reason: 'RideReportService depends on this');
    });

    test('handles every method RideReportService calls', () {
      final kt = kotlin();
      for (final m in ['getCacheDir', 'shareFile', 'smsDraft']) {
        expect(kt, contains('"$m"'),
            reason: 'Dart invokes "$m"; an unhandled call returns null silently');
      }
    });

    test('uses FileProvider rather than a raw file:// URI', () {
      final kt = kotlin();
      expect(kt, contains('FileProvider.getUriForFile'));
      expect(kt, isNot(contains('Uri.fromFile')),
          reason: 'a file:// URI throws FileUriExposedException on Android 7+');
    });

    test('opens an SMS draft and never sends directly', () {
      final kt = kotlin();
      expect(kt, contains('smsto:'));
      expect(kt, isNot(contains('SmsManager')),
          reason:
              'there is no auto-send path in this app by design; a false positive '
              'must not message anyone');
    });

    test('keeps the cockpit wakelock', () {
      expect(kotlin(), contains('FLAG_KEEP_SCREEN_ON'));
    });
  });
}
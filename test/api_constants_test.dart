import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/constants/api_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiConstants host policy', () {
    test('the default host is the named tunnel, not a quick tunnel', () {
      expect(ApiConstants.defaultBaseUrl, 'https://pcx.denailss.beauty');
      expect(ApiConstants.defaultBaseUrl, isNot(contains('trycloudflare.com')),
          reason:
              'quick-tunnel hosts are recycled every ~24 h and the subdomain '
              'ceases to exist when the process stops. Hard-coding one produced '
              'a dead link most mornings.');
    });

    test('the legacy quick tunnel is retained only for migration', () {
      expect(ApiConstants.legacyQuickTunnelUrl, contains('trycloudflare.com'));
      // It must not be among the hosts the resolver tries.
      expect(ApiConstants.lanBaseUrl, isNot(contains('trycloudflare')));
      expect(ApiConstants.tailscaleBaseUrl, isNot(contains('trycloudflare')));
    });

    test('the LAN host is a plain IP on the PocketBase port', () {
      expect(ApiConstants.lanBaseUrl, 'http://192.168.1.53:8092');
      expect(ApiConstants.tailscaleBaseUrl, 'http://100.115.78.109:8092');
    });

    test('the engine constants are untouched', () {
      expect(ApiConstants.pcxDisplacementL, 0.1569);
      expect(ApiConstants.pcxVolumetricEfficiency, 0.82);
      expect(ApiConstants.pcxTankCapacityL, 8.1);
    });
  });

  group('HostMemory', () {
    test('is null before anything has connected', () async {
      expect(await HostMemory.lastGood(), isNull);
    });

    test('round-trips a host', () async {
      await HostMemory.remember('https://pcx.denailss.beauty');
      expect(await HostMemory.lastGood(), 'https://pcx.denailss.beauty');
    });

    test('a rebuilt tunnel URL replaces the old one', () async {
      // This is the whole point of remembering: the tunnel URL can change and
      // the app should follow without a reinstall.
      await HostMemory.remember('https://old.trycloudflare.com');
      await HostMemory.remember('https://pcx.denailss.beauty');
      expect(await HostMemory.lastGood(), 'https://pcx.denailss.beauty');
    });

    test('an empty string is not treated as a host', () async {
      await HostMemory.remember('');
      final v = await HostMemory.lastGood();
      expect(v == null || v.isEmpty, isTrue,
          reason: 'an empty host would produce "  /api/health"');
    });
  });

  group('HostResolver result shape', () {
    test('a null host always carries a reason', () {
      const r = ResolveResult(null, HostFailure.noneReachable);
      expect(r.ok, isFalse);
      expect(r.failure, HostFailure.noneReachable);
    });

    test('a resolved host carries no failure', () {
      const r = ResolveResult('https://pcx.denailss.beauty', null);
      expect(r.ok, isTrue);
      expect(r.failure, isNull);
    });

    test('credentialsRejected is distinct from noneReachable', () {
      // A rider needs different advice for each: "server down" versus "your
      // password is wrong".
      expect(HostFailure.noneReachable, isNot(HostFailure.credentialsRejected));
    });
  });
}
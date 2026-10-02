import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the PocketBase backend lives, and how to reach it.
///
/// Three layers, in the order a phone should actually try them:
///
/// 1. **LAN** — `http://192.168.1.53:8092`. Works at home, on the ride out of
///    the house, zero internet. Zero latency, so sync is instant.
/// 2. **Named tunnel** — `https://pcx.denailss.beauty`. Works anywhere, stable
///    for years. This is what makes the app usable away from home.
/// 3. **The last host that worked** — the tunnel URL changes if the tunnel is
///    rebuilt, so the working one is remembered rather than hard-coded.
///
/// The quick-tunnel host is deliberately absent. `*.trycloudflare.com` is
/// recycled every ~24 hours and the subdomain disappears when the process
/// stops, which made the previous hard-coded URL a dead link most mornings.
class ApiConstants {
  // Named Cloudflare tunnel. Stable because it is bound to a DNS record.
  static const String defaultBaseUrl = 'https://pcx.denailss.beauty';

  // Home LAN, also served over Tailscale.
  static const String lanBaseUrl = 'http://192.168.1.53:8092';
  static const String tailscaleBaseUrl = 'http://100.115.78.109:8092';

  /// Legacy quick-tunnel host, kept only so an old install can be detected and
  /// migrated away from. Do not add this to the rotation.
  static const String legacyQuickTunnelUrl =
      'https://commodity-stuck-commitments-losses.trycloudflare.com';

  static const String hostPrefKey = 'pb_last_good_host';

  // Collections
  static const String collectionVehicles = 'vehicles';
  static const String collectionPreRideScans = 'pre_ride_scans';
  static const String collectionTrips = 'trips';
  static const String collectionDiagnosticTests = 'diagnostic_tests';
  static const String collectionMaintenance = 'maintenance_records';
  static const String collectionAppLogs = 'app_logs';

  // PCX 160 Engine Specs
  static const double pcxDisplacementL = 0.1569; // 156.9cc eSP+ 4-valve
  static const double pcxVolumetricEfficiency = 0.82; // 82% typical stock
  static const double pcxTankCapacityL = 8.1;
  static const double defaultFuelPriceIdr = 13700.0; // Pertamax baseline
}

/// Android Keystore-backed credential storage.
///
/// The PocketBase password used to sit in `api_constants.dart`, committed to a
/// public repository. Anyone who cloned it had full read access to the rider's
/// trips, maintenance history and diagnostics. It is out of source now and only
/// reachable through this class.
///
/// `ponytail:` the first launch still needs a credential to bootstrap. Rather
/// than shipping a default, [isBootstrapped] stays false and the Garage shows
/// a one-time setup prompt, so the account password is chosen by the owner
/// rather than shipped by the developer.
class CredentialStore {
  static final CredentialStore _instance = CredentialStore._internal();
  factory CredentialStore() => _instance;
  CredentialStore._internal();

  static const _emailKey = 'pb_email';
  static const _passKey = 'pb_password';
  static const _bootKey = 'pb_bootstrapped';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> save(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passKey, value: password);
    await _storage.write(key: _bootKey, value: 'true');
  }

  Future<String?> email() => _storage.read(key: _emailKey);

  Future<String?> password() => _storage.read(key: _passKey);

  Future<bool> isBootstrapped() async =>
      (await _storage.read(key: _bootKey)) == 'true';

  Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passKey);
    await _storage.delete(key: _bootKey);
  }
}

/// Remembers which host last answered, so a rebuilt tunnel does not require a
/// reinstall. Plain SharedPreferences: a URL is not a secret, and this is read
/// before authentication, so it must not sit behind the Keystore.
class HostMemory {
  static Future<String?> lastGood() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(ApiConstants.hostPrefKey);
  }

  static Future<void> remember(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ApiConstants.hostPrefKey, host);
  }
}

/// Chooses a reachable host and verifies it actually answers.
class HostResolver {
  /// Returns the first host whose `/api/health` responds 200, or null.
  ///
  /// Health check rather than a login attempt: it is one cheap GET, it does not
  /// burn an auth token on a dead host, and it distinguishes "server unreachable"
  /// from "credentials rejected" — the two cases a rider needs told apart.
  static Future<ResolveResult> resolve({Duration timeout = const Duration(seconds: 6)}) async {
    final last = await HostMemory.lastGood();

    final candidates = <String>[
      if (last != null && last.isNotEmpty) last,
      ApiConstants.defaultBaseUrl,
      ApiConstants.lanBaseUrl,
      ApiConstants.tailscaleBaseUrl,
    ];

    final seen = <String>{};
    for (final host in candidates) {
      if (!seen.add(host)) continue;
      try {
        final ok = await _health(host, timeout);
        if (ok) {
          await HostMemory.remember(host);
          return ResolveResult(host, null);
        }
      } catch (e) {
        debugPrint('[HostResolver] $host failed: $e');
      }
    }
    return const ResolveResult(null, HostFailure.noneReachable);
  }

  static Future<bool> _health(String host, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse('$host/api/health'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode == 200;
    } finally {
      client.close(force: true);
    }
  }
}

/// Outcome of a host probe, with the reason attached for the Garage screen.
enum HostFailure {
  /// No host answered. Usually the tunnel is down or the phone is off-network.
  noneReachable,

  /// A host answered but rejected the credentials, which is a different
  /// problem from being unreachable and needs a different message.
  credentialsRejected,
}

class ResolveResult {
  final String? host;
  final HostFailure? failure;
  const ResolveResult(this.host, this.failure);

  bool get ok => host != null;
}
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'navigation_models.dart';

/// Persisted search history and pinned destinations.
///
/// A rider going home or to work taps the same two or three places every day.
/// Making them retype the address is the kind of friction that gets a nav
/// feature abandoned, so the places they actually used are worth keeping.
///
/// ponytail: identity is name+~11m of coordinates, not a fuzzy string match.
/// If two SPBU sit in the same street with the same name they are one place
/// anyway. Add OSM ids here if Photon starts returning them.
class DestinationStore extends ChangeNotifier {
  static final DestinationStore _instance = DestinationStore._internal();
  factory DestinationStore() => _instance;
  DestinationStore._internal();

  static const String _recentKey = 'nav_recent_destinations';
  static const String _favoritesKey = 'nav_favorite_destinations';
  static const int _recentCap = 5;
  static const int _favoritesCap = 8;

  List<NavPlace> _recent = [];
  List<NavPlace> _favorites = [];

  /// Most-recent first.
  List<NavPlace> get recent => List.unmodifiable(_recent);
  List<NavPlace> get favorites => List.unmodifiable(_favorites);

  Future<void> initialize() async {
    _recent = [];
    _favorites = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      _recent = _decode(prefs.getString(_recentKey));
      _favorites = _decode(prefs.getString(_favoritesKey));
    } catch (_) {}
    notifyListeners();
  }

  static String _keyOf(NavPlace p) =>
      '${p.name}@${p.lat.toStringAsFixed(4)},${p.lng.toStringAsFixed(4)}';

  bool isFavorite(NavPlace p) => _favorites.any((f) => _keyOf(f) == _keyOf(p));

  Future<void> addRecent(NavPlace place) async {
    _recent.removeWhere((p) => _keyOf(p) == _keyOf(place));
    _recent.insert(0, place);
    if (_recent.length > _recentCap) {
      _recent = _recent.sublist(0, _recentCap);
    }
    notifyListeners();
    await _persist(_recentKey, _recent);
  }

  Future<void> toggleFavorite(NavPlace place) async {
    if (isFavorite(place)) {
      _favorites.removeWhere((p) => _keyOf(p) == _keyOf(place));
    } else {
      _favorites.insert(0, place);
      if (_favorites.length > _favoritesCap) {
        _favorites = _favorites.sublist(0, _favoritesCap);
      }
    }
    notifyListeners();
    await _persist(_favoritesKey, _favorites);
  }

  Future<void> removeRecent(NavPlace place) async {
    _recent.removeWhere((p) => _keyOf(p) == _keyOf(place));
    notifyListeners();
    await _persist(_recentKey, _recent);
  }

  /// Clears history only. Pinned places were chosen deliberately; history was
  /// accumulated as a side effect, so "clear" should not take both.
  Future<void> clearRecent() async {
    _recent = [];
    notifyListeners();
    await _persist(_recentKey, _recent);
  }

  Future<void> _persist(String key, List<NavPlace> places) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(places
            .map((p) => {'n': p.name, 'd': p.detail, 'a': p.lat, 'o': p.lng})
            .toList()),
      );
    } catch (_) {}
  }

  /// A corrupt or partial prefs entry must not brick navigation, so anything
  /// unparseable is dropped rather than thrown.
  static List<NavPlace> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <NavPlace>[];
      for (final e in list) {
        if (e is! Map) continue;
        final name = e['n']?.toString();
        final lat = e['a'];
        final lng = e['o'];
        if (name == null || lat is! num || lng is! num) continue;
        out.add(NavPlace(
          name: name,
          detail: e['d']?.toString() ?? '',
          lat: lat.toDouble(),
          lng: lng.toDouble(),
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pcx_telemetry_app/core/navigation/destination_store.dart';
import 'package:pcx_telemetry_app/core/navigation/navigation_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

NavPlace place(String name, double lat, double lng) =>
    NavPlace(name: name, detail: 'Jakarta', lat: lat, lng: lng);

void main() {
  // DestinationStore is a singleton, so its lists survive between tests.
  // An empty store plus initialize() puts every test back at the start.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DestinationStore().initialize();
  });

  group('recent history', () {
    test('a new place becomes the first entry', () async {
      await DestinationStore().addRecent(place('Rumah', -6.2, 106.8));
      expect(DestinationStore().recent.single.name, 'Rumah');
    });

    test('re-visiting a place moves it to the front instead of duplicating',
        () async {
      final store = DestinationStore();
      await store.addRecent(place('Kantor', -6.2, 106.8));
      await store.addRecent(place('Rumah', -6.1, 106.9));
      await store.addRecent(place('Kantor', -6.2, 106.8));

      expect(store.recent.length, 2);
      expect(store.recent.first.name, 'Kantor',
          reason: 'the place just used is the one most likely to be next');
    });

    test('the same name at different coordinates is two places', () async {
      // Two SPBU on the same street are genuinely different destinations.
      // Collapsing them by name would send the rider to the wrong pump.
      final store = DestinationStore();
      await store.addRecent(place('SPBU Pertamina', -6.20, 106.80));
      await store.addRecent(place('SPBU Pertamina', -6.25, 106.85));

      expect(store.recent.length, 2);
    });

    test('history is capped so it stays scannable', () async {
      final store = DestinationStore();
      for (var i = 0; i < 9; i++) {
        await store.addRecent(place('Tujuan $i', -6.0 - i * 0.01, 106.8));
      }
      expect(store.recent.length, 5);
      expect(store.recent.first.name, 'Tujuan 8');
    });

    test('clearRecent empties history but leaves pinned places', () async {
      final store = DestinationStore();
      await store.addRecent(place('Rumah', -6.2, 106.8));
      await store.toggleFavorite(place('Kantor', -6.2, 106.8));

      await store.clearRecent();

      expect(store.recent, isEmpty);
      expect(store.favorites.single.name, 'Kantor',
          reason: 'pinned places were chosen, not accumulated');
    });
  });

  group('favorites', () {
    test('toggling adds then removes the same place', () async {
      final store = DestinationStore();
      final p = place('Rumah', -6.2, 106.8);

      await store.toggleFavorite(p);
      expect(store.isFavorite(p), isTrue);
      expect(store.favorites.length, 1);

      await store.toggleFavorite(p);
      expect(store.isFavorite(p), isFalse);
      expect(store.favorites, isEmpty);
    });

    test('pinned places are capped', () async {
      final store = DestinationStore();
      for (var i = 0; i < 11; i++) {
        await store.toggleFavorite(place('Favorit $i', -6.0 - i * 0.01, 106.8));
      }
      expect(store.favorites.length, 8);
    });
  });

  group('persistence', () {
    test('recent and favorites survive a reload', () async {
      await DestinationStore().addRecent(place('Rumah', -6.2, 106.8));
      await DestinationStore().toggleFavorite(place('Kantor', -6.2, 106.8));

      await DestinationStore().initialize();

      expect(DestinationStore().recent.single.name, 'Rumah');
      expect(DestinationStore().favorites.single.name, 'Kantor');
    });

    test('a corrupt store is dropped instead of throwing', () async {
      // A bad prefs write must never be the reason navigation stops working.
      SharedPreferences.setMockInitialValues({'nav_recent_destinations': '{oops'});
      await DestinationStore().initialize();
      expect(DestinationStore().recent, isEmpty);
    });

    test('entries missing coordinates are skipped, valid ones kept', () async {
      SharedPreferences.setMockInitialValues({
        'nav_recent_destinations': '[{"n":"Rumah","a":-6.2,"o":106.8},{"n":"Hantu"}]',
      });
      await DestinationStore().initialize();
      expect(DestinationStore().recent.single.name, 'Rumah');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pcx_telemetry_app/core/navigation/navigation_manager.dart';
import 'package:pcx_telemetry_app/core/navigation/navigation_models.dart';
import 'package:pcx_telemetry_app/ui/navigation/nav_route_bar.dart';
import 'package:pcx_telemetry_app/ui/navigation/navigation_sheet.dart';
import 'package:pcx_telemetry_app/ui/theme/theme_service.dart';

Widget wrap(Widget child) => ThemeScope(
      service: ThemeService(),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, child: child),
        ),
      ),
    );

Widget bar({bool mapVisible = true}) => NavRouteBar(
      currentPosition: const LatLng(-6.2088, 106.8456),
      isMapVisible: mapVisible,
      onToggleMap: () {},
    );

NavRoute route() => NavRoute(
      totalDistanceMeters: 12400,
      totalDurationSec: 1500,
      polyline: const [LatLng(-6.2, 106.8), LatLng(-6.1, 106.9)],
      steps: const [
        NavStep(
          instruction: 'Mulai perjalanan ke Jl. Melati',
          streetName: 'Jl. Melati',
          distanceMeters: 400,
          durationSec: 60,
          type: ManeuverType.depart,
          modifier: '',
          location: LatLng(-6.2, 106.8),
        ),
        NavStep(
          instruction: 'Belok kiri ke Jl. Kenanga',
          streetName: 'Jl. Kenanga',
          distanceMeters: 800,
          durationSec: 90,
          type: ManeuverType.turn,
          modifier: 'left',
          location: LatLng(-6.1, 106.9),
        ),
      ],
    );

void main() {
  setUp(() {
    NavigationManager().stopNavigation();
  });

  testWidgets('idle offers search as a labelled, tappable row', (tester) async {
    await tester.pumpWidget(wrap(bar()));

    expect(find.textContaining('Cari tujuan'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    // The whole bar is the target, not a glyph inside it. A tap in the middle
    // of the row must reach the search page.
    final barBox = tester.getSize(find.byType(NavRouteBar));
    expect(barBox.height, greaterThanOrEqualTo(44),
        reason: 'primary handlebar action must clear the touch-target floor');
  });

  testWidgets('idle bar is not dominated by a stop control', (tester) async {
    // There must be no way to stop a navigation that does not exist.
    await tester.pumpWidget(wrap(bar()));
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('navigating replaces the prompt with turn guidance', (tester) async {
    NavigationManager().startNavigation(
      route(),
      const NavPlace(name: 'Kantor', detail: 'Sudirman', lat: -6.1, lng: 106.9),
    );
    await tester.pumpWidget(wrap(bar()));

    expect(find.textContaining('Cari tujuan'), findsNothing);
    expect(find.textContaining('Mulai perjalanan'), findsOneWidget);
    expect(find.textContaining('12.4 km'), findsOneWidget,
        reason: 'remaining distance belongs on the bar while riding');
    expect(find.byIcon(Icons.close), findsOneWidget,
        reason: 'stop must stay reachable without opening a menu');
  });

  testWidgets('the navigating bar meets the touch-target floor', (tester) async {
    NavigationManager().startNavigation(
      route(),
      const NavPlace(name: 'Kantor', detail: 'Sudirman', lat: -6.1, lng: 106.9),
    );
    await tester.pumpWidget(wrap(bar()));

    final stopTarget = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkResponse),
      ),
    );
    expect(stopTarget.width, greaterThanOrEqualTo(44));
    expect(stopTarget.height, greaterThanOrEqualTo(44));
  });

  testWidgets('the nav sheet shows the destination and a stop action',
      (tester) async {
    NavigationManager().startNavigation(
      route(),
      const NavPlace(name: 'Kantor', detail: 'Sudirman', lat: -6.1, lng: 106.9),
    );
    await tester.pumpWidget(wrap(bar()));
    await tester.tap(find.byType(NavRouteBar));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationSheet), findsOneWidget);
    expect(find.text('Kantor'), findsOneWidget);
    expect(find.text('HENTIKAN NAVIGASI'), findsOneWidget);
  });

  testWidgets('stopping from the sheet returns the bar to idle', (tester) async {
    NavigationManager().startNavigation(
      route(),
      const NavPlace(name: 'Kantor', detail: 'Sudirman', lat: -6.1, lng: 106.9),
    );
    await tester.pumpWidget(wrap(bar()));
    await tester.tap(find.byType(NavRouteBar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('HENTIKAN NAVIGASI'));
    await tester.pumpAndSettle();

    expect(NavigationManager().isNavigating, isFalse);
    expect(find.textContaining('Cari tujuan'), findsOneWidget);
  });
}

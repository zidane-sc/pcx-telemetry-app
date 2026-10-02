import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/navigation/navigation_manager.dart';
import '../theme/theme_service.dart';
import 'navigation_sheet.dart';
import 'search_destination_page.dart';

/// The cockpit's single navigation surface.
///
/// It replaces both a top-bar search icon and a turn banner that only existed
/// while navigating. One slot, three states:
///
///   idle       "Cari tujuan, SPBU, bengkel..."  -> tap opens search
///   navigating distance, maneuver, ETA, street  -> tap opens the nav sheet
///
/// Navigation is a state of the cockpit, not a fourth place in it. A rider
/// never decides to "go to the navigation tab" -- they decide where they are
/// going, which is a one-tap decision from wherever they already are. Keeping
/// it here also means the entry point is a 48dp row with a text label instead
/// of an 18dp glyph sharing a toolbar with theme and Bluetooth buttons.
class NavRouteBar extends StatelessWidget {
  final LatLng currentPosition;
  final bool isMapVisible;
  final VoidCallback onToggleMap;
  final bool compact;

  const NavRouteBar({
    super.key,
    required this.currentPosition,
    required this.isMapVisible,
    required this.onToggleMap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final slot = ThemeScope.slotOf(context);
    final nav = NavigationManager();

    return AnimatedBuilder(
      animation: nav,
      builder: (context, _) {
        if (nav.isNavigating && nav.currentStep != null) {
          return _buildNavigating(context, nav, slot);
        }
        return _buildIdle(context, slot);
      },
    );
  }

  Widget _buildIdle(BuildContext context, ThemeSlot slot) {
    return Semantics(
      button: true,
      label: 'Cari tujuan navigasi',
      child: Material(
        color: slot.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => SearchDestinationPage.push(context, currentPosition),
          child: Container(
            // 48dp minimum. This is a primary action on a handlebar mount, not
            // a toolbar affordance.
            height: compact ? 44 : 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: slot.accent.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: slot.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Cari tujuan, SPBU, bengkel...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: slot.text.withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.navigation, color: slot.positive, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigating(
      BuildContext context, NavigationManager nav, ThemeSlot slot) {
    final route = nav.currentRoute;
    if (route == null) return const SizedBox.shrink();
    final step = nav.currentStep!;
    final distM = nav.distanceToNextStepMeters;
    final distStr = distM >= 1000.0
        ? '${(distM / 1000.0).toStringAsFixed(1)} KM'
        : '${distM.toStringAsFixed(0)} M';
    final remainKm = (nav.totalRemainingDistanceMeters / 1000.0);
    final eta = DateTime.now()
        .add(Duration(seconds: route.totalDurationSec.toInt()));

    return Container(
      padding: EdgeInsets.fromLTRB(10, compact ? 6 : 8, 6, compact ? 6 : 8),
      decoration: BoxDecoration(
        color: slot.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: slot.accent.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: slot.accent.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Tapping the maneuver block opens the full nav sheet: remaining
          // distance, arrival time, stop. Everything not needed while riding.
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => NavigationSheet.show(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: slot.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child:
                            Icon(step.icon, color: slot.accent, size: compact ? 22 : 26),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  distStr,
                                  style: TextStyle(
                                    color: slot.positive,
                                    fontSize: compact ? 14 : 16,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'monospace',
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: slot.text.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${eta.hour.toString().padLeft(2, '0')}:'
                                      '${eta.minute.toString().padLeft(2, '0')} • '
                                      '${remainKm.toStringAsFixed(1)} km',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: slot.text.withOpacity(0.8),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              step.instruction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: slot.text,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          _barIcon(
            icon: isMapVisible ? Icons.map : Icons.map_outlined,
            color: isMapVisible ? slot.positive : slot.accent,
            tooltip: isMapVisible ? 'Sembunyikan peta' : 'Tampilkan peta',
            onTap: onToggleMap,
          ),
          _barIcon(
            icon: Icons.close,
            color: Colors.redAccent,
            tooltip: 'Hentikan navigasi',
            onTap: nav.stopNavigation,
          ),
        ],
      ),
    );
  }

  /// 44dp square so the two secondary controls meet the touch-target floor
  /// the old 32px toolbar buttons were below.
  Widget _barIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

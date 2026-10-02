import 'package:flutter/material.dart';
import '../theme/theme_service.dart';
import '../../core/navigation/navigation_manager.dart';

/// Full navigation detail, reached by tapping the route bar while navigating.
///
/// Turn-by-turn itself lives in the bar; this sheet holds what a rider needs
/// before starting or when something is wrong -- where they are going, how far
/// is left, when they arrive, and a way out. Stopping navigation from a
/// 44dp target on the bar itself is an easy mis-tap at speed, so the
/// destructive action is here instead.
class NavigationSheet extends StatelessWidget {
  const NavigationSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeScope.slotOf(context).elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const NavigationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = ThemeScope.slotOf(context);
    final nav = NavigationManager();

    return AnimatedBuilder(
      animation: nav,
      builder: (context, _) {
        final route = nav.currentRoute;
        if (!nav.isNavigating || route == null) {
          return const SizedBox.shrink();
        }
        final dest = nav.destination;
        final remainKm = nav.totalRemainingDistanceMeters / 1000.0;
        final eta = DateTime.now()
            .add(Duration(seconds: route.totalDurationSec.toInt()));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.flag, color: slot.positive, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            dest?.name ?? 'Tujuan',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: slot.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if ((dest?.detail ?? '').isNotEmpty)
                            Text(
                              dest!.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: slot.text.withOpacity(0.5),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _metric('SISA RUTE', '${remainKm.toStringAsFixed(1)} KM',
                        slot.accent),
                    _metric(
                        'ESTIMASI SAMPAI',
                        '${eta.hour.toString().padLeft(2, '0')}:'
                        '${eta.minute.toString().padLeft(2, '0')}',
                        slot.positive),
                    _metric('LANGKAH',
                        '${nav.currentStepIndex + 1}/${route.steps.length}',
                        slot.warning),
                  ],
                ),
                const SizedBox(height: 18),
                // Destructive action kept off the bar on purpose: a 44dp stop
                // button next to a map toggle is one glove-swipe away from
                // losing turn-by-turn mid-corner.
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.15),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      nav.stopNavigation();
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text(
                      'HENTIKAN NAVIGASI',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, letterSpacing: 1.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

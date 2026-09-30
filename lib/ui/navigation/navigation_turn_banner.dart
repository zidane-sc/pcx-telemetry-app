import 'package:flutter/material.dart';
import '../../core/navigation/navigation_manager.dart';

class NavigationTurnBanner extends StatelessWidget {
  final NavigationManager navMgr;
  final VoidCallback onToggleMap;
  final bool isMapVisible;

  const NavigationTurnBanner({
    super.key,
    required this.navMgr,
    required this.onToggleMap,
    required this.isMapVisible,
  });

  @override
  Widget build(BuildContext context) {
    if (!navMgr.isNavigating || navMgr.currentStep == null) {
      return const SizedBox.shrink();
    }

    final step = navMgr.currentStep!;
    final dist = navMgr.distanceToNextStepMeters;
    final distStr = dist >= 1000.0
        ? '${(dist / 1000.0).toStringAsFixed(1)} KM'
        : '${dist.toStringAsFixed(0)} M';

    final totalKm =
        (navMgr.currentRoute!.totalDistanceMeters / 1000.0).toStringAsFixed(1);
    final totalMin =
        (navMgr.currentRoute!.totalDurationSec / 60.0).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Maneuver Turn Icon Container
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(step.icon, color: const Color(0xFF00E5FF), size: 26),
          ),
          const SizedBox(width: 10),

          // Maneuver Text & Distance
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      distStr,
                      style: const TextStyle(
                        color: Color(0xFF00FF66),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$totalKm km • $totalMin mnt',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  step.instruction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Map Toggle Button
          IconButton(
            icon: Icon(
              isMapVisible ? Icons.map : Icons.map_outlined,
              color: isMapVisible ? const Color(0xFF00FF66) : const Color(0xFF00E5FF),
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Tampilkan / Sembunyikan Peta',
            onPressed: onToggleMap,
          ),

          // Stop Navigation Button
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Hentikan Navigasi',
            onPressed: () {
              navMgr.stopNavigation();
            },
          ),
        ],
      ),
    );
  }
}

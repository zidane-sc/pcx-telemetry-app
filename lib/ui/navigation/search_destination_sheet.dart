import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/routing_service.dart';
import '../../core/navigation/navigation_manager.dart';

class SearchDestinationSheet extends StatefulWidget {
  final LatLng currentPosition;

  const SearchDestinationSheet({super.key, required this.currentPosition});

  static Future<void> show(BuildContext context, LatLng currentPos) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SearchDestinationSheet(currentPosition: currentPos),
    );
  }

  @override
  State<SearchDestinationSheet> createState() => _SearchDestinationSheetState();
}

class _SearchDestinationSheetState extends State<SearchDestinationSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  bool _isRouting = false;
  List<NavPlace> _results = [];

  final List<Map<String, dynamic>> _quickShortcuts = [
    {'name': 'SPBU Pertamina', 'icon': Icons.local_gas_station, 'query': 'SPBU Pertamina'},
    {'name': 'SPBU Shell', 'icon': Icons.local_gas_station, 'query': 'Shell'},
    {'name': 'Bengkel AHASS', 'icon': Icons.build, 'query': 'AHASS'},
    {'name': 'Rest Area / Kopi', 'icon': Icons.local_cafe, 'query': 'Indomaret Point'},
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLoading = true);
      final places = await RoutingService.searchPlaces(
        query,
        userLat: widget.currentPosition.latitude,
        userLng: widget.currentPosition.longitude,
      );
      if (mounted) {
        setState(() {
          _results = places;
          _isLoading = false;
        });
      }
    });
  }

  void _selectPlace(NavPlace place) async {
    setState(() => _isRouting = true);

    final route = await RoutingService.calculateRoute(
      origin: widget.currentPosition,
      destination: place.toLatLng,
    );

    if (!mounted) return;
    setState(() => _isRouting = false);

    if (route != null) {
      NavigationManager().startNavigation(route, place);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00FF66),
          content: Text(
            'Navigasi ke ${place.name} dimulai! (${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} KM)',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Gagal menghitung rute. Coba tujuan lain.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.directions_bike, color: Color(0xFF00E5FF), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'CARI TUJUAN NAVIGASI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Input Field
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ketik nama tempat, mall, jalan...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: _onSearchChanged,
          ),

          const SizedBox(height: 10),

          // Quick Category Shortcuts (SPBU, Bengkel, etc.)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickShortcuts.map((sc) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    avatar: Icon(sc['icon'] as IconData, size: 14, color: const Color(0xFF00FF66)),
                    label: Text(
                      sc['name'] as String,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: Colors.white.withOpacity(0.06),
                    side: BorderSide(color: const Color(0xFF00FF66).withOpacity(0.3), width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onPressed: () {
                      _searchCtrl.text = sc['query'] as String;
                      _onSearchChanged(sc['query'] as String);
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          if (_isRouting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text(
                      'Menghitung rute khusus motor...',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
                ),
              ),
            )
          else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Tempat tidak ditemukan.\nCoba kata kunci lain atau nama jalan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, index) {
                  final p = _results[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.location_on, color: Color(0xFF00E5FF), size: 18),
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    subtitle: Text(
                      p.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
                    onTap: () => _selectPlace(p),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

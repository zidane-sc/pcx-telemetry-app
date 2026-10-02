import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/navigation/destination_store.dart';
import '../../core/navigation/navigation_manager.dart';
import '../../core/navigation/navigation_models.dart';
import '../../core/navigation/routing_service.dart';
import '../theme/theme_service.dart';

/// Full-screen destination search.
///
/// ponytail: it was a bottom sheet with `autofocus: true`, which is the worst
/// of both -- the keyboard covers the results and the sheet resizes under the
/// rider's thumb. A route is a destination you cannot undo from a glance, so
/// it gets the whole screen.
///
/// Quick categories are rows, not the horizontal ActionChip scroll: a chip
/// rail hides options behind a sideways swipe, which is not an affordance you
/// can discover with a gloved hand on a moving bike.
class SearchDestinationPage extends StatefulWidget {
  final LatLng currentPosition;

  const SearchDestinationPage({super.key, required this.currentPosition});

  static Future<void> push(BuildContext context, LatLng currentPos) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchDestinationPage(currentPosition: currentPos),
      ),
    );
  }

  @override
  State<SearchDestinationPage> createState() => _SearchDestinationPageState();
}

class _SearchDestinationPageState extends State<SearchDestinationPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  bool _isLoading = false;
  bool _isRouting = false;
  List<NavPlace> _results = [];

  static const List<(String, IconData, String)> _categories = [
    ('SPBU Pertamina', Icons.local_gas_station, 'SPBU Pertamina'),
    ('SPBU Shell / Pertamax', Icons.local_gas_station, 'Shell'),
    ('Bengkel AHASS', Icons.build, 'AHASS'),
    ('Kopi / Istirahat', Icons.local_cafe, 'Indomaret Point'),
  ];

  @override
  void initState() {
    super.initState();
    // Autofocus from initState rather than a post-frame callback, so the
    // keyboard is already up when the route settles instead of sliding in
    // over results the rider is trying to read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focus.dispose();
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
      if (!mounted) return;
      setState(() {
        _results = places;
        _isLoading = false;
      });
    });
  }

  Future<void> _selectPlace(NavPlace place) async {
    FocusScope.of(context).unfocus();
    setState(() => _isRouting = true);

    final route = await RoutingService.calculateRoute(
      origin: widget.currentPosition,
      destination: place.toLatLng,
    );

    if (!mounted) return;
    setState(() => _isRouting = false);

    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Gagal menghitung rute. Coba tujuan lain.'),
        ),
      );
      return;
    }

    // Recorded on success only. A failed lookup is not somewhere the rider
    // meant to go, and next time's RECENT list is the one thing they trust.
    await DestinationStore().addRecent(place);
    NavigationManager().startNavigation(route, place);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF00FF66),
        content: Text(
          'Navigasi ke ${place.name} dimulai '
          '(${(route.totalDistanceMeters / 1000).toStringAsFixed(1)} KM)',
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = ThemeScope.slotOf(context);
    final store = DestinationStore();
    final hasQuery = _searchCtrl.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: slot.background,
      appBar: AppBar(
        backgroundColor: slot.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: slot.text),
          tooltip: 'Kembali ke kokpit',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'CARI TUJUAN',
          style: TextStyle(
            color: slot.text,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: slot.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Nama tempat, mall, atau jalan...',
                hintStyle:
                    TextStyle(color: slot.text.withOpacity(0.35), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: slot.accent, size: 22),
                suffixIcon: hasQuery
                    ? IconButton(
                        icon:
                            Icon(Icons.clear, color: slot.text.withOpacity(0.5)),
                        tooltip: 'Hapus pencarian',
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: slot.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          if (_isRouting)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: Color(0xFF00E5FF), strokeWidth: 2.5),
                    SizedBox(height: 14),
                    Text(
                      'Menghitung rute khusus motor...',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else if (!hasQuery)
            Expanded(
              child: AnimatedBuilder(
                animation: store,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (store.favorites.isNotEmpty) ...[
                      _sectionLabel('TERSIMPAN', slot),
                      for (final p in store.favorites)
                        _placeRow(p, slot, starred: true),
                    ],
                    if (store.recent.isNotEmpty) ...[
                      _sectionLabel('TERKINI', slot, action: _confirmClearRecent),
                      for (final p in store.recent)
                        _placeRow(p, slot, starred: store.isFavorite(p)),
                    ],
                    _sectionLabel('CATEGORI', slot),
                    for (final (label, icon, query) in _categories)
                      ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        leading: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: slot.positive.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: slot.positive, size: 18),
                        ),
                        title: Text(
                          label,
                          style: TextStyle(
                            color: slot.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: Icon(Icons.chevron_right,
                            color: slot.text.withOpacity(0.3), size: 20),
                        onTap: () {
                          _searchCtrl.text = query;
                          _onSearchChanged(query);
                        },
                      ),
                  ],
                ),
              ),
            )
          else if (_isLoading)
            const Expanded(
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child:
                      CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
                ),
              ),
            )
          else if (_results.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Tempat tidak ditemukan.\n'
                    'Coba kata kunci lain, atau nama jalan terdekat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: slot.text.withOpacity(0.45),
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, i) =>
                    _placeRow(_results[i], slot, starred: store.isFavorite(_results[i])),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ThemeSlot slot, {VoidCallback? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              color: slot.text.withOpacity(0.45),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'Hapus',
                style: TextStyle(color: slot.text.withOpacity(0.5), fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeRow(NavPlace p, ThemeSlot slot, {required bool starred}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: slot.accent.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.location_on, color: slot.accent, size: 18),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: slot.text,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      subtitle: p.detail.isEmpty
          ? null
          : Text(
              p.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: slot.text.withOpacity(0.5), fontSize: 11),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              starred ? Icons.star : Icons.star_border,
              color: starred ? const Color(0xFFFFB300) : slot.text.withOpacity(0.3),
              size: 20,
            ),
            tooltip: starred ? 'Hapus dari tersimpan' : 'Simpan tujuan',
            onPressed: () => DestinationStore().toggleFavorite(p),
          ),
          Icon(Icons.arrow_forward_ios,
              color: slot.text.withOpacity(0.24), size: 12),
        ],
      ),
      onTap: () => _selectPlace(p),
    );
  }

  Future<void> _confirmClearRecent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ThemeScope.slotOf(ctx).elevated,
        title: const Text('Hapus riwayat tujuan?',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: const Text(
          'Tempat yang tersimpan tidak ikut terhapus.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('BATAL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('HAPUS',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed == true) await DestinationStore().clearRecent();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/destination.dart';
import '../../services/destination_repository.dart';
import '../../services/osm_places_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/destination_view.dart';
import '../../widgets/map_common.dart';
import '../../widgets/map_pins.dart';
import 'destination_form.dart';

/// The Build page: a map of one area where the user fills in missing
/// destinations. Tap "+ Add Destination", then tap the map to place a pin —
/// existing destinations are shown too, so it's obvious what's missing.
class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key, required this.userId});

  final String userId;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  final _repo = DestinationRepository();
  final _osm = OsmPlacesService();
  final _mapController = MapController();

  List<Destination> _destinations = [];
  bool _loading = true;
  String? _error;

  bool _placing = false;
  LatLng? _draftPoint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVisibleArea());
  }

  Future<void> _loadVisibleArea() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final bounds = _mapController.camera.visibleBounds;

    // Two sources of "what's already on the map": Appwrite (community
    // contributions + anything curated by hand) and live OpenStreetMap
    // points of interest — fetched together so a slow one doesn't block
    // the other. OSM is supplementary and fails silently (see
    // OsmPlacesService); Appwrite failing is shown as a real error since
    // that's the data Build itself writes to.
    final osmFuture = _osm.listInBounds(
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    );
    // Started eagerly, alongside osmFuture above, so the two requests run
    // concurrently rather than one waiting on the other. The no-op
    // catchError below attaches a listener the instant this future is
    // created — without it, if this errors before osmFuture (awaited
    // first) finishes, Dart's zone error handling reports it as a genuine
    // unhandled exception, since nothing was listening yet. The real
    // handling still happens at the `await communityFuture` below; Futures
    // support multiple independent listeners, so this doesn't swallow it.
    final communityFuture = _repo.listInBounds(
      south: bounds.south,
      west: bounds.west,
      north: bounds.north,
      east: bounds.east,
    )..catchError((_) {});

    List<Destination> osmPlaces = [];
    try {
      osmPlaces = await osmFuture;
    } catch (e) {
      debugPrint('Build: OSM fetch failed — $e');
    }

    try {
      final community = await communityFuture;
      if (!mounted) return;
      setState(() {
        _destinations = [...osmPlaces, ...community];
        _loading = false;
      });
      debugPrint('Build: loaded ${osmPlaces.length} OSM + ${community.length} community = ${_destinations.length} pins');
    } on DestinationException catch (e) {
      if (!mounted) return;
      setState(() {
        _destinations = osmPlaces;
        _error = e.message;
        _loading = false;
      });
    }
  }
  void _startPlacing() {
    setState(() {
      _placing = true;
      _draftPoint = null;
    });
    _toast('Tap anywhere on the map to drop a pin.');
  }

  void _cancelPlacing() => setState(() {
        _placing = false;
        _draftPoint = null;
      });

  void _onMapTap(LatLng point) {
    if (!_placing) return;
    setState(() => _draftPoint = point);
  }

  Future<void> _openForm({LatLng? location, Destination? editing}) async {
    final point = location ?? editing!.location;
    final result = await Navigator.push<Destination>(
      context,
      MaterialPageRoute(
        builder: (_) => DestinationFormPage(location: point, userId: widget.userId, initial: editing),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _placing = false;
      _draftPoint = null;
    });

    try {
      final saved = editing == null
          ? await _repo.create(result, authorId: widget.userId)
          : await _repo.update(result, userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _destinations = [
          ..._destinations.where((d) => d.id != saved.id),
          saved,
        ];
      });
      _toast(editing == null ? '"${saved.name}" added to the map 🎉' : '"${saved.name}" updated.');
    } on DestinationException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  Future<void> _delete(Destination destination) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.parchment50,
        title: Text('Remove "${destination.name}"?', style: AppText.headline(size: 16)),
        content: Text('This takes it off the map for everyone.', style: AppText.body(size: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove', style: AppText.body(size: 13.5, weight: FontWeight.w700, color: AppColors.blaze600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.delete(destination, userId: widget.userId);
      if (!mounted) return;
      setState(() => _destinations.removeWhere((d) => d.id == destination.id));
      Navigator.of(context).pop();
      _toast('Removed.');
    } on DestinationException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  void _openDetail(Destination destination) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment50,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            DestinationDetail(destination: destination, userId: widget.userId),
            if (destination.isMine(widget.userId)) ...[
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openForm(editing: destination);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.pine800,
                      side: const BorderSide(color: AppColors.pine800),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _delete(destination),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.blaze600,
                      side: const BorderSide(color: AppColors.blaze600),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.pine950,
      content: Text(message, style: AppText.body(size: 12.5, color: AppColors.parchment50)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment50,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(child: _buildMapArea()),
        ]),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Build', style: AppText.headline(size: 22)),
            const SizedBox(height: 2),
            Text('Fill in the gaps on the map', style: AppText.body(size: 12.5, color: Colors.black54)),
          ]),
        ),
        if (!_placing)
          ElevatedButton.icon(
            onPressed: _startPlacing,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Destination'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blaze600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: AppText.body(size: 13, weight: FontWeight.w700),
            ),
          ),
      ]),
    );
  }

  Widget _buildMapArea() {
    return Stack(children: [
      Positioned.fill(
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: kDefaultMapCenter,
            initialZoom: 14,
            onTap: (_, point) => _onMapTap(point),
            onMapEvent: (event) {
              if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) _loadVisibleArea();
            },
          ),
          children: [
            osmTileLayer(),
            MarkerLayer(markers: [
              for (final d in _destinations)
                Marker(
                  point: d.location,
                  width: d.isCommunity ? 46 : 34,
                  height: d.isCommunity ? 46 : 34,
                  alignment: d.isCommunity ? Alignment.topCenter : Alignment.center,
                  child: GestureDetector(
                    onTap: _placing ? null : () => _openDetail(d),
                    child: d.isCommunity
                        ? CommunityPin(category: d.category, isMine: d.isMine(widget.userId))
                        : ExistingPin(category: d.category, dimmed: _placing),
                  ),
                ),
              if (_draftPoint != null) draftMarker(_draftPoint!),
            ]),
            const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
          ],
        ),
      ),
      Positioned(
        top: 10,
        right: 10,
        child: MapRoundButton(icon: Icons.my_location, tooltip: 'Recenter', onTap: () => _mapController.move(kDefaultMapCenter, 14)),
      ),
      if (_loading)
        const Positioned(top: 14, left: 0, right: 0, child: Center(child: _Pill(child: CircularProgressIndicator(strokeWidth: 2)))),
      if (_error != null)
        Positioned(
          top: 14,
          left: 60,
          right: 60,
          child: _Pill(
            child: Text(_error!, style: AppText.body(size: 12, color: AppColors.blaze700), textAlign: TextAlign.center),
          ),
        ),
      if (!_placing) _legend(),
      if (_placing) _placingBanner(),
    ]);
  }

  Widget _legend() {
    return Positioned(
      left: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.parchment50.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12), boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ]),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _legendRow(const ExistingPin(category: 'Culture'), 'Existing destination', size: 20),
          const SizedBox(height: 6),
          _legendRow(const CommunityPin(category: 'Culture'), 'Community-added', size: 26),
          const SizedBox(height: 6),
          _legendRow(const CommunityPin(category: 'Culture', isMine: true), 'Added by you', size: 26),
        ]),
      ),
    );
  }

  Widget _legendRow(Widget pin, String label, {required double size}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: size, height: size, child: FittedBox(child: pin)),
      const SizedBox(width: 8),
      Text(label, style: AppText.body(size: 11, color: AppColors.ink)),
    ]);
  }

  Widget _placingBanner() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: AppColors.pine950, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.touch_app_outlined, color: AppColors.gold500, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _draftPoint == null ? 'Tap the map to place your destination' : 'Pin placed — continue to fill in the details',
              style: AppText.body(size: 12.5, color: AppColors.parchment50),
            ),
          ),
          if (_draftPoint != null)
            TextButton(
              onPressed: () => _openForm(location: _draftPoint),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.blaze600,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Continue', style: AppText.body(size: 12.5, weight: FontWeight.w700, color: Colors.white)),
            )
          else
            TextButton(onPressed: _cancelPlacing, child: Text('Cancel', style: AppText.body(size: 12.5, color: AppColors.parchment50.withValues(alpha: 0.7)))),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: AppColors.parchment50, borderRadius: BorderRadius.circular(20), boxShadow: const [
        BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
      ]),
      child: SizedBox(height: 16, width: 16, child: child),
    );
  }
}

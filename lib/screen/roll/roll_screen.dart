import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/destination.dart';
import '../../services/destination_repository.dart';
import '../../services/geocoding_service.dart' show PlaceResult;
import '../../services/monetization_service.dart';
import '../../services/osm_places_service.dart';
import '../../services/trail_roller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/destination_view.dart';
import '../../widgets/map_common.dart';
import '../../widgets/map_pins.dart';
import '../../widgets/place_search_bar.dart';
import '../../widgets/premium_banner.dart';
import '../../widgets/stop_card.dart';

enum _TrailSize { short, classic, long }

extension on _TrailSize {
  int get stopCount => switch (this) { _TrailSize.short => 4, _TrailSize.classic => 6, _TrailSize.long => 8 };
  String get label => switch (this) { _TrailSize.short => 'Short', _TrailSize.classic => 'Classic', _TrailSize.long => 'Long' };
}

/// The Roll page: pick Must Visit stops on the map, order them, then roll a
/// full spontaneous trail around them.
class RollScreen extends StatefulWidget {
  const RollScreen({super.key, required this.userId});

  final String userId;

  @override
  State<RollScreen> createState() => _RollScreenState();
}

class _RollScreenState extends State<RollScreen> {
  final _repo = DestinationRepository();
  final _osm = OsmPlacesService();
  final _roller = TrailRoller();
  final _mapController = MapController();
  final _quota = RollQuota();

  LatLng _center = kDefaultMapCenter;
  List<Destination> _pool = [];
  bool _loadingArea = true;
  String? _areaLabel;

  final List<Destination> _mustVisit = [];
  _TrailSize _size = _TrailSize.classic;

  RolledTrail? _trail;
  bool _rolling = false;
  final Set<String> _rerollExcluded = {};
  int? _rerollingIndex;

  @override
  void initState() {
    super.initState();
    _quota.load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadArea());
  }

  @override
  void dispose() {
    _quota.dispose();
    super.dispose();
  }

  Future<void> _loadArea() async {
    setState(() => _loadingArea = true);
    final box = boxAround(_center, 3);

    // Both started eagerly so they run concurrently. The no-op catchError
    // on communityFuture attaches a listener immediately — without it, if
    // Appwrite errors before the (awaited-first) OSM fetch finishes, Dart
    // flags it as a genuine unhandled exception since nothing was
    // listening yet. Real handling still happens at the await below;
    // Futures support multiple independent listeners, so this doesn't
    // swallow anything.
    final osmFuture = _osm.listInBounds(south: box.south, west: box.west, north: box.north, east: box.east);
    final communityFuture =
        _repo.listInBounds(south: box.south, west: box.west, north: box.north, east: box.east)..catchError((_) {});

    List<Destination> osmPlaces = [];
    try {
      osmPlaces = await osmFuture;
    } catch (e) {
      debugPrint('Roll: OSM fetch failed — $e');
    }

    try {
      final community = await communityFuture;
      if (!mounted) return;
      setState(() {
        _pool = [...osmPlaces, ...community];
        _loadingArea = false;
      });
      debugPrint('Roll: loaded ${osmPlaces.length} OSM + ${community.length} community = ${_pool.length} candidates');
    } on DestinationException catch (e) {
      if (!mounted) return;
      setState(() {
        _pool = osmPlaces;
        _loadingArea = false;
      });
      _toast(e.message);
    }
  }

  void _onPlaceSelected(PlaceResult place) {
    setState(() {
      _center = place.latLng;
      _areaLabel = place.name;
      _mustVisit.clear();
      _trail = null;
    });
    _mapController.move(_center, 14);
    _loadArea();
  }

  void _toggleMustVisit(Destination d) {
    setState(() {
      final i = _mustVisit.indexWhere((m) => m.id == d.id);
      if (i >= 0) {
        _mustVisit.removeAt(i);
      } else {
        _mustVisit.add(d);
      }
    });
  }

  void _reorderMustVisit(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _mustVisit.removeAt(oldIndex);
      _mustVisit.insert(newIndex, item);
    });
  }

  Future<void> _roll() async {
    final premium = MonetizationService.instance.isPremium.value;
    if (!_quota.canRoll(premium: premium)) {
      _offerUpgrade("You've used today's free rolls.");
      return;
    }
    if (_pool.length < _mustVisit.length + 1) {
      _toast('Not enough destinations here yet — try Build to add some, or search a busier area.');
      return;
    }

    setState(() => _rolling = true);
    await Future.delayed(const Duration(milliseconds: 550)); // let the dice feel like they're rolling
    final rolled = _roller.roll(
      pool: _pool,
      mustVisit: _mustVisit,
      stopCount: _size.stopCount,
      anchor: _center,
    );
    await _quota.consume(premium: premium);
    if (!mounted) return;
    setState(() {
      _trail = rolled;
      _rolling = false;
      _rerollExcluded.clear();
    });
    _fitTrailOnMap(rolled);
  }

  Future<void> _rerollStop(int index) async {
    final premium = MonetizationService.instance.isPremium.value;
    if (!premium) {
      _offerUpgrade('Re-rolling a single stop is a Premium feature.');
      return;
    }
    final trail = _trail;
    if (trail == null) return;

    setState(() => _rerollingIndex = index);
    await Future.delayed(const Duration(milliseconds: 350));
    final replacement = _roller.rerollCandidate(
      trail: trail,
      index: index,
      pool: _pool,
      exclude: _rerollExcluded,
    );
    if (!mounted) return;
    setState(() {
      _rerollingIndex = null;
      if (replacement == null) {
        _toast('No other nearby destination to swap in.');
        return;
      }
      _rerollExcluded.add(replacement.id);
      _trail = trail.replaceAt(index, replacement);
    });
    _fitTrailOnMap(_trail!);
  }

  Future<void> _offerUpgrade(String reason) async {
    final upgraded = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.parchment50,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _PaywallSheet(reason: reason),
    );
    if (upgraded != true || !mounted) return;
    final ok = await MonetizationService.instance.presentPaywall();
    if (!mounted) return;
    if (ok) {
      _toast('Welcome to Premium 🎉');
      setState(() {});
    } else if (!MonetizationService.instance.canPurchase) {
      _toast('Purchases aren\'t available in this build.');
    }
  }

  void _fitTrailOnMap(RolledTrail trail) {
    if (trail.stops.isEmpty) return;
    final lats = trail.stops.map((s) => s.location.latitude);
    final lngs = trail.stops.map((s) => s.location.longitude);
    final bounds = LatLngBounds(
      LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
      LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(40, 40, 40, 260)));
    });
  }

  void _editTrail() => setState(() => _trail = null);

  void _startTrail() {
    _toast('Trail started — safe travels! (Turn-by-turn isn\'t wired up in this build.)');
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
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: _map()),
              Positioned(top: 10, left: 12, right: 12, child: PlaceSearchBar(hint: 'Search an area…', onSelected: _onPlaceSelected)),
              if (_loadingArea)
                const Positioned(top: 68, left: 0, right: 0, child: _LoadingPill()),
              if (_trail == null) _selectingSheet() else _rolledSheet(_trail!),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Roll', style: AppText.headline(size: 22)),
            const SizedBox(height: 2),
            Text(
              _areaLabel ?? 'Build your adventure',
              style: AppText.body(size: 12.5, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: MonetizationService.instance.isPremium,
          builder: (context, premium, _) => AnimatedBuilder(
            animation: _quota,
            builder: (context, _) => RollQuotaBadge(
              premium: premium,
              remaining: _quota.remaining,
              onTap: () => _offerUpgrade('Go Premium for unlimited rolls.'),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _map() {
    final trail = _trail;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 14,
        // Refresh the candidate pool as the map is panned — but only while
        // still picking Must Visit stops. Once a trail is rolled, the pool
        // stays fixed to what was actually rolled from, so browsing the
        // route on the map doesn't quietly swap the re-roll candidates out
        // from under a trail the user is reviewing.
        onMapEvent: (event) {
          if (_trail != null) return;
          if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
            _center = _mapController.camera.center;
            _loadArea();
          }
        },
      ),
      children: [
        osmTileLayer(),
        if (trail != null)
          PolylineLayer(polylines: [
            Polyline(points: trail.stops.map((s) => s.location).toList(), strokeWidth: 4, color: AppColors.blaze600.withValues(alpha: 0.75)),
          ]),
        MarkerLayer(markers: [
          if (trail == null) ...[
            for (final d in _pool)
              Marker(
                point: d.location,
                width: 40,
                height: 40,
                alignment: d.isCommunity ? Alignment.topCenter : Alignment.center,
                child: GestureDetector(
                  onTap: () => _toggleMustVisit(d),
                  child: _mustVisit.any((m) => m.id == d.id)
                      ? _MustVisitPin(order: _mustVisit.indexWhere((m) => m.id == d.id) + 1)
                      : Opacity(opacity: 0.85, child: d.isCommunity ? CommunityPin(category: d.category) : ExistingPin(category: d.category)),
                ),
              ),
          ] else ...[
            for (var i = 0; i < trail.stops.length; i++)
              Marker(
                point: trail.stops[i].location,
                width: 34,
                height: 34,
                child: GestureDetector(
                  onTap: () => _showStopSheet(i),
                  child: NumberedPin(number: i + 1, must: trail.isMust(i), highlight: _rerollingIndex == i),
                ),
              ),
          ],
        ]),
        const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
      ],
    );
  }

  void _showStopSheet(int index) {
    final trail = _trail;
    if (trail == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.parchment50,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: SingleChildScrollView(
          child: DestinationDetail(destination: trail.stops[index], userId: widget.userId, photoHeight: 150),
        ),
      ),
    );
  }

  Widget _selectingSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.34,
      minChildSize: 0.2,
      maxChildSize: 0.7,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.parchment50,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4))),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                children: [
                  Row(children: [
                    Text('Must Visit', style: AppText.headline(size: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _mustVisit.isEmpty ? 'tap pins on the map to add stops' : '${_mustVisit.length} picked · drag to reorder',
                        style: AppText.body(size: 11.5, color: Colors.black45),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  if (_mustVisit.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const Icon(Icons.touch_app_outlined, color: AppColors.moss600),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Optional — tap any pin to mark it Must Visit, or just roll and let the dice decide.', style: AppText.body(size: 12.5, color: Colors.black54))),
                      ]),
                    )
                  else
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onReorder: _reorderMustVisit,
                      itemCount: _mustVisit.length,
                      itemBuilder: (context, i) => Padding(
                        key: ValueKey(_mustVisit[i].id),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MustVisitRow(number: i + 1, destination: _mustVisit[i], onRemove: () => _toggleMustVisit(_mustVisit[i])),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Text('Trail length', style: AppText.body(size: 12.5, weight: FontWeight.w600, color: Colors.black54)),
                  const SizedBox(height: 8),
                  Row(
                    children: _TrailSize.values.map((s) {
                      final selected = s == _size;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _size = s),
                          child: Container(
                            margin: EdgeInsets.only(right: s != _TrailSize.long ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: selected ? AppColors.pine800 : AppColors.parchment100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(child: Text(s.label, style: AppText.body(size: 12.5, weight: FontWeight.w600, color: selected ? AppColors.parchment50 : AppColors.ink.withValues(alpha: 0.6)))),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _quota,
                    builder: (context, _) => ValueListenableBuilder<bool>(
                      valueListenable: MonetizationService.instance.isPremium,
                      builder: (context, premium, _) {
                        if (!premium && _quota.remaining == 0) {
                          return OutOfRollsBanner(onUpgrade: () => _offerUpgrade('Go Premium for unlimited rolls.'));
                        }
                        return _RollButton(rolling: _rolling, onTap: _roll);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _rolledSheet(RolledTrail trail) {
    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.2,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.parchment50,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 12)],
          ),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Your trail', style: AppText.headline(size: 16)),
                    Text(
                      '${trail.stops.length} stops · ${formatMinutes(trail.totalMinutes)} · ${formatDistance(trail.totalMeters)}',
                      style: AppText.mono(size: 11, color: AppColors.moss600),
                    ),
                  ]),
                ),
                TextButton.icon(onPressed: _editTrail, icon: const Icon(Icons.tune, size: 16), label: const Text('Edit')),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                itemCount: trail.stops.length,
                itemBuilder: (context, i) => StopCard(
                  number: i + 1,
                  destination: trail.stops[i],
                  isMust: trail.isMust(i),
                  onTap: () => _showStopSheet(i),
                  onReroll: () => _rerollStop(i),
                  rerolling: _rerollingIndex == i,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + MediaQuery.of(context).padding.bottom),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _startTrail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blaze600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text('Start this trail', style: AppText.body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _MustVisitPin extends StatelessWidget {
  const _MustVisitPin({required this.order});
  final int order;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.blaze600,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold500, width: 2.5),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Center(child: Text('$order', style: AppText.mono(size: 14, weight: FontWeight.w700, color: Colors.white))),
    );
  }
}

class _MustVisitRow extends StatelessWidget {
  const _MustVisitRow({required this.number, required this.destination, required this.onRemove});
  final int number;
  final Destination destination;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(color: AppColors.blaze600, shape: BoxShape.circle),
          child: Center(child: Text('$number', style: AppText.mono(size: 11, weight: FontWeight.w700, color: Colors.white))),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(destination.name, style: AppText.body(size: 13, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onRemove, visualDensity: VisualDensity.compact),
        const Icon(Icons.drag_handle, size: 18, color: Colors.black38),
      ]),
    );
  }
}

class _RollButton extends StatelessWidget {
  const _RollButton({required this.rolling, required this.onTap});
  final bool rolling;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: rolling ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(color: AppColors.gold500, borderRadius: BorderRadius.circular(16)),
        child: Center(
          child: rolling
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.pine950))
              : Text('🎲  ROLL', style: AppText.body(size: 16, weight: FontWeight.w800, color: AppColors.pine950)),
        ),
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: AppColors.parchment50, borderRadius: BorderRadius.circular(20), boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
        ]),
        child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.workspace_premium, color: AppColors.gold500, size: 32),
        const SizedBox(height: 12),
        Text('Go Premium', style: AppText.headline(size: 20)),
        const SizedBox(height: 6),
        Text(reason, style: AppText.body(size: 13, color: Colors.black54)),
        const SizedBox(height: 16),
        _perk('Unlimited rolls, every day'),
        _perk('Re-roll a single stop without losing the rest of the trail'),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now'))),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blaze600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Upgrade'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _perk(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          const Icon(Icons.check_circle, size: 16, color: AppColors.moss600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.body(size: 13))),
        ]),
      );
}

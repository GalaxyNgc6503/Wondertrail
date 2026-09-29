import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trail_stop.dart';
import '../../services/appwrite_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';
import '../explore/stop_gallery_screen.dart';
import 'quick_drop_sheet.dart';

/// The Traveller's home screen: a live map where a roll picks a whole
/// trail, and the search circle travels with you.
///
/// - Roll picks a whole trail that has a stop inside the circle and joins
///   it there. The full route is drawn with numbered stops.
/// - The circle always sits on the current stop. Rolling again glides it
///   to the next stop; tapping any numbered stop moves it there.
/// - At the last stop, rolling hops to a different trail that has a stop
///   inside the circle around where you're standing.
/// - Other trails' stops inside the circle show as small dim pins; tapping
///   one switches to that whole trail.
/// - Long-pressing an empty spot drops a new pin into the database as a
///   single-stop trail.
class RollMapScreen extends StatefulWidget {
  const RollMapScreen({super.key});

  @override
  State<RollMapScreen> createState() => _RollMapScreenState();
}

class _RollMapScreenState extends State<RollMapScreen>
    with SingleTickerProviderStateMixin {
  final TrailRepository _repository = TrailRepository();
  final GeocodingService _geocoding = GeocodingService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  // No geolocator wiring yet (needs platform permissions from `flutter
  // create`, same caveat as elsewhere in this codebase) — a low-zoom
  // world view is the honest starting point rather than guessing a city.
  static const LatLng _fallbackCenter = LatLng(20, 0);

  // Search
  LatLng? _searchCenter;
  List<GeocodingResult> _suggestions = <GeocodingResult>[];
  bool _searching = false;

  // Circle
  double _radiusKm = 0.6;
  bool _settingsExpanded = false;
  late final AnimationController _glide;
  LatLng? _glideFrom;
  LatLng? _glideTo;

  // The trail being walked
  Trail? _trail;
  int _index = 0; // current stop
  int _entry = 0; // stop where this walk began

  // Other stops inside the circle (hop targets), around the circle centre
  List<TrailStop> _pool = <TrailStop>[];
  int _poolRequest = 0;
  bool _loadingPool = false;

  final Map<String, int> _laneByTrailId = <String, int>{};
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _glide.dispose();
    _searchController.dispose();
    _geocoding.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------

  TrailStop? get _currentStop {
    final Trail? t = _trail;
    if (t == null || t.stops.isEmpty) return null;
    return t.stops[_index.clamp(0, t.stops.length - 1)];
  }

  /// Where the circle sits: on the current stop while a trail is active,
  /// otherwise on the searched place.
  LatLng? get _circleCenter {
    final TrailStop? s = _currentStop;
    if (s != null) return LatLng(s.lat, s.lng);
    return _searchCenter;
  }

  LatLng? get _glidePosition {
    final LatLng? to = _glideTo;
    if (to == null) return null;
    final LatLng from = _glideFrom ?? to;
    final double t = Curves.easeInOutCubic.transform(_glide.value);
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  int _laneIndexFor(String trailId) =>
      _laneByTrailId.putIfAbsent(trailId, () => _laneByTrailId.length);

  Color _colorForTrail(String trailId) =>
      AppColors.laneColorFor(_laneIndexFor(trailId));

  double _distanceKm(LatLng a, LatLng b) =>
      haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Other trails' stops inside the circle — never the active trail's own
  /// stops, which are drawn as numbered pins instead.
  List<TrailStop> get _hopPins {
    final String? activeId = _trail?.id;
    return _pool.where((TrailStop s) => s.trailId != activeId).toList();
  }

  int get _hopTrailCount =>
      _hopPins.map((TrailStop s) => s.trailId).toSet().length;

  // ---------------------------------------------------------------------
  // Circle + camera
  // ---------------------------------------------------------------------

  void _snapCircleTo(LatLng point) {
    _glideFrom = point;
    _glideTo = point;
    _glide.value = 1;
  }

  void _glideCircleTo(LatLng point) {
    _glideFrom = _glidePosition ?? _glideTo ?? point;
    _glideTo = point;
    _glide.forward(from: 0);
  }

  void _fitTrail(Trail trail) {
    if (trail.stops.isEmpty) return;
    final List<LatLng> pts =
        trail.stops.map((TrailStop s) => LatLng(s.lat, s.lng)).toList();
    if (pts.length == 1) {
      _mapController.move(pts.first, 15);
      return;
    }
    final double h = MediaQuery.of(context).size.height;
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: EdgeInsets.fromLTRB(48, h * 0.22, 48, h * 0.48),
      ),
    );
  }

  void _keepVisible(LatLng point) {
    final MapCamera cam = _mapController.camera;
    if (!cam.visibleBounds.contains(point)) {
      _mapController.move(point, cam.zoom);
    }
  }

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  void _onSearchChanged(String query) {
    setState(() => _searching = query.trim().isNotEmpty);
    _geocoding.searchDebounced(
      query: query,
      onResults: (List<GeocodingResult> results) {
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _searching = false);
      },
    );
  }

  Future<void> _selectSearchResult(GeocodingResult result) async {
    setState(() {
      _searchCenter = result.point;
      _searchController.text = result.label;
      _suggestions = const <GeocodingResult>[];
      _trail = null;
      _index = 0;
      _entry = 0;
      _pool = <TrailStop>[];
      _status = null;
    });
    FocusScope.of(context).unfocus();
    _snapCircleTo(result.point);
    _mapController.move(result.point, 14);
    await _loadPool();
  }

  // ---------------------------------------------------------------------
  // Loading what's inside the circle
  // ---------------------------------------------------------------------

  Future<void> _loadPool() async {
    final LatLng? center = _circleCenter;
    if (center == null) return;
    final int request = ++_poolRequest;
    setState(() => _loadingPool = true);
    try {
      final List<TrailStop> pool = await _repository.fetchCrossTrailPoolNear(
        center: center,
        travellerRadiusKm: _radiusKm,
      );
      if (!mounted || request != _poolRequest) return;
      setState(() {
        _pool = pool;
        _loadingPool = false;
      });
    } catch (_) {
      if (!mounted || request != _poolRequest) return;
      setState(() => _loadingPool = false);
    }
  }

  // ---------------------------------------------------------------------
  // Moving along and between trails
  // ---------------------------------------------------------------------

  /// Join [trail] at the first stop if it's inside the circle around
  /// [center], otherwise at the nearest stop that is.
  int _entryIndex(Trail trail, LatLng center) {
    int best = 0;
    double bestDistance = double.infinity;
    for (int i = 0; i < trail.stops.length; i++) {
      final double d =
          _distanceKm(center, LatLng(trail.stops[i].lat, trail.stops[i].lng));
      if (i == 0 && d <= _radiusKm) return 0;
      if (d <= _radiusKm && d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  void _goToIndex(int i) {
    final Trail? t = _trail;
    if (t == null) return;
    final int next = i.clamp(0, t.stops.length - 1);
    final TrailStop s = t.stops[next];
    final LatLng point = LatLng(s.lat, s.lng);
    setState(() {
      _index = next;
      if (next < _entry) _entry = next;
      _status = null;
    });
    _glideCircleTo(point);
    _keepVisible(point);
    _loadPool();
  }

  void _startTrail(Trail trail, int index) {
    final TrailStop s = trail.stops[index];
    final LatLng point = LatLng(s.lat, s.lng);
    _laneIndexFor(trail.id ?? '');
    setState(() {
      _trail = trail;
      _index = index;
      _entry = index;
      _status = null;
    });
    _glideCircleTo(point);
    _fitTrail(trail);
    _loadPool();
  }

  Future<void> _onRoll() async {
    if (_circleCenter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search a location to start rolling.')),
      );
      return;
    }

    final Trail? current = _trail;
    // Mid-trail: the circle glides on to the next stop.
    if (current != null && _index < current.stops.length - 1) {
      _goToIndex(_index + 1);
      return;
    }

    // No trail yet, or at the last stop: pick a whole trail that has a
    // stop inside the circle and join it there.
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final LatLng center = _circleCenter!;
      final List<TrailStop> pool = await _repository.fetchCrossTrailPoolNear(
        center: center,
        travellerRadiusKm: _radiusKm,
      );
      final List<String> ids = pool
          .map((TrailStop s) => s.trailId)
          .toSet()
          .where((String id) => id != current?.id)
          .toList();
      if (!mounted) return;
      if (ids.isEmpty) {
        setState(() {
          _busy = false;
          _pool = pool;
          _status = current != null
              ? 'That was the last stop, and no other trails are within '
                  '${_radiusKm.toStringAsFixed(2)} km.'
              : 'No trails within ${_radiusKm.toStringAsFixed(2)} km. '
                  'Try a wider radius.';
        });
        return;
      }
      ids.shuffle();
      final Trail next = await _repository.fetchTrailWithStops(ids.first);
      if (!mounted) return;
      if (next.stops.isEmpty) {
        setState(() {
          _busy = false;
          _status = "That trail has no stops yet. Roll again.";
        });
        return;
      }
      setState(() => _busy = false);
      _startTrail(next, _entryIndex(next, center));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = "Couldn't roll — check your connection and try again.";
      });
    }
  }

  /// Tapping a dim pin from another trail: switch to that whole trail
  /// with that stop as the current one.
  Future<void> _onHopPinTapped(TrailStop stop) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final Trail next = await _repository.fetchTrailWithStops(stop.trailId);
      if (!mounted) return;
      final int i = next.stops.indexWhere((TrailStop s) => s.id == stop.id);
      setState(() => _busy = false);
      if (next.stops.isEmpty) return;
      _startTrail(next, i < 0 ? 0 : i);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = "Couldn't open that trail — try again.";
      });
    }
  }

  void _clearTrail() {
    final LatLng? back = _searchCenter;
    setState(() {
      _trail = null;
      _index = 0;
      _entry = 0;
      _status = null;
    });
    if (back != null) {
      _glideCircleTo(back);
      _loadPool();
    }
  }

  // ---------------------------------------------------------------------
  // Dropping a pin
  // ---------------------------------------------------------------------

  Future<void> _onLongPressMap(LatLng point) async {
    final Trail? created = await showModalBottomSheet<Trail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.parchment50,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => QuickDropSheet(point: point),
    );
    if (created == null || !mounted || created.stops.isEmpty) return;
    _startTrail(created, 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Saved! It's live and rollable now.")),
    );
  }

  void _openGallery(TrailStop stop) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StopGalleryScreen(
          photoFileIds: stop.photoFileIds,
          title: stop.name,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Trail? trail = _trail;
    final Color trailColor =
        trail == null ? AppColors.blaze600 : _colorForTrail(trail.id ?? '');
    final List<LatLng> route = trail == null
        ? const <LatLng>[]
        : trail.stops.map((TrailStop s) => LatLng(s.lat, s.lng)).toList();
    final List<LatLng> walked = (trail == null || _index < _entry)
        ? const <LatLng>[]
        : route.sublist(_entry, _index + 1);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 2,
              onLongPress: (_, LatLng point) => _onLongPressMap(point),
            ),
            children: <Widget>[
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.wondertrail.mobile',
              ),
              // The circle glides between stops rather than jumping.
              AnimatedBuilder(
                animation: _glide,
                builder: (BuildContext context, Widget? _) {
                  final LatLng? at = _glidePosition;
                  if (at == null) return const SizedBox.shrink();
                  return CircleLayer(
                    circles: <CircleMarker>[
                      CircleMarker(
                        point: at,
                        radius: _radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: AppColors.blaze600.withValues(alpha: 0.08),
                        borderColor: AppColors.blaze600.withValues(alpha: 0.55),
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  );
                },
              ),
              if (route.length > 1)
                PolylineLayer(
                  polylines: <Polyline>[
                    Polyline(
                      points: route,
                      strokeWidth: 9,
                      color: AppColors.parchment50.withValues(alpha: 0.85),
                    ),
                    Polyline(
                      points: route,
                      strokeWidth: 4,
                      color: trailColor,
                      pattern: StrokePattern.dotted(),
                    ),
                    if (walked.length > 1)
                      Polyline(
                        points: walked,
                        strokeWidth: 4,
                        color: trailColor,
                      ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers(trail, trailColor)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _TopControls(
                searchController: _searchController,
                onSearchChanged: _onSearchChanged,
                busy: _searching || _loadingPool,
                suggestions: _suggestions,
                onSuggestionSelected: _selectSearchResult,
                radiusKm: _radiusKm,
                onRadiusChanged: (double v) => setState(() => _radiusKm = v),
                onRadiusChangeEnd: (_) => _loadPool(),
                expanded: _settingsExpanded,
                onToggleExpanded: () =>
                    setState(() => _settingsExpanded = !_settingsExpanded),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _BottomPanel(
                trail: trail,
                trailColor: trailColor,
                index: _index,
                statusText: _statusText(),
                rollLabel: _rollLabel(),
                busy: _busy,
                hasCenter: _circleCenter != null,
                onRoll: _onRoll,
                onClear: _clearTrail,
                onSelectStop: _goToIndex,
                onOpenGallery: _openGallery,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(Trail? trail, Color trailColor) {
    final List<Marker> markers = <Marker>[];

    // Where you searched — stays put while the circle moves on.
    if (_searchCenter != null) {
      markers.add(
        Marker(
          point: _searchCenter!,
          width: 22,
          height: 22,
          child: const Icon(
            Icons.my_location,
            color: AppColors.pine950,
            size: 20,
          ),
        ),
      );
    }

    // Other trails' stops inside the circle: small dim hop targets.
    for (final TrailStop stop in _hopPins) {
      final Color color = _colorForTrail(stop.trailId);
      markers.add(
        Marker(
          point: LatLng(stop.lat, stop.lng),
          width: 40,
          height: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => _onHopPinTapped(stop),
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.parchment50, width: 2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // The active trail: numbered stops, the current one enlarged.
    if (trail != null) {
      for (int i = 0; i < trail.stops.length; i++) {
        final TrailStop stop = trail.stops[i];
        final bool current = i == _index;
        final double size = current ? 40 : 30;
        markers.add(
          Marker(
            point: LatLng(stop.lat, stop.lng),
            width: size + 12,
            height: size + 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToIndex(i),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: trailColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current ? AppColors.gold500 : AppColors.parchment50,
                      width: current ? 3 : 2,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppText.statStrong(color: Colors.white)
                        .copyWith(fontSize: current ? 16 : 13),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  String _rollLabel() {
    final Trail? t = _trail;
    if (t == null) return 'Roll a trail';
    return _index < t.stops.length - 1 ? 'Next stop' : 'Roll another trail';
  }

  String _statusText() {
    if (_status != null) return _status!;
    final String r = _radiusKm.toStringAsFixed(2);
    final int others = _hopTrailCount;
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final Trail? t = _trail;

    if (t == null) {
      if (_searchCenter == null) return 'Search a location to start rolling.';
      return others > 0
          ? '${plural(others, 'trail', 'trails')} within $r km'
          : 'No trails within $r km. Try a wider radius.';
    }
    if (_index == t.stops.length - 1) {
      return others > 0
          ? 'Last stop. Roll to hop to one of '
              '${plural(others, 'nearby trail', 'nearby trails')}.'
          : 'Last stop. No other trails within the circle.';
    }
    return 'Stop ${_index + 1} of ${t.stops.length}'
        '${others > 0 ? ', ${plural(others, 'other trail', 'other trails')} within $r km' : ''}';
  }
}

class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.searchController,
    required this.onSearchChanged,
    required this.busy,
    required this.suggestions,
    required this.onSuggestionSelected,
    required this.radiusKm,
    required this.onRadiusChanged,
    required this.onRadiusChangeEnd,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool busy;
  final List<GeocodingResult> suggestions;
  final ValueChanged<GeocodingResult> onSuggestionSelected;
  final double radiusKm;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<double> onRadiusChangeEnd;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: <Widget>[
          Material(
            elevation: 3,
            borderRadius: BorderRadius.circular(14),
            color: AppColors.parchment50,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    style: AppText.body(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      hintText: 'Search a location to start rolling',
                      prefixIcon: const Icon(Icons.search, color: AppColors.ink),
                      suffixIcon: busy
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    expanded ? Icons.tune : Icons.tune_outlined,
                    color: AppColors.blaze600,
                  ),
                  onPressed: onToggleExpanded,
                  tooltip: 'Circle size',
                ),
              ],
            ),
          ),
          if (suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: AppColors.parchment100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int i) {
                    final GeocodingResult r = suggestions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.place_outlined,
                        color: AppColors.blaze600,
                      ),
                      title: Text(r.label, style: AppText.body()),
                      onTap: () => onSuggestionSelected(r),
                    );
                  },
                ),
              ),
            ),
          if (expanded)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              decoration: BoxDecoration(
                color: AppColors.parchment50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text('Searching radius', style: AppText.label()),
                      Text('${radiusKm.toStringAsFixed(2)} km',
                          style: AppText.statStrong()),
                    ],
                  ),
                  Slider(
                    value: radiusKm,
                    min: 0.1,
                    max: 1,
                    divisions: 18,
                    activeColor: AppColors.blaze600,
                    onChanged: onRadiusChanged,
                    onChangeEnd: onRadiusChangeEnd,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.parchment50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Long-press the map to drop a pin',
                  style: AppText.caption(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.trail,
    required this.trailColor,
    required this.index,
    required this.statusText,
    required this.rollLabel,
    required this.busy,
    required this.hasCenter,
    required this.onRoll,
    required this.onClear,
    required this.onSelectStop,
    required this.onOpenGallery,
  });

  final Trail? trail;
  final Color trailColor;
  final int index;
  final String statusText;
  final String rollLabel;
  final bool busy;
  final bool hasCenter;
  final VoidCallback onRoll;
  final VoidCallback onClear;
  final ValueChanged<int> onSelectStop;
  final ValueChanged<TrailStop> onOpenGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.parchment50.withValues(alpha: 0.0),
            AppColors.parchment50,
          ],
          stops: const <double>[0, 0.3],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (trail != null && trail!.stops.isNotEmpty) ...<Widget>[
            _TrailCard(
              trail: trail!,
              color: trailColor,
              index: index,
              onClear: onClear,
              onSelectStop: onSelectStop,
              onOpenGallery: onOpenGallery,
            ),
            const SizedBox(height: 10),
          ],
          Text(
            statusText,
            style: AppText.caption(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (busy || !hasCenter) ? null : onRoll,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold500,
                foregroundColor: AppColors.pine950,
                disabledBackgroundColor: AppColors.gold500.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.pine950,
                      ),
                    )
                  : Text(
                      '🎲  $rollLabel',
                      style: AppText.button(color: AppColors.pine950)
                          .copyWith(fontSize: 17),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailCard extends StatelessWidget {
  const _TrailCard({
    required this.trail,
    required this.color,
    required this.index,
    required this.onClear,
    required this.onSelectStop,
    required this.onOpenGallery,
  });

  final Trail trail;
  final Color color;
  final int index;
  final VoidCallback onClear;
  final ValueChanged<int> onSelectStop;
  final ValueChanged<TrailStop> onOpenGallery;

  double get _totalKm {
    double km = 0;
    for (int i = 0; i < trail.stops.length - 1; i++) {
      km += haversineKm(
        trail.stops[i].lat,
        trail.stops[i].lng,
        trail.stops[i + 1].lat,
        trail.stops[i + 1].lng,
      );
    }
    return km;
  }

  int get _totalMinutes => trail.stops.fold<int>(
        0,
        (int sum, TrailStop s) => sum + (s.recommendedTimeMinutes ?? 0),
      );

  String _minutes(int m) {
    if (m < 60) return '$m min';
    final int rest = m % 60;
    return rest == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h $rest min';
  }

  @override
  Widget build(BuildContext context) {
    final int count = trail.stops.length;
    final TrailStop stop = trail.stops[index.clamp(0, count - 1)];
    final String? thumbId =
        stop.photoFileIds.isNotEmpty ? stop.photoFileIds.first : null;

    // A Border with only a left side can't be combined with a
    // borderRadius (Flutter asserts on non-uniform borders), so the
    // coloured accent is a separate strip clipped by the rounded card.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.parchment100,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.pine950.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(trail.title, style: AppText.trailName()),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 14,
                        children: <Widget>[
                          Text(
                            '$count ${count == 1 ? 'stop' : 'stops'}',
                            style: AppText.stat(),
                          ),
                          if (count > 1)
                            Text('${_totalKm.toStringAsFixed(1)} km',
                                style: AppText.stat()),
                          if (_totalMinutes > 0)
                            Text(_minutes(_totalMinutes), style: AppText.stat()),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.ink.withValues(alpha: 0.6),
                  tooltip: 'Clear this trail',
                  onPressed: onClear,
                ),
              ],
            ),
          ),
          if (count > 1)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                itemCount: count,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int i) {
                  final bool current = i == index;
                  return InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onSelectStop(i),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
                      decoration: BoxDecoration(
                        color: current ? color : AppColors.parchment50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: current ? AppColors.parchment50 : color,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: AppText.tag(
                                color: current ? color : AppColors.parchment50,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            trail.stops[i].name,
                            style: AppText.label(
                              color: current
                                  ? AppColors.parchment50
                                  : AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          InkWell(
            onTap: () => onOpenGallery(stop),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: thumbId != null
                          ? Image.network(
                              AppwriteService.instance.fileViewUrl(thumbId),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(stop.name, style: AppText.stopName()),
                        if (stop.note.isNotEmpty)
                          Text(
                            stop.note,
                            style: AppText.body(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          children: <Widget>[
                            Text(stop.category, style: AppText.tag()),
                            if (stop.recommendedTimeMinutes != null)
                              Text('${stop.recommendedTimeMinutes} min',
                                  style: AppText.tag()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 5, color: color),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.moss600, AppColors.pine800],
        ),
      ),
      child: Icon(Icons.photo_outlined, color: AppColors.parchment50),
    );
  }
}

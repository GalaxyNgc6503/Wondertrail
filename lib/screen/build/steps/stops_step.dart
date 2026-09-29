import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_theme.dart';
import '../add_stop.dart';
import '../trail_draft.dart';

class StopsStep extends StatefulWidget {
  const StopsStep({
    super.key,
    required this.draft,
    required this.onDraftChanged,
  });

  final TrailDraft draft;
  final VoidCallback onDraftChanged;

  @override
  State<StopsStep> createState() => _StopsStepState();
}

class _StopsStepState extends State<StopsStep> {
  Future<void> _addStop() async {
    final StopDraft? result = await Navigator.of(context).push<StopDraft>(
      MaterialPageRoute<StopDraft>(builder: (_) => const AddStopScreen()),
    );
    if (result == null) return;
    setState(() => widget.draft.stops.add(result));
    widget.onDraftChanged();
  }

  Future<void> _editStop(StopDraft existing) async {
    final StopDraft? result = await Navigator.of(context).push<StopDraft>(
      MaterialPageRoute<StopDraft>(
        builder: (_) => AddStopScreen(initial: existing),
      ),
    );
    if (result == null) return;
    setState(() {
      final int i = widget.draft.stops.indexWhere((StopDraft s) => s.id == existing.id);
      if (i != -1) widget.draft.stops[i] = result;
    });
    widget.onDraftChanged();
  }

  void _removeStop(StopDraft stop) {
    setState(() => widget.draft.stops.removeWhere((StopDraft s) => s.id == stop.id));
    widget.onDraftChanged();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final StopDraft moved = widget.draft.stops.removeAt(oldIndex);
      widget.draft.stops.insert(newIndex, moved);
    });
    widget.onDraftChanged();
  }

  @override
  Widget build(BuildContext context) {
    final List<StopDraft> stops = widget.draft.stops;

    return Column(
      children: <Widget>[
        if (stops.length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SizedBox(
              height: 180,
              child: _NonInteractiveDraftMap(stops: stops),
            ),
          ),
        // Always visible regardless of list state — this is the fix.
        // The old code only offered "+ Add a stop" inside the empty
        // state below, so there was no way to add a second stop once
        // the first one existed.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Stops (${stops.length})', style: AppText.sectionHeading()),
              TextButton.icon(
                onPressed: _addStop,
                icon: const Icon(Icons.add),
                label: const Text('Add a stop'),
              ),
            ],
          ),
        ),
        Expanded(
          child: stops.isEmpty
              ? const _EmptyStopsState()
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                  itemCount: stops.length,
                  onReorder: _reorder,
                  itemBuilder: (BuildContext context, int i) {
                    final StopDraft stop = stops[i];
                    return Padding(
                      key: ValueKey<String>(stop.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _StopCard(
                        index: i,
                        stop: stop,
                        onTap: () => _editStop(stop),
                        onRemove: () => _removeStop(stop),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyStopsState extends StatelessWidget {
  const _EmptyStopsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.flag_outlined, size: 36, color: AppColors.ink.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Add at least 2 stops to continue.',
              style: AppText.body(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.index,
    required this.stop,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final StopDraft stop;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(top: 18, right: 4),
                  child: Icon(Icons.drag_handle, color: AppColors.ink),
                ),
              ),
              _Thumb(stop: stop),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${index + 1}. ${stop.name}', style: AppText.stopName()),
                    if (stop.note.isNotEmpty)
                      Text(
                        stop.note,
                        style: AppText.body(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
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
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.blaze700),
                onPressed: onRemove,
                tooltip: 'Remove stop',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.stop});
  final StopDraft stop;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: stop.photos.isEmpty
                ? const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[AppColors.moss600, AppColors.pine800],
                      ),
                    ),
                  )
                : FutureBuilder<Uint8List>(
                    future: stop.photos.first.readAsBytes(),
                    builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                      if (!snap.hasData) {
                        return Container(color: AppColors.parchment100);
                      }
                      return Image.memory(snap.data!, fit: BoxFit.cover);
                    },
                  ),
          ),
        ),
        if (stop.photos.length > 1)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.pine950.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+${stop.photos.length - 1}',
                style: AppText.caption(color: AppColors.parchment50)
                    .copyWith(fontSize: 10),
              ),
            ),
          ),
      ],
    );
  }
}

class _NonInteractiveDraftMap extends StatelessWidget {
  const _NonInteractiveDraftMap({required this.stops});
  final List<StopDraft> stops;

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = stops
        .where((StopDraft s) => s.hasLocation)
        .map((StopDraft s) => LatLng(s.lat!, s.lng!))
        .toList();
    if (points.length < 2) return const SizedBox.shrink();

    final LatLngBounds bounds = LatLngBounds.fromPoints(points);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit:
              CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
        ),
        children: <Widget>[
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'app.wondertrail.mobile',
          ),
          PolylineLayer(
            polylines: <Polyline>[
              Polyline(points: points, strokeWidth: 3, color: AppColors.blaze600),
            ],
          ),
          MarkerLayer(
            markers: List<Marker>.generate(points.length, (int i) {
              return Marker(
                point: points[i],
                width: 26,
                height: 26,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.blaze600,
                  child: Text('${i + 1}',
                      style: AppText.tag(color: AppColors.parchment50)),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
// `hide Path`: latlong2 exports its own generic Path<T> (a route type),
// which otherwise collides with dart:ui's Path (via material.dart) used
// below for canvas drawing — Dart resolves the bare name to latlong2's
// version silently rather than erroring, so it has to be hidden explicitly.
import 'package:latlong2/latlong.dart' hide Path;

import '../../models/trail_stop.dart';
import '../../services/appwrite_service.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';
import '../explore/stop_gallery_screen.dart';
import 'rolling_rule.dart';

class _RolledNode {
  _RolledNode({
    required this.stop,
    required this.laneIndex,
    required this.branched,
  });

  final TrailStop stop;
  final int laneIndex;

  /// True when this stop's trail differs from the previous node's trail —
  /// i.e. the chain forked onto a new branch here.
  final bool branched;
}

/// The actual rolling + git-graph rendering. Renders the rolled sequence
/// as a branching graph: one lane per distinct trail encountered this
/// session (assigned in first-seen order), straight lines for consecutive
/// same-trail stops, curved branch lines when the chain jumps trails.
class RollChainScreen extends StatefulWidget {
  const RollChainScreen({
    super.key,
    required this.center,
    required this.locationLabel,
    required this.rule,
    required this.radiusKm,
  });

  final LatLng center;
  final String locationLabel;
  final RollingRule rule;
  final double radiusKm;

  @override
  State<RollChainScreen> createState() => _RollChainScreenState();
}

class _RollChainScreenState extends State<RollChainScreen> {
  final TrailRepository _repository = TrailRepository();
  final ScrollController _scrollController = ScrollController();

  final List<_RolledNode> _chain = <_RolledNode>[];
  final Map<String, int> _laneByTrailId = <String, int>{};

  // Trail-mode session state: once a trail is picked, subsequent rolls
  // just walk it in order rather than issuing a new query.
  Trail? _trailModeTrail;
  int _trailModeIndex = -1;

  bool _loading = false;
  String? _endMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _rollNext();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _laneIndexFor(String trailId) {
    return _laneByTrailId.putIfAbsent(trailId, () => _laneByTrailId.length);
  }

  Future<void> _rollNext() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      TrailStop? next;

      switch (widget.rule) {
        case RollingRule.trail:
          next = await _nextForTrailMode();
          break;
        case RollingRule.random:
          next = await _repository.rollRandomStop(
            center: widget.center,
            radiusKm: widget.radiusKm,
          );
          break;
        case RollingRule.illPick:
          // Shouldn't normally reach here — the Roll tab intercepts this
          // rule before navigating — but handled honestly just in case.
          if (!mounted) return;
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Manual pick isn't built yet.")),
          );
          return;
      }

      if (!mounted) return;

      if (next == null) {
        setState(() {
          _loading = false;
          _endMessage = _chain.isEmpty
              ? "Nothing found within ${widget.radiusKm.toStringAsFixed(2)} km of here."
              : "Nothing left nearby — that's the end of this chain.";
        });
        return;
      }

      final int lane = _laneIndexFor(next.trailId);
      final bool branched =
          _chain.isNotEmpty && _chain.last.stop.trailId != next.trailId;

      setState(() {
        _chain.add(_RolledNode(stop: next!, laneIndex: lane, branched: branched));
        _loading = false;
        _endMessage = null;
      });

      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = "Couldn't roll — check your connection and try again.";
      });
    }
  }

  Future<TrailStop?> _nextForTrailMode() async {
    if (_trailModeTrail == null) {
      final Trail? trail = await _repository.pickRandomTrailNear(
        center: widget.center,
        radiusKm: widget.radiusKm,
      );
      if (trail == null || trail.stops.isEmpty) return null;
      _trailModeTrail = trail;
      _trailModeIndex = 0;
      return trail.stops[0];
    }

    final int nextIndex = _trailModeIndex + 1;
    if (nextIndex >= _trailModeTrail!.stops.length) {
      return null; // end of this trail — a real state, not a crash
    }
    _trailModeIndex = nextIndex;
    return _trailModeTrail!.stops[nextIndex];
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
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

  @override
  Widget build(BuildContext context) {
    final double graphWidth = 28.0 + _laneByTrailId.length * 24.0;

    return Scaffold(
      backgroundColor: AppColors.parchment50,
      appBar: AppBar(
        title: Text(widget.locationLabel, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: _chain.isEmpty && _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: _chain.length,
                      itemBuilder: (BuildContext context, int i) {
                        final _RolledNode node = _chain[i];
                        final int? prevLane =
                            i == 0 ? null : _chain[i - 1].laneIndex;
                        final int? nextLane =
                            i == _chain.length - 1 ? null : _chain[i + 1].laneIndex;
                        return _GraphRow(
                          node: node,
                          prevLaneIndex: prevLane,
                          nextLaneIndex: nextLane,
                          graphWidth: graphWidth,
                          onTap: () => _openGallery(node.stop),
                        );
                      },
                    ),
            ),
            if (_endMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _endMessage!,
                  textAlign: TextAlign.center,
                  style: AppText.caption(),
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppText.caption(color: AppColors.blaze700),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || _endMessage != null) ? null : _rollNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold500,
                    foregroundColor: AppColors.pine950,
                    disabledBackgroundColor:
                        AppColors.gold500.withValues(alpha: 0.35),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pine950,
                          ),
                        )
                      : Text(
                          '🎲  Roll next',
                          style: AppText.button(color: AppColors.pine950),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphRow extends StatelessWidget {
  const _GraphRow({
    required this.node,
    required this.prevLaneIndex,
    required this.nextLaneIndex,
    required this.graphWidth,
    required this.onTap,
  });

  final _RolledNode node;
  final int? prevLaneIndex;
  final int? nextLaneIndex;
  final double graphWidth;
  final VoidCallback onTap;

  static const double _laneSpacing = 24;
  static const double _leftPad = 20;

  double _laneX(int lane) => _leftPad + lane * _laneSpacing;

  @override
  Widget build(BuildContext context) {
    final Color laneColor = AppColors.laneColorFor(node.laneIndex);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: graphWidth,
            child: CustomPaint(
              painter: _GraphNodePainter(
                laneX: _laneX(node.laneIndex),
                prevLaneX: prevLaneIndex == null ? null : _laneX(prevLaneIndex!),
                nextLaneX: nextLaneIndex == null ? null : _laneX(nextLaneIndex!),
                color: laneColor,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 20, 6),
              child: _NodeCard(node: node, laneColor: laneColor, onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphNodePainter extends CustomPainter {
  _GraphNodePainter({
    required this.laneX,
    required this.prevLaneX,
    required this.nextLaneX,
    required this.color,
  });

  final double laneX;
  final double? prevLaneX;
  final double? nextLaneX;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height / 2;
    final Paint linePaint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (prevLaneX != null) {
      final Path path = Path()..moveTo(prevLaneX!, 0);
      if (prevLaneX == laneX) {
        path.lineTo(laneX, midY);
      } else {
        path.cubicTo(prevLaneX!, midY * 0.6, laneX, midY * 0.4, laneX, midY);
      }
      canvas.drawPath(path, linePaint);
    }

    if (nextLaneX != null) {
      final Path path = Path()..moveTo(laneX, midY);
      if (nextLaneX == laneX) {
        path.lineTo(laneX, size.height);
      } else {
        final double bottomHalf = size.height - midY;
        path.cubicTo(
          laneX,
          midY + bottomHalf * 0.4,
          nextLaneX!,
          midY + bottomHalf * 0.6,
          nextLaneX!,
          size.height,
        );
      }
      canvas.drawPath(path, linePaint);
    }

    canvas.drawCircle(Offset(laneX, midY), 7, Paint()..color = color);
    canvas.drawCircle(
      Offset(laneX, midY),
      7,
      Paint()
        ..color = AppColors.parchment50
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphNodePainter oldDelegate) {
    return oldDelegate.laneX != laneX ||
        oldDelegate.prevLaneX != prevLaneX ||
        oldDelegate.nextLaneX != nextLaneX ||
        oldDelegate.color != color;
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node, required this.laneColor, required this.onTap});

  final _RolledNode node;
  final Color laneColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TrailStop stop = node.stop;
    final String? thumbId = stop.photoFileIds.isNotEmpty ? stop.photoFileIds.first : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
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
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: laneColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            stop.trailTitle,
                            style: AppText.tag(color: laneColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (node.branched) ...<Widget>[
                          const SizedBox(width: 6),
                          Text('branched', style: AppText.caption()),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(stop.name, style: AppText.stopName()),
                    if (stop.note.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        stop.note,
                        style: AppText.body(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.moss600, AppColors.pine800],
        ),
      ),
      child: const Icon(Icons.photo_outlined, color: AppColors.parchment50),
    );
  }
}

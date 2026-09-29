import 'package:flutter/material.dart';

import '../../models/trail_stop.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';
import 'stop_gallery_screen.dart';

/// Shows one published trail: its cover, title, and ordered stops.
/// Pushed from an Explore card with the trail's id:
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => TrailDetailScreen(trailId: trail.id),
/// ));
/// ```
class TrailDetailScreen extends StatefulWidget {
  const TrailDetailScreen({super.key, required this.trailId, this.repository});

  final String trailId;

  /// Inject a repository for testing; defaults to a real Appwrite-backed one.
  final TrailRepository? repository;

  @override
  State<TrailDetailScreen> createState() => _TrailDetailScreenState();
}

class _TrailDetailScreenState extends State<TrailDetailScreen> {
  late final TrailRepository _repository = widget.repository ?? TrailRepository();
  late Future<Trail> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getTrail(widget.trailId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment50,
      body: FutureBuilder<Trail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScaffold();
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _ErrorScaffold(
              onRetry: () => setState(() => _future = _repository.getTrail(widget.trailId)),
            );
          }
          return _TrailDetailBody(trail: snapshot.data!, repository: _repository);
        },
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.blaze600))),
        ],
      ),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  const _ErrorScaffold({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 32, color: AppColors.ink.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text("Couldn't load this trail.", style: AppText.body(size: 13, color: Colors.black45)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onRetry,
                    child: Text('Try again', style: AppText.body(size: 13, weight: FontWeight.w600, color: AppColors.blaze700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailDetailBody extends StatelessWidget {
  const _TrailDetailBody({required this.trail, required this.repository});

  final Trail trail;
  final TrailRepository repository;

  @override
  Widget build(BuildContext context) {
    final coverStop = trail.stops.where((s) => s.photoFileIds != null && s.photoFileIds!.isNotEmpty).firstOrNull;
    final coverPhotoId = coverStop?.photoFileIds?.first;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: AppColors.pine800,
          expandedHeight: 220,
          pinned: true,
          iconTheme: const IconThemeData(color: AppColors.parchment50),
          flexibleSpace: FlexibleSpaceBar(
            background: coverPhotoId != null
                ? Image.network(repository.previewUrl(coverPhotoId, width: 800), fit: BoxFit.cover)
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.moss600, AppColors.pine800]),
                    ),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trail.title, style: AppText.headline(size: 23)),
                const SizedBox(height: 12),
                _buildStatRow(),
                const SizedBox(height: 18),
                Text('Stops', style: AppText.body(size: 13, weight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverList.separated(
            itemCount: trail.stops.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) => _StopRow(
              stop: trail.stops[index],
              index: index,
              isLast: index == trail.stops.length - 1,
              repository: repository,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow() {
    return Row(
      children: [
        _stat('${trail.stops.length}', 'stops'),
        const SizedBox(width: 22),
        _stat('${trail.roughDistanceKm.toStringAsFixed(1)} km', 'distance'),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppText.mono(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
        Text(label, style: AppText.mono(size: 10, color: Colors.black45)),
      ],
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.index, required this.isLast, required this.repository});

  final TrailStop stop;
  final int index;
  final bool isLast;
  final TrailRepository repository;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.blaze600),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: AppText.mono(size: 11, weight: FontWeight.w700, color: AppColors.parchment50),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: AppColors.blaze600.withOpacity(0.35)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StopGalleryScreen(stop: stop, repository: repository)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildThumb(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stop.name, style: AppText.headline(size: 15)),
                          const SizedBox(height: 2),
                          Text(stop.note, style: AppText.body(size: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb() {
    final photoIds = stop.photoFileIds ?? const [];
    if (photoIds.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(colors: [AppColors.moss600, AppColors.pine800]),
        ),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            repository.previewUrl(photoIds.first, width: 160),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(colors: [AppColors.moss600, AppColors.pine800]),
              ),
            ),
          ),
        ),
        if (photoIds.length > 1)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: AppColors.pine950.withOpacity(0.75), borderRadius: BorderRadius.circular(6)),
              child: Text('+${photoIds.length - 1}', style: AppText.mono(size: 8.5, color: AppColors.parchment50)),
            ),
          ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

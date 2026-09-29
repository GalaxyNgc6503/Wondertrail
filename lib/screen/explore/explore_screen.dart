import 'package:flutter/material.dart';

import '../../models/trail_stop.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';
import 'trail_detail_screen.dart';

/// Browse published trails, newest first. Pull to refresh.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, this.repository});

  /// Inject a repository for testing; defaults to a real Appwrite-backed one.
  final TrailRepository? repository;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TrailRepository _repository = widget.repository ?? TrailRepository();
  late Future<List<TrailSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listTrails();
  }

  Future<void> _refresh() async {
    final next = _repository.listTrails();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchment50,
      appBar: AppBar(
        backgroundColor: AppColors.parchment50,
        elevation: 0,
        title: Text('Explore', style: AppText.headline()),
      ),
      body: RefreshIndicator(
        color: AppColors.blaze600,
        onRefresh: _refresh,
        child: FutureBuilder<List<TrailSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.blaze600));
            }
            if (snapshot.hasError) {
              return _buildMessage(
                icon: Icons.cloud_off_outlined,
                message: "Couldn't load trails — pull down to try again.",
              );
            }
            final trails = snapshot.data ?? const [];
            if (trails.isEmpty) {
              return _buildMessage(
                icon: Icons.map_outlined,
                message: 'No trails yet — be the first to publish one.',
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              itemCount: trails.length,
              itemBuilder: (context, index) => _TrailCard(trail: trails[index], repository: _repository),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessage({required IconData icon, required String message}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 32, color: AppColors.ink.withOpacity(0.3)),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center, style: AppText.body(size: 13, color: Colors.black45)),
          ),
        ),
      ],
    );
  }
}

class _TrailCard extends StatelessWidget {
  const _TrailCard({required this.trail, required this.repository});

  final TrailSummary trail;
  final TrailRepository repository;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TrailDetailScreen(trailId: trail.id, repository: repository)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCover(),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(trail.title, style: AppText.headline(size: 17)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'By @${trail.authorId}',
                          style: AppText.body(size: 12, color: Colors.black45),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${trail.stopCount} stops · ${trail.distanceKm.toStringAsFixed(1)} km',
                        style: AppText.mono(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    final fileId = trail.coverPhotoFileId;
    if (fileId == null) return _coverFallback();

    return Image.network(
      repository.previewUrl(fileId, width: 500),
      height: 150,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: 150,
          color: AppColors.parchment100,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blaze600)),
        );
      },
      errorBuilder: (context, error, stack) => _coverFallback(),
    );
  }

  Widget _coverFallback() {
    return Container(
      height: 150,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.moss600, AppColors.pine800]),
      ),
    );
  }
}

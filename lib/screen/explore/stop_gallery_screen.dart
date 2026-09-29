import 'package:flutter/material.dart';

import '../../models/trail_stop.dart';
import '../../services/trail_repository.dart';
import '../../theme/app_theme.dart';

/// Shows one stop's full photo gallery (swipeable), plus its name and note.
/// Pushed from a stop row in [TrailDetailScreen]:
///
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => StopGalleryScreen(stop: stop, repository: repository),
/// ));
/// ```
class StopGalleryScreen extends StatefulWidget {
  const StopGalleryScreen({super.key, required this.stop, required this.repository});

  final TrailStop stop;
  final TrailRepository repository;

  @override
  State<StopGalleryScreen> createState() => _StopGalleryScreenState();
}

class _StopGalleryScreenState extends State<StopGalleryScreen> {
  final _pageController = PageController();
  int _page = 0;

  List<String> get _photoIds => widget.stop.photoFileIds ?? const [];

  @override
  Widget build(BuildContext context) {
    final hasPhotos = _photoIds.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.pine950,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: hasPhotos ? _buildGallery() : _buildNoPhotos(),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.parchment50),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.stop.name,
              style: AppText.headline(size: 17, color: AppColors.parchment50),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_photoIds.length > 1)
            Text('${_page + 1} / ${_photoIds.length}', style: AppText.mono(size: 11, color: AppColors.parchment50.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildGallery() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _photoIds.length,
      onPageChanged: (index) => setState(() => _page = index),
      itemBuilder: (context, index) {
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.repository.previewUrl(_photoIds[index], width: 1000),
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(color: AppColors.blaze600));
              },
              errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                size: 40,
                color: AppColors.parchment50.withOpacity(0.4),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoPhotos() {
    return Center(
      child: Icon(Icons.image_not_supported_outlined, size: 40, color: AppColors.parchment50.withOpacity(0.35)),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_photoIds.length > 1) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_photoIds.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? AppColors.blaze600 : AppColors.parchment50.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 14),
          ],
          Text(
            widget.stop.note,
            style: AppText.body(size: 13, color: AppColors.parchment50.withOpacity(0.75)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

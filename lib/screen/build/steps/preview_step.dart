import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_theme.dart';
import '../trail_draft.dart';

/// A traveller's-eye-view mock of the trail about to be published. The
/// roll button here is a visual rehearsal only — tapping it explains
/// that, rather than actually rolling. The real roll mechanic lives
/// entirely on the Traveller side (the Roll tab), never here.
class PreviewStep extends StatelessWidget {
  const PreviewStep({
    super.key,
    required this.draft,
    required this.onEditStops,
    required this.onContinueToPublish,
  });

  final TrailDraft draft;
  final VoidCallback onEditStops;
  final VoidCallback onContinueToPublish;

  XFile? get _coverPreview {
    if (draft.coverPhoto != null) return draft.coverPhoto;
    for (final StopDraft s in draft.stops) {
      if (s.photos.isNotEmpty) return s.photos.first;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final XFile? cover = _coverPreview;
    final int? totalTime = draft.totalTimeMinutes;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        AspectRatio(
          aspectRatio: 16 / 9,
          child: cover != null
              ? FutureBuilder<Uint8List>(
                  future: cover.readAsBytes(),
                  builder: (BuildContext context, AsyncSnapshot<Uint8List> snap) {
                    if (!snap.hasData) {
                      return Container(color: AppColors.parchment100);
                    }
                    return Image.memory(snap.data!, fit: BoxFit.cover);
                  },
                )
              : const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[AppColors.moss600, AppColors.pine800],
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                draft.title.isEmpty ? 'Untitled trail' : draft.title,
                style: AppText.screenTitle(),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Text('${draft.stops.length} stops', style: AppText.stat()),
                  const SizedBox(width: 12),
                  Text(
                    totalTime != null ? '~$totalTime min' : '',
                    style: AppText.stat(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "This is a preview — the real roll happens on the "
                          "Roll tab once your trail is published.",
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold500,
                    foregroundColor: AppColors.pine950,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  ),
                  child: Text(
                    '🎲 ROLL FOR FIRST STOP',
                    style: AppText.button(color: AppColors.pine950),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Stops', style: AppText.sectionHeading()),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...draft.stops.asMap().entries.map((MapEntry<int, StopDraft> e) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: _PreviewStopRow(index: e.key, stop: e.value),
          );
        }),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: onEditStops,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Edit'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: onContinueToPublish,
                child: const Text('Publish 🚀'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewStopRow extends StatelessWidget {
  const _PreviewStopRow({required this.index, required this.stop});
  final int index;
  final StopDraft stop;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 12,
              backgroundColor: AppColors.blaze600,
              child: Text('${index + 1}',
                  style: AppText.tag(color: AppColors.parchment50)),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(stop.name, style: AppText.stopName()),
                  if (stop.note.isNotEmpty)
                    Text(stop.note,
                        style: AppText.body(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

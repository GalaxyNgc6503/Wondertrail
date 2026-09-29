import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../trail_draft.dart';

/// Step 5 — Publish. Deliberately splits "publishing succeeded" from
/// "navigate away" into two separate callbacks (`onPublish` vs.
/// `onFinished`), because a success screen reached via a callback that
/// ALSO triggers navigation in that same callback is never seen. The
/// success view below is rendered by this widget's own state and stays
/// on screen until the person taps Done — nothing auto-navigates away
/// the instant publishing succeeds.
class PublishStep extends StatefulWidget {
  const PublishStep({
    super.key,
    required this.draft,
    required this.onPublish,
    required this.onFinished,
  });

  final TrailDraft draft;

  /// Performs the actual Appwrite publish call (uploads + document
  /// creation). Throws on failure.
  final Future<void> Function() onPublish;

  /// Called only when the person dismisses the success view — this is
  /// the "navigate away now" half, kept separate on purpose.
  final VoidCallback onFinished;

  @override
  State<PublishStep> createState() => _PublishStepState();
}

class _PublishStepState extends State<PublishStep> {
  bool _publishing = false;
  bool _published = false;
  String? _error;

  Future<void> _doPublish() async {
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await widget.onPublish();
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _published = true; // notify success — does NOT navigate away
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = "Couldn't publish — check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_published) {
      return _SuccessView(onDone: widget.onFinished);
    }

    final TrailDraft draft = widget.draft;
    final int? totalTime = draft.totalTimeMinutes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SummaryLine(
                  emoji: '📍',
                  text: draft.startingLocation?.label ?? 'No starting location',
                ),
                const SizedBox(height: 10),
                _SummaryLine(emoji: '🛑', text: '${draft.stops.length} stops'),
                const SizedBox(height: 10),
                _SummaryLine(
                  emoji: '⏱️',
                  text: totalTime != null
                      ? '~$totalTime min total'
                      : '${draft.stops.length} stops (no time estimates set)',
                ),
                const SizedBox(height: 10),
                const _SummaryLine(emoji: '🌎', text: 'Public'),
                const SizedBox(height: 10),
                const _SummaryLine(
                  emoji: '🎲',
                  text: 'Cross-trail discovery: On',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (_error != null) ...<Widget>[
          Text(_error!, style: AppText.caption(color: AppColors.blaze700)),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _publishing ? null : _doPublish,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _publishing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.parchment50,
                    ),
                  )
                : const Text('Publish Trail'),
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.emoji, required this.text});
  final String emoji;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppText.body())),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text('Your trail is live!', style: AppText.screenTitle()),
            const SizedBox(height: 8),
            Text('0 travellers yet', style: AppText.body()),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // No sharing package is wired up in this build — honest
                  // stub rather than a fake success state.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Sharing isn't wired up yet.")),
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold500,
                  foregroundColor: AppColors.pine950,
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

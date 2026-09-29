import 'package:flutter/material.dart';

import '../../../models/trail_stop.dart';
import '../../../theme/app_theme.dart';
import '../trail_draft.dart';

/// Step 3 — labeled "Discovery" in the UI, not "Roll Rules": see the
/// product decision in the build spec. Every published trail is open to
/// cross-trail discovery — that's no longer a choice made here, only how
/// wide a radius it reaches. How a Traveller rolls (the circle, the
/// radius) is theirs, on the Roll tab, never here.
class RollRulesStep extends StatelessWidget {
  const RollRulesStep({
    super.key,
    required this.draft,
    required this.onDraftChanged,
  });

  final TrailDraft draft;
  final VoidCallback onDraftChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: <Widget>[
        Text('Discovery', style: AppText.sectionHeading()),
        const SizedBox(height: 4),
        Text(
          'Every published trail is public and open to cross-trail rolls — '
          'a Traveller whose search circle passes near one of your stops '
          'can hop onto your whole trail from there.',
          style: AppText.caption(),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('Nearby radius', style: AppText.sectionHeading()),
            Text('${draft.nearbyRadiusKm.toStringAsFixed(1)} km',
                style: AppText.statStrong()),
          ],
        ),
        Slider(
          value: draft.nearbyRadiusKm.clamp(0.5, 10),
          min: 0.5,
          max: 10,
          divisions: 19,
          activeColor: AppColors.blaze600,
          onChanged: (double v) {
            draft.nearbyRadiusKm = v;
            onDraftChanged();
          },
        ),
        const SizedBox(height: 24),
        Text('Category tags', style: AppText.sectionHeading()),
        const SizedBox(height: 4),
        Text('For filtering and matching.', style: AppText.caption()),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: kCategories.map((String c) {
            final bool selected = draft.categories.contains(c);
            return FilterChip(
              label: Text(c),
              selected: selected,
              labelStyle: AppText.label(
                color: selected ? AppColors.parchment50 : AppColors.ink,
              ),
              onSelected: (bool v) {
                if (v) {
                  draft.categories.add(c);
                } else {
                  draft.categories.remove(c);
                }
                onDraftChanged();
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

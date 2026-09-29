import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "2 rolls left today" / "Unlimited rolls" pill, with an upsell tap target
/// for free users.
class RollQuotaBadge extends StatelessWidget {
  const RollQuotaBadge({super.key, required this.premium, required this.remaining, this.onTap});

  final bool premium;
  final int remaining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = premium ? 'Unlimited rolls' : '$remaining roll${remaining == 1 ? '' : 's'} left today';
    final color = premium ? AppColors.gold500 : (remaining == 0 ? AppColors.blaze600 : AppColors.pine800);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: premium ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(premium ? Icons.workspace_premium : Icons.casino_outlined, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: AppText.body(size: 11.5, weight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// Full-width upsell banner shown when a free user is out of rolls.
class OutOfRollsBanner extends StatelessWidget {
  const OutOfRollsBanner({super.key, required this.onUpgrade});
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.pine950, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.workspace_premium, color: AppColors.gold500),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Out of rolls for today", style: AppText.body(size: 13, weight: FontWeight.w700, color: AppColors.parchment50)),
            const SizedBox(height: 2),
            Text('Go Premium for unlimited rolls and single-stop re-rolls.', style: AppText.body(size: 11.5, color: AppColors.parchment50.withValues(alpha: 0.75))),
          ]),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: onUpgrade,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.pine950,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('Upgrade', style: AppText.body(size: 12.5, weight: FontWeight.w700, color: AppColors.pine950)),
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/destination.dart';
import '../theme/app_theme.dart';
import 'destination_view.dart';

/// A generated trail's stop, as a horizontal card: number, photo, name,
/// category, time, cost — with an optional re-roll action for premium.
class StopCard extends StatelessWidget {
  const StopCard({
    super.key,
    required this.number,
    required this.destination,
    required this.isMust,
    this.onTap,
    this.onReroll,
    this.rerolling = false,
    this.highlight = false,
  });

  final int number;
  final Destination destination;
  final bool isMust;
  final VoidCallback? onTap;
  final VoidCallback? onReroll;
  final bool rerolling;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final badgeColor = isMust ? AppColors.blaze600 : AppColors.pine800;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.parchment50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? AppColors.gold500 : Colors.black.withValues(alpha: 0.06), width: highlight ? 2 : 1),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: DestinationPhoto(destination: destination, width: 72, height: 72),
              ),
              Positioned(
                left: -4,
                top: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: Center(child: Text('$number', style: AppText.mono(size: 11, weight: FontWeight.w700, color: Colors.white))),
                ),
              ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(destination.name, style: AppText.body(size: 14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (isMust)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.push_pin, size: 13, color: AppColors.blaze600),
                    ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  CategoryChip(destination.category),
                  const SizedBox(width: 8),
                  Icon(Icons.schedule, size: 12, color: AppColors.moss600),
                  const SizedBox(width: 3),
                  Text(destination.visitLabel, style: AppText.mono(size: 11, color: AppColors.moss600)),
                ]),
                const SizedBox(height: 4),
                Text(destination.cost, style: AppText.mono(size: 11, color: AppColors.blaze700)),
              ]),
            ),
            if (onReroll != null)
              IconButton(
                tooltip: isMust ? "Must Visit stops can't be re-rolled" : 'Re-roll this stop',
                onPressed: isMust ? null : onReroll,
                icon: rerolling
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.casino_outlined, size: 20, color: isMust ? Colors.black26 : AppColors.pine800),
              ),
          ]),
        ),
      ),
    );
  }
}

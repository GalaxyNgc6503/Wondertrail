import 'package:flutter/material.dart';

import '../models/destination.dart';
import '../services/photo_urls.dart';
import '../theme/app_theme.dart';
import 'map_pins.dart';

/// A destination's photo: the local file (pre-publish), the uploaded photo,
/// or a category-coloured placeholder.
class DestinationPhoto extends StatelessWidget {
  const DestinationPhoto({super.key, required this.destination, this.width, this.height = 160, this.radius = 0});

  final Destination destination;
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(destination.category);
    final placeholder = Container(
      width: width,
      height: height,
      color: style.color.withValues(alpha: 0.18),
      child: Icon(style.icon, size: height.clamp(24, 64) * 0.5, color: style.color),
    );

    final Widget image;
    if (destination.localPhoto != null) {
      image = Image.file(destination.localPhoto!, width: width, height: height, fit: BoxFit.cover);
    } else if (destination.photoFileId != null) {
      image = Image.network(
        PhotoUrls.preview(destination.photoFileId!, width: width == null ? 800 : (width! * 2).round()),
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
      );
    } else {
      image = placeholder;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(this.category, {super.key});
  final String category;

  @override
  Widget build(BuildContext context) {
    final style = categoryStyle(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: style.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(style.icon, size: 12, color: style.color),
        const SizedBox(width: 4),
        Text(category, style: AppText.body(size: 11, weight: FontWeight.w600, color: style.color)),
      ]),
    );
  }
}

/// "45 min" / "RM10–20" pill.
class InfoPill extends StatelessWidget {
  const InfoPill({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: AppColors.moss600),
      const SizedBox(width: 4),
      Flexible(child: Text(label, style: AppText.mono(size: 11.5, color: AppColors.ink), overflow: TextOverflow.ellipsis)),
    ]);
  }
}

/// Who a destination belongs to, in words — mirrors the pin styles.
({String label, Color color}) provenance(Destination d, String userId) {
  if (d.isMine(userId)) return (label: 'Added by you', color: AppColors.gold500);
  if (d.isCommunity) return (label: 'Added by the community', color: AppColors.blaze600);
  return (label: 'Existing destination', color: AppColors.pine800);
}

/// Everything a traveller sees about a destination. Shared by the publish
/// preview, the Build map's detail sheet and the Roll map's peek.
class DestinationDetail extends StatelessWidget {
  const DestinationDetail({super.key, required this.destination, required this.userId, this.photoHeight = 190});

  final Destination destination;
  final String userId;
  final double photoHeight;

  @override
  Widget build(BuildContext context) {
    final d = destination;
    final tag = provenance(d, userId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DestinationPhoto(destination: d, height: photoHeight, width: double.infinity, radius: 16),
        const SizedBox(height: 14),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tag.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tag.color.withValues(alpha: 0.6)),
            ),
            child: Text(tag.label, style: AppText.body(size: 11, weight: FontWeight.w600, color: AppColors.ink)),
          ),
          const SizedBox(width: 8),
          CategoryChip(d.category),
        ]),
        const SizedBox(height: 10),
        Text(d.name, style: AppText.headline(size: 24)),
        const SizedBox(height: 8),
        Row(children: [
          InfoPill(icon: Icons.schedule, label: d.visitLabel),
          const SizedBox(width: 18),
          Expanded(child: InfoPill(icon: Icons.payments_outlined, label: d.cost)),
        ]),
        const SizedBox(height: 14),
        Text(d.description, style: AppText.body(size: 14).copyWith(height: 1.45)),
        if (d.tips != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.parchment100, borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.gold500),
              const SizedBox(width: 8),
              Expanded(child: Text(d.tips!, style: AppText.body(size: 13).copyWith(height: 1.4))),
            ]),
          ),
        ],
      ],
    );
  }
}

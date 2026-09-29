import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';

/// Icon + colour for a destination category.
({IconData icon, Color color}) categoryStyle(String? category) {
  switch (category) {
    case 'Food':
      return (icon: Icons.restaurant, color: const Color(0xFFB8862F));
    case 'View':
      return (icon: Icons.landscape, color: const Color(0xFF3F7D8C));
    case 'Nature':
      return (icon: Icons.park, color: AppColors.moss600);
    case 'Culture':
    default:
      return (icon: Icons.account_balance, color: const Color(0xFF7A5C99));
  }
}

const _pinShadow = [BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2))];

/// Existing (base dataset) destination: a round pine badge.
Marker existingMarker({required LatLng point, required String category, Widget? child, bool dimmed = false}) {
  return Marker(
    point: point,
    width: 34,
    height: 34,
    child: child ?? ExistingPin(category: category, dimmed: dimmed),
  );
}

class ExistingPin extends StatelessWidget {
  const ExistingPin({super.key, required this.category, this.dimmed = false});
  final String category;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.pine800,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: _pinShadow,
        ),
        child: Icon(categoryStyle(category).icon, size: 15, color: AppColors.parchment50),
      ),
    );
  }
}

/// User-added destination: a blaze teardrop. Yours also gets a gold ring and
/// a star so it reads as editable at a glance.
class CommunityPin extends StatelessWidget {
  const CommunityPin({super.key, required this.category, this.isMine = false});
  final String category;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        const Icon(Icons.location_on, size: 46, color: AppColors.blaze600, shadows: [
          Shadow(color: Color(0x50000000), blurRadius: 4, offset: Offset(0, 2)),
        ]),
        Positioned(
          top: 6,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.parchment50,
              shape: BoxShape.circle,
              border: isMine ? Border.all(color: AppColors.gold500, width: 2.5) : null,
            ),
            child: Icon(categoryStyle(category).icon, size: 11, color: AppColors.blaze700),
          ),
        ),
        if (isMine)
          const Positioned(
            top: 0,
            right: 4,
            child: Icon(Icons.star, size: 14, color: AppColors.gold500),
          ),
      ],
    );
  }
}

Marker communityMarker({required LatLng point, required String category, bool isMine = false}) {
  return Marker(
    point: point,
    width: 46,
    height: 46,
    alignment: Alignment.topCenter, // tip of the drop sits on the coordinate
    child: CommunityPin(category: category, isMine: isMine),
  );
}

/// The pin being placed — gold, springs in when it appears.
Marker draftMarker(LatLng point) {
  return Marker(
    point: point,
    width: 52,
    height: 52,
    alignment: Alignment.topCenter,
    child: TweenAnimationBuilder<double>(
      key: ValueKey('${point.latitude},${point.longitude}'),
      tween: Tween(begin: 0.3, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, alignment: Alignment.bottomCenter, child: child),
      child: const Icon(Icons.location_on, size: 52, color: AppColors.gold500, shadows: [
        Shadow(color: Color(0x60000000), blurRadius: 5, offset: Offset(0, 2)),
      ]),
    ),
  );
}

/// Numbered badge for a stop in a route. [must] stops are blaze, rolled
/// stops are pine, so it's obvious which ones the user pinned.
class NumberedPin extends StatelessWidget {
  const NumberedPin({super.key, required this.number, required this.must, this.highlight = false});
  final int number;
  final bool must;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: highlight ? 1.2 : 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: must ? AppColors.blaze600 : AppColors.pine800,
          shape: BoxShape.circle,
          border: Border.all(color: highlight ? AppColors.gold500 : Colors.white, width: 2.5),
          boxShadow: _pinShadow,
        ),
        child: Center(
          child: Text(
            '$number',
            style: AppText.mono(size: 14, weight: FontWeight.w700, color: AppColors.parchment50),
          ),
        ),
      ),
    );
  }
}

/// Faded dot for a destination that's in the area but not in the trail.
class DimDot extends StatelessWidget {
  const DimDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.pine800.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}

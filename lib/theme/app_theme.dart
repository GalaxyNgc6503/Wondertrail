import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for Wondertrail — mirrors the HTML mockup's palette
/// (deep pine app chrome, aged-parchment cards, blaze-orange wayfinding
/// accent, gold reserved for premium/paywall moments only).
class AppColors {
  AppColors._();

  static const pine950 = Color(0xFF16241B);
  static const pine800 = Color(0xFF223327);
  static const parchment100 = Color(0xFFF1E9D2);
  static const parchment50 = Color(0xFFF8F3E4);
  static const ink = Color(0xFF2B2118);
  static const blaze600 = Color(0xFFC1512B);
  static const blaze700 = Color(0xFFA6431F);
  static const gold500 = Color(0xFFD9A441);
  static const moss600 = Color(0xFF5C7259);
}

/// Text styles — Zilla Slab for headlines (trail-signage feel), Work Sans
/// for body/UI, IBM Plex Mono for anything data-like (distances, counts,
/// coordinates), matching the mockup's typography.
class AppText {
  AppText._();

  static TextStyle headline({double size = 20, Color? color}) =>
      GoogleFonts.zillaSlab(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.ink,
      );

  static TextStyle body({double size = 13.5, FontWeight weight = FontWeight.w400, Color? color}) =>
      GoogleFonts.workSans(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
      );

  static TextStyle mono({double size = 11, FontWeight weight = FontWeight.w500, Color? color}) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.moss600,
      );
}

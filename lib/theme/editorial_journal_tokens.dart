import 'package:flutter/material.dart';

/// Visual primitives for the warm paper-and-editorial experience theme.
abstract final class EditorialJournalTokens {
  static const paperTextureAsset = 'assets/textures/editorial_paper.png';
  static const serifFamily = 'Source Han Serif CN';
  static const serifFallback = [
    'Source Han Serif SC',
    'Songti SC',
    'STSong',
    'SimSun',
    'serif',
  ];

  static const colorCanvas = Color(0xFFF5F0E7);
  static const colorCanvasEnd = Color(0xFFFBF7F0);
  static const colorSurface = Color(0xFFFFFDF7);
  static const colorSurfaceMuted = Color(0xFFEFE8DC);
  static const colorToolLayer = Color(0xFFF8F2E8);
  static const colorInk = Color(0xFF22231F);
  static const colorMuted = Color(0xFF625D56);
  static const colorSubtle = Color(0xFF827A70);
  // Ink-like accents keep the paper theme warm without looking fluorescent.
  // Interactive colors remain dark enough to carry small white labels, while
  // the lighter coral is reserved for decoration and large glyphs.
  static const colorAccent = Color(0xFF9F5141);
  static const colorAccentPressed = Color(0xFF7E4035);
  static const colorAccentSoft = Color(0xFFF4E9E3);
  static const colorCoralDecoration = Color(0xFFC77A67);
  static const colorCobalt = Color(0xFF56649D);
  static const colorCobaltSoft = Color(0xFFE5E7F2);
  static const colorButter = Color(0xFFF7E7AD);
  static const colorSky = Color(0xFFDDEAF0);
  static const colorLine = Color(0xFFD7CDBF);
  static const colorControl = Color(0xFF756D64);
  static const colorShadow = Color(0xFF53483D);
}

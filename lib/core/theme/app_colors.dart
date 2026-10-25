import 'package:flutter/material.dart';

/// Design tokens estimated from the reference video (see PROPOSAL.md §2).
abstract final class AppColors {
  static const background = Color(0xFFECEBEF);
  static const surface = Color(0xFFFFFFFF);
  static const sheet = Color(0xFFF6F6F8);
  static const field = Color(0xFFFFFFFF);
  static const iconTile = Color(0xFFF0F0F3);

  static const textPrimary = Color(0xFF151515);
  static const textSecondary = Color(0xFF8A8A8E);
  static const textMuted = Color(0xFFB4B4B8);

  static const accent = Color(0xFF5B3FD6);
  static const dark = Color(0xFF1C1C1E);
  static const darkSoft = Color(0xFF3A3A3C);
  static const badge = Color(0xFFFF3B30);
  static const loader = Color(0xFF3D7BF0);
  static const coin = Color(0xFFF59E0B);

  static const disabled = Color(0xFFE4E4E8);
}

/// Gradients used for the credit cards. The first three match the video.
abstract final class CardPalette {
  static const teal = [Color(0xFF357867), Color(0xFF285E52)];
  static const amber = [Color(0xFFC08A32), Color(0xFFA9752A)];
  static const violet = [Color(0xFF7457F0), Color(0xFF5A3FD8)];
  static const rose = [Color(0xFFD0668A), Color(0xFFB04B70)];
  static const graphite = [Color(0xFF3A3A40), Color(0xFF1F1F23)];
  static const ocean = [Color(0xFF4A7BEA), Color(0xFF2F5FD0)];

  /// Order used when assigning colors to newly added cards.
  static const forNewCards = [graphite, rose, ocean, teal, amber, violet];
}

abstract final class AppRadii {
  static const card = 22.0;
  static const section = 22.0;
  static const field = 14.0;
  static const sheet = 28.0;
}

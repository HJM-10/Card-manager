import 'package:flutter/material.dart';

enum WalletStyle {
  classic(
    'SpendTrail Classic',
    'DMSans',
    'DMSans',
    Color(0xFF5C45CC),
    Color(0xFF262039),
  ),
  cobaltFold(
    'Cobalt Fold',
    'SpaceGrotesk',
    'Inter',
    Color(0xFF235EC1),
    Color(0xFF173767),
  ),
  figCarousel(
    'Fig Carousel',
    'Outfit',
    'DMSans',
    Color(0xFF854666),
    Color(0xFF523349),
  );

  const WalletStyle(
    this.label,
    this.displayFont,
    this.bodyFont,
    this.accent,
    this.dockColor,
  );

  final String label, displayFont, bodyFont;
  final Color accent, dockColor;

  Color tileColor(ColorScheme colors) => switch (this) {
    classic => colors.primaryContainer,
    cobaltFold => Color.alphaBlend(const Color(0x3B92BCFF), colors.surface),
    figCarousel => Color.alphaBlend(const Color(0x3BF1A3CC), colors.surface),
  };
}

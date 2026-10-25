import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/card_utils.dart';

/// Network logos drawn in code (no image assets needed).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.brand,
    this.color = Colors.white,
    this.height = 14,
  });

  final CardBrand brand;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    switch (brand) {
      case CardBrand.visa:
        return Text(
          'VISA',
          style: GoogleFonts.poppins(
            fontSize: height,
            height: 1,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.4,
            color: color,
          ),
        );
      case CardBrand.mastercard:
        final d = height * 1.15;
        return SizedBox(
          width: d * 1.6,
          height: d,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                child: _circle(d, const Color(0xFFEB001B)),
              ),
              Positioned(
                right: 0,
                child: _circle(d, const Color(0xFFF79E1B).withValues(alpha: 0.9)),
              ),
            ],
          ),
        );
      case CardBrand.unknown:
        return const SizedBox.shrink();
    }
  }

  Widget _circle(double d, Color c) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

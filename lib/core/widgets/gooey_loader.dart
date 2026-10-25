import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "Gooey" metaball loader seen in the "Adding your card..." state.
///
/// Blurred circles are drawn, then the alpha channel is thresholded with a
/// color matrix so overlapping blurs fuse into one liquid shape.
class GooeyLoader extends StatefulWidget {
  const GooeyLoader({super.key, this.color = AppColors.loader, this.size = 44});

  final Color color;
  final double size;

  @override
  State<GooeyLoader> createState() => _GooeyLoaderState();
}

class _GooeyLoaderState extends State<GooeyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final sigma = s * 0.16;
    return SizedBox(
      width: s * 2.4,
      height: s * 1.4,
      child: ColorFiltered(
        // alpha' = 18 * alpha - 7 * 255  -> hard edge at ~40% alpha.
        colorFilter: const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          0, 0, 0, 18, -7 * 255,
        ]),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: Size(s * 2.4, s * 1.4),
              painter: _BlobPainter(t: _c.value, color: widget.color, r: s / 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.t, required this.color, required this.r});

  final double t;
  final Color color;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cy = size.height / 2;
    final cx = size.width / 2 - r * 0.3;

    // Main blob breathes slightly.
    final pulse = 1 + 0.06 * math.sin(t * 2 * math.pi);
    canvas.drawCircle(Offset(cx, cy), r * 0.62 * pulse, paint);

    // Satellite blob travels out to the right and is absorbed back.
    final travel = (1 - math.cos(t * 2 * math.pi)) / 2; // 0 -> 1 -> 0
    final sx = cx + r * 0.3 + travel * r * 0.95;
    canvas.drawCircle(Offset(sx, cy), r * (0.42 - 0.08 * travel), paint);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.color != color;
}

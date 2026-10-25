import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../shell/app_shell.dart';

/// Timeline (2.9 s):
///  • cash stack pops in, coins drop one by one into an arc
///  • illustration collapses away, leaving the "Magpie." wordmark centered
///  • purple progress bar fills at the bottom, then fades into Home
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2900),
  );

  late final _cashIn = _curve(0.0, 0.22, Curves.easeOutBack);
  late final _out = _curve(0.52, 0.70, Curves.easeInOutCubic);
  late final _progress = _curve(0.06, 0.96, Curves.easeInOut);
  late final _textIn = _curve(0.10, 0.30, Curves.easeOutCubic);
  late final _coins = List.generate(
    5,
    (i) => _curve(0.10 + i * 0.05, 0.28 + i * 0.05, Curves.easeOutBack),
  );

  static const _coinOffsets = [
    Offset(-52, 22),
    Offset(-26, 8),
    Offset(0, 2),
    Offset(26, 8),
    Offset(52, 22),
  ];

  Animation<double> _curve(double begin, double end, Curve curve) =>
      CurvedAnimation(parent: _c, curve: Interval(begin, end, curve: curve));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final out = _out.value;
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Illustration: collapses its height so the wordmark
                    // glides to the exact center.
                    ClipRect(
                      child: Align(
                        heightFactor: 1 - out,
                        alignment: Alignment.bottomCenter,
                        child: Opacity(
                          opacity: (1 - out * 1.4).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 1 - 0.12 * out,
                            child: _illustration(),
                          ),
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: _textIn.value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - _textIn.value)),
                        child: Column(
                          children: [
                            Text.rich(
                              TextSpan(
                                text: 'Magpie',
                                children: [
                                  TextSpan(
                                    text: '.',
                                    style: AppText.wordmark(AppColors.accent),
                                  ),
                                ],
                              ),
                              style: AppText.wordmark(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Send, spend and track every card — your\n'
                              'whole money life in one calm place.',
                              textAlign: TextAlign.center,
                              style: AppText.tiny().copyWith(height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: Center(child: _progressBar()),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _illustration() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < 5; i++)
                  Positioned(
                    left: 70 + _coinOffsets[i].dx - 4.5,
                    top: _coinOffsets[i].dy - 40 * (1 - _coins[i].value),
                    child: Opacity(
                      opacity: _coins[i].value.clamp(0.0, 1.0),
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.coin,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Opacity(
            opacity: _cashIn.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.8 + 0.2 * _cashIn.value,
              child: Image.asset(
                'assets/images/cash_stack.jpg',
                width: 170,
                height: 170,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar() {
    const width = 64.0;
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.centerLeft,
      child: Container(
        width: width * _progress.value,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

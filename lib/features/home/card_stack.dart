import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/motion.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../add_card/add_card_sheet.dart';

const _frontHeight = 200.0;
const _peek = 40.0;
const _notchWidth = 124.0;
const _notchHeight = 50.0;

/// Wallet-style stack: back cards show only their header strip, the front
/// card shows full details and has a bottom-right notch for the Add Card pill.
class CardStack extends ConsumerWidget {
  const CardStack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    if (cards.isEmpty) {
      return Card(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 40),
          const Text('Your wallet is empty'),
          FilledButton.icon(onPressed: () => showAddCardSheet(context), icon: const Icon(Icons.add), label: const Text('Add Card')),
        ]),
      ));
    }
    // Show at most 3 cards so the stack keeps the reference proportions.
    final visible = cards.length > 3 ? cards.sublist(cards.length - 3) : cards;
    final height = _frontHeight + (visible.length - 1) * _peek;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            AnimatedPositioned(
              key: ValueKey(visible[i].id),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutBack,
              top: i * _peek,
              left: 0,
              right: 0,
              height: _frontHeight,
              child: _EnterFromTop(
                child: Pressable(
                  scale: 0.985,
                  onTap: i == visible.length - 1
                      ? null
                      : () => ref
                          .read(cardsProvider.notifier)
                          .bringToFront(visible[i].id),
                  child: _CardFace(
                    card: visible[i],
                    isFront: i == visible.length - 1,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Pressable(
              onTap: () => showAddCardSheet(context),
              child: Container(
                width: _notchWidth - 10,
                height: _notchHeight - 10,
                decoration: BoxDecoration(
                  color: AppColors.dark,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add,
                          size: 14, color: AppColors.dark),
                    ),
                    const SizedBox(width: 8),
                    Text('Add Card', style: AppText.caption(Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Newly mounted cards (e.g. just added) drop in from above.
class _EnterFromTop extends StatelessWidget {
  const _EnterFromTop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -30 * (1 - t)),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
      ),
      child: child,
    );
  }
}

class _CardFace extends ConsumerWidget {
  const _CardFace({required this.card, required this.isFront});

  final CreditCard card;
  final bool isFront;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final masked = isFront
        ? '•••• •••• •••• ${card.last4}'
        : '•••• •••• ${card.last4}';

    return PhysicalShape(
      clipper: const NotchedCardClipper(),
      clipBehavior: Clip.antiAlias,
      color: card.gradient.last,
      elevation: isFront ? 10 : 4,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: card.gradient,
          ),
        ),
        child: Stack(
          children: [
            // Soft decorative glow circles.
            Positioned(
              right: -40,
              top: -60,
              child: _glow(170),
            ),
            Positioned(
              left: -50,
              bottom: -80,
              child: _glow(190),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        BrandLogo(brand: card.brand, height: 14),
                        const Spacer(),
                        Text(
                          masked,
                          style: AppText.tiny(Colors.white70)
                              .copyWith(letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                  if (isFront) ...[
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Balance',
                                  style: AppText.tiny(Colors.white60)),
                              const SizedBox(height: 2),
                              TweenAnimationBuilder<double>(
                                key: ValueKey(card.id),
                                tween: Tween(begin: 0, end: card.balance),
                                duration: const Duration(milliseconds: 1200),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(ref.watch(moneyProvider)(v),
                                      style: AppText.balance()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Exp. Date',
                                style: AppText.tiny(Colors.white60)),
                            const SizedBox(height: 4),
                            Text(card.expiry,
                                style: AppText.caption(Colors.white)),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text('Name', style: AppText.tiny(Colors.white60)),
                    const SizedBox(height: 2),
                    Text(card.holder, style: AppText.caption(Colors.white)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
      );
}

/// Rounded card with an inverted-corner cut-out in the bottom-right.
class NotchedCardClipper extends CustomClipper<Path> {
  const NotchedCardClipper();

  @override
  Path getClip(Size size) {
    const r = AppRadii.card;
    const nr = 18.0;
    final w = size.width;
    final h = size.height;
    const nw = _notchWidth;
    const nh = _notchHeight;

    return Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      // Right edge down to the notch.
      ..lineTo(w, h - nh - nr)
      ..quadraticBezierTo(w, h - nh, w - nr, h - nh)
      // Across the top of the notch.
      ..lineTo(w - nw + nr, h - nh)
      ..quadraticBezierTo(w - nw, h - nh, w - nw, h - nh + nr)
      // Down the left side of the notch.
      ..lineTo(w - nw, h - nr)
      ..quadraticBezierTo(w - nw, h, w - nw - nr, h)
      // Bottom edge and remaining corners.
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/wallet_style.dart';
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
  const CardStack({super.key, this.style});

  final WalletStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    if (cards.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 40),
              const Text('Your wallet is empty'),
              FilledButton.icon(
                onPressed: () => showAddCardSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Card'),
              ),
            ],
          ),
        ),
      );
    }
    final frontHeight =
        _frontHeight +
        (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 42) * 7;
    final fold = style == WalletStyle.cobaltFold;
    final carousel = style == WalletStyle.figCarousel;
    final conceptHeight = frontHeight - 48;
    if (fold || carousel) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your wallet',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showAddCardSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Card'),
              ),
            ],
          ),
          if (carousel)
            _FigDeck(
              key: ValueKey(cards.map((card) => card.id).join(',')),
              cards: cards.reversed.toList(),
              cardHeight: conceptHeight,
            )
          else
            _stack(context, ref, cards, conceptHeight),
        ],
      );
    }
    return _stack(context, ref, cards, frontHeight);
  }

  Widget _stack(
    BuildContext context,
    WidgetRef ref,
    List<CreditCard> cards,
    double frontHeight,
  ) {
    final fold = style == WalletStyle.cobaltFold;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Keep the stacked designs to three visible cards.
    final visible = cards.length > 3 ? cards.sublist(cards.length - 3) : cards;
    final peek = fold ? 22.0 : _peek;
    final height = frontHeight + (visible.length - 1) * peek;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            AnimatedPositioned(
              key: ValueKey(visible[i].id),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 520),
              curve: fold ? Curves.easeOutCubic : Curves.easeOutBack,
              top: i * peek,
              left: fold ? (visible.length - i - 1) * 8 : 0,
              right: fold ? (visible.length - i - 1) * 8 : 0,
              height: frontHeight,
              child: _EnterFromTop(
                key: fold ? ValueKey(i == visible.length - 1) : null,
                folded: fold,
                child: Pressable(
                  scale: 0.985,
                  onTap: i == visible.length - 1
                      ? null
                      : () => ref
                            .read(cardsProvider.notifier)
                            .bringToFront(visible[i].id),
                  child: fold
                      ? _ConceptCardFace(
                          card: visible[i],
                          style: WalletStyle.cobaltFold,
                          depth: visible.length - i - 1,
                        )
                      : _CardFace(
                          card: visible[i],
                          isFront: i == visible.length - 1,
                        ),
                ),
              ),
            ),
          if (!fold)
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
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
                          child: const Icon(
                            Icons.add,
                            size: 14,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Add Card', style: AppText.caption(Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FigDeck extends StatefulWidget {
  const _FigDeck({super.key, required this.cards, required this.cardHeight});

  final List<CreditCard> cards;
  final double cardHeight;

  @override
  State<_FigDeck> createState() => _FigDeckState();
}

class _FigDeckState extends State<_FigDeck> {
  int current = 0;

  void move(int delta) =>
      setState(() => current = (current + delta) % widget.cards.length);

  @override
  Widget build(BuildContext context) {
    final count = widget.cards.length;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        SizedBox(
          height: widget.cardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: count == 1
                      ? null
                      : (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          if (velocity.abs() >= 70) move(velocity < 0 ? 1 : -1);
                        },
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 560),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, progress) => FadeTransition(
                      opacity: progress,
                      child: AnimatedBuilder(
                        animation: progress,
                        child: child,
                        builder: (context, child) => Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .001)
                            ..rotateY(-.36 * (1 - progress.value)),
                          child: child,
                        ),
                      ),
                    ),
                    child: _ConceptCardFace(
                      key: ValueKey(widget.cards[current].id),
                      card: widget.cards[current],
                      style: WalletStyle.figCarousel,
                    ),
                  ),
                ),
              ),
              if (count > 1)
                SizedBox(
                  width: 36,
                  child: Tooltip(
                    message: 'Next card',
                    child: Pressable(
                      onTap: () => move(1),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 8, 0, 8),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4B45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text('Card ${current + 1} of $count'),
          ),
      ],
    );
  }
}

/// Newly mounted cards (e.g. just added) drop in from above.
class _EnterFromTop extends StatelessWidget {
  const _EnterFromTop({super.key, required this.child, required this.folded});
  final Widget child;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: folded ? 470 : 650),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: folded
            ? Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .001)
                  ..rotateX(-.33 * (1 - t)),
                child: child,
              )
            : Transform.translate(
                offset: Offset(0, -30 * (1 - t)),
                child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
              ),
      ),
      child: child,
    );
  }
}

class _ConceptCardFace extends ConsumerWidget {
  const _ConceptCardFace({
    super.key,
    required this.card,
    required this.style,
    this.depth = 0,
  });

  final CreditCard card;
  final WalletStyle style;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cobalt = style == WalletStyle.cobaltFold;
    final gradient = switch ((cobalt, depth)) {
      (true, 0) => const [Color(0xFF235EC1), Color(0xFF183A86)],
      (true, 1) => const [Color(0xFF50529D), Color(0xFF50529D)],
      (true, _) => const [Color(0xFF316F92), Color(0xFF316F92)],
      (false, _) => const [Color(0xFF854666), Color(0xFF5A2D47)],
    };
    final detail = TextStyle(
      color: Colors.white,
      fontFamily: style.bodyFont,
      fontSize: 11,
    );
    final network = Text(
      card.brand.name.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: detail.copyWith(
        fontFamily: style.displayFont,
        fontWeight: FontWeight.w700,
        letterSpacing: .8,
      ),
    );
    return PhysicalShape(
      clipper: cobalt
          ? const _FoldedCardClipper()
          : const ShapeBorderClipper(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(19)),
              ),
            ),
      color: gradient.last,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (depth == 0)
              Positioned(
                right: -28,
                top: -85,
                child: Transform.rotate(
                  angle: cobalt ? .58 : 0,
                  child: Container(
                    width: 195,
                    height: 195,
                    decoration: BoxDecoration(
                      shape: cobalt ? BoxShape.rectangle : BoxShape.circle,
                      color: Colors.white.withValues(alpha: .13),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(13, depth == 0 ? 12 : 2, 13, 12),
              child: Column(
                mainAxisAlignment: depth == 0
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: network),
                      Text('•••• ${card.last4}', style: detail),
                    ],
                  ),
                  if (depth == 0) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Demo balance · PKR', style: detail),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            ref.watch(moneyProvider)(
                              ref.watch(demoBalanceProvider(card.id)),
                            ),
                            style: AppText.balance().copyWith(
                              fontFamily: style.displayFont,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.holder.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: detail.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(right: cobalt ? 28 : 0),
                          child: Text(card.expiry, style: detail),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
    final balance = isFront ? ref.watch(demoBalanceProvider(card.id)) : 0.0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final expiry = Column(
      crossAxisAlignment: largeText
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text('Exp. Date', style: AppText.tiny(Colors.white70)),
        const SizedBox(height: 4),
        Text(card.expiry, style: AppText.caption(Colors.white)),
      ],
    );

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
            Positioned(right: -40, top: -60, child: _glow(170)),
            Positioned(left: -50, bottom: -80, child: _glow(190)),
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
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              masked,
                              style: AppText.tiny(
                                Colors.white70,
                              ).copyWith(letterSpacing: 0.6),
                            ),
                          ),
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
                              Text(
                                'Demo balance',
                                style: AppText.tiny(Colors.white60),
                              ),
                              const SizedBox(height: 2),
                              TweenAnimationBuilder<double>(
                                key: ValueKey(card.id),
                                tween: Tween(
                                  begin: reduceMotion ? balance : 0,
                                  end: balance,
                                ),
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 1200),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    ref.watch(moneyProvider)(v),
                                    style: AppText.balance(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!largeText) expiry,
                      ],
                    ),
                    if (largeText) ...[const SizedBox(height: 6), expiry],
                    const Spacer(),
                    Text('Name', style: AppText.tiny(Colors.white60)),
                    const SizedBox(height: 2),
                    Text(
                      card.holder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(Colors.white),
                    ),
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

class _FoldedCardClipper extends CustomClipper<Path> {
  const _FoldedCardClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(10, 0)
    ..lineTo(size.width - 10, 0)
    ..quadraticBezierTo(size.width, 0, size.width, 10)
    ..lineTo(size.width, size.height - 36)
    ..lineTo(size.width - 36, size.height)
    ..lineTo(10, size.height)
    ..quadraticBezierTo(0, size.height, 0, size.height - 10)
    ..lineTo(0, 10)
    ..quadraticBezierTo(0, 0, 10, 0)
    ..close();

  @override
  bool shouldReclip(_FoldedCardClipper oldClipper) => false;
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

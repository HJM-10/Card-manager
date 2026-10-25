import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/card_utils.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/gooey_loader.dart';
import '../../core/widgets/motion.dart';
import '../../data/providers.dart';

Future<void> showAddCardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 380),
      reverseDuration: Duration(milliseconds: 260),
    ),
    builder: (_) => const AddCardSheet(),
  );
}

class AddCardSheet extends ConsumerStatefulWidget {
  const AddCardSheet({super.key});

  @override
  ConsumerState<AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends ConsumerState<AddCardSheet> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_number, _expiry, _cvv]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  bool get _valid =>
      isCardNumberValid(_number.text) &&
      isExpiryValid(_expiry.text) &&
      isCvvValid(_cvv.text);

  Future<void> _submit() async {
    if (!_valid || _adding) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _adding = true);
    await ref
        .read(cardsProvider.notifier)
        .addCard(number: _number.text, expiry: _expiry.text);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
        padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + safeBottom),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _adding ? const _AddingState() : _buildForm(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final brand = detectBrand(_number.text);
    return Column(
      key: const ValueKey('form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Text('Add Card', style: AppText.title().copyWith(fontSize: 18)),
        const SizedBox(height: 2),
        Text('Enter your card details.', style: AppText.caption()),
        const SizedBox(height: 18),
        _Label('Card number'),
        _Field(
          controller: _number,
          hint: '0000 0000 0000 0000',
          formatters: [CardNumberFormatter()],
          autofocus: true,
          suffix: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: a, child: child),
            ),
            child: BrandLogo(
              key: ValueKey(brand),
              brand: brand,
              color: AppColors.textPrimary,
              height: 15,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label('Expiry date'),
                  _Field(
                    controller: _expiry,
                    hint: 'MM/YY',
                    formatters: [ExpiryFormatter()],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label('CVV'),
                  _Field(
                    controller: _cvv,
                    hint: '000',
                    obscure: true,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Pressable(
          onTap: _valid ? _submit : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 52,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _valid ? AppColors.dark : AppColors.disabled,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Add Card',
              style: AppText.body(
                _valid ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddingState extends StatelessWidget {
  const _AddingState();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('adding'),
      height: 170,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GooeyLoader(size: 40),
          const SizedBox(height: 14),
          Text('Adding your card...',
              style: AppText.caption(AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: AppText.tiny()),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.formatters,
    this.suffix,
    this.obscure = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final List<TextInputFormatter> formatters;
  final Widget? suffix;
  final bool obscure;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      inputFormatters: formatters,
      style: AppText.body().copyWith(letterSpacing: 0.4),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(AppColors.textMuted),
        filled: true,
        fillColor: AppColors.field,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Align(
                  widthFactor: 1,
                  alignment: Alignment.centerRight,
                  child: suffix,
                ),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

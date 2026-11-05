import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../data/spendtrail_api.dart';

class SpendTrailApp extends ConsumerStatefulWidget {
  const SpendTrailApp({super.key, this.api});
  final SpendTrailApi? api;

  @override
  ConsumerState<SpendTrailApp> createState() => _SpendTrailAppState();
}

class _SpendTrailAppState extends ConsumerState<SpendTrailApp> {
  late final api = widget.api ?? SpendTrailApi();
  Map<String, dynamic>? user;

  ThemeData theme(Brightness brightness) {
    final light = brightness == Brightness.light;
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      scaffoldBackgroundColor: light ? const Color(0xFFFFF7ED) : null,
      colorScheme: ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: const Color(0xFFEB7867),
        primary: light ? const Color(0xFF102735) : null,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpendTrail',
    debugShowCheckedModeBanner: false,
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    themeMode: ref.watch(settingsProvider).themeMode,
    home: user == null
        ? _SignIn(
            api: api,
            onAuthenticated: (value) => setState(() => user = value),
          )
        : _Wallet(
            api: api,
            user: user!,
            onSignedOut: () => setState(() => user = null),
          ),
  );
}

class _AppearanceMenu extends ConsumerStatefulWidget {
  const _AppearanceMenu({this.onDark = false});

  final bool onDark;

  @override
  ConsumerState<_AppearanceMenu> createState() => _AppearanceMenuState();
}

class _AppearanceMenuState extends ConsumerState<_AppearanceMenu> {
  bool saving = false;

  Future<void> select(String appearance) async {
    final settings = ref.read(settingsProvider);
    if (settings.appearance == appearance) return;
    setState(() => saving = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .save(
            name: settings.name,
            currency: settings.currency,
            appearance: appearance,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appearance could not be saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(settingsProvider).appearance;
    return PopupMenuButton<String>(
      tooltip: 'Appearance',
      icon: Icon(
        Icons.brightness_6_outlined,
        color: widget.onDark ? Colors.white : null,
      ),
      enabled: !saving,
      onSelected: select,
      itemBuilder: (_) => [
        for (final (value, label) in [
          ('system', 'System'),
          ('light', 'Light'),
          ('dark', 'Dark'),
        ])
          CheckedPopupMenuItem(
            value: value,
            checked: appearance == value,
            child: Text(label),
          ),
      ],
    );
  }
}

class _SignIn extends StatefulWidget {
  const _SignIn({required this.api, required this.onAuthenticated});
  final SpendTrailApi api;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool registering = false, busy = false;
  bool hidePassword = true;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final user = await widget.api.authenticate(
        email: email.text,
        password: password.text,
        name: registering ? name.text : null,
      );
      password.clear();
      if (mounted) widget.onAuthenticated(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void setRegistering(bool value) {
    setState(() {
      registering = value;
      hidePassword = true;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2269CD),
      brightness: theme.brightness,
    );
    final action = light ? const Color(0xFF2269CD) : const Color(0xFFABCFFF);
    final fieldFill = light
        ? const Color(0xFFF1F2F6)
        : colors.surfaceContainerHighest;
    return Scaffold(
      backgroundColor: const Color(0xFF10131D),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, viewport) {
                final headerHeight = (viewport.maxHeight * .36).clamp(
                  146.0,
                  290.0,
                );
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LoginHeader(
                        registering: registering,
                        minHeight: headerHeight,
                      ),
                      Container(
                        constraints: BoxConstraints(
                          minHeight: (viewport.maxHeight - headerHeight).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: light ? Colors.white : colors.surface,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          child: Theme(
                            data: theme.copyWith(
                              colorScheme: colors,
                              inputDecorationTheme: InputDecorationThemeData(
                                filled: true,
                                fillColor: fieldFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            child: AutofillGroup(
                              child: buildForm(colors, action, fieldFill),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget buildForm(ColorScheme colors, Color action, Color fieldFill) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Log in')),
            ButtonSegment(value: true, label: Text('Sign up')),
          ],
          selected: {registering},
          onSelectionChanged: busy
              ? null
              : (value) => setRegistering(value.single),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: fieldFill,
            selectedBackgroundColor: colors.inverseSurface,
            selectedForegroundColor: colors.onInverseSurface,
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 14),
        if (registering) ...[
          TextFormField(
            controller: name,
            enabled: !busy,
            maxLength: 50,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
              counterText: '',
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter your name.' : null,
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline),
          ),
          validator: (v) =>
              v == null ||
                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
              ? 'Enter a valid email.'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          enabled: !busy,
          obscureText: hidePassword,
          maxLength: 128,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: [
            registering ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: registering ? 'At least 10 characters' : null,
            counterText: '',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: hidePassword ? 'Show password' : 'Hide password',
              onPressed: busy
                  ? null
                  : () => setState(() => hidePassword = !hidePassword),
              icon: Icon(
                hidePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (v) =>
              (v?.length ?? 0) < 10 ? 'Use at least 10 characters.' : null,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : submit,
          style: FilledButton.styleFrom(
            backgroundColor: action,
            foregroundColor: colors.brightness == Brightness.light
                ? Colors.white
                : const Color(0xFF102735),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            busy
                ? 'Please wait…'
                : registering
                ? 'Create account'
                : 'Sign in',
          ),
        ),
        TextButton(
          onPressed: busy ? null : () => setRegistering(!registering),
          style: TextButton.styleFrom(foregroundColor: action),
          child: Text(
            registering
                ? 'Already registered? Sign in'
                : 'New here? Create account',
          ),
        ),
        Text(
          'Fictional card profiles · PKR',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    ),
  );
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.registering, required this.minHeight});

  final bool registering;
  final double minHeight;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(child: CustomPaint(painter: _LoginStreak())),
      const Positioned(top: 0, right: 10, child: _AppearanceMenu(onDark: true)),
      Container(
        constraints: BoxConstraints(minHeight: minHeight),
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(48, 42, 48, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SpendTrail',
              style: TextStyle(
                color: Color(0xFFBBD6FF),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              registering ? 'Create your account.' : 'Welcome back.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontStyle: FontStyle.italic,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your cards. Your spending. One clear picture.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFC2CAD8), fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );
}

class _LoginStreak extends CustomPainter {
  const _LoginStreak();

  @override
  void paint(Canvas canvas, Size size) {
    final streak = Path()
      ..moveTo(size.width * .73, 0)
      ..lineTo(size.width * .60, size.height * .34)
      ..lineTo(size.width * .67, size.height * .39)
      ..lineTo(size.width * .54, size.height * .63)
      ..lineTo(size.width * .57, size.height * .68)
      ..lineTo(size.width * .43, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0x88518DEE)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawPath(streak, paint);
    paint
      ..strokeWidth = 1.25
      ..color = const Color(0x5578AEFF)
      ..maskFilter = null;
    canvas.drawPath(streak, paint);
  }

  @override
  bool shouldRepaint(_LoginStreak oldDelegate) => false;
}

class _Wallet extends StatefulWidget {
  const _Wallet({
    required this.api,
    required this.user,
    required this.onSignedOut,
  });
  final SpendTrailApi api;
  final Map<String, dynamic> user;
  final VoidCallback onSignedOut;
  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> {
  List<Map<String, dynamic>> cards = [];
  bool loading = true, signingOut = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  void handle(ApiException e) {
    if (!mounted) return;
    if (e.unauthorized) {
      widget.onSignedOut();
      return;
    }
    setState(() => error = e.message);
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.cards();
      if (mounted) setState(() => cards = result);
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? card]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CardEditor(
        api: widget.api,
        card: card,
        onExpired: widget.onSignedOut,
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> archive(Map<String, dynamic> card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive card?'),
        content: Text('Remove ${card['label']} from your active cards?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.archiveCard(card['id'] as String);
      if (mounted) await load();
    } on ApiException catch (e) {
      handle(e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SpendTrail'),
      actions: [
        const _AppearanceMenu(),
        TextButton(
          onPressed: signingOut
              ? null
              : () async {
                  setState(() {
                    signingOut = true;
                    error = null;
                  });
                  try {
                    await widget.api.logout();
                    if (mounted) widget.onSignedOut();
                  } on ApiException catch (e) {
                    handle(e);
                  } finally {
                    if (mounted) setState(() => signingOut = false);
                  }
                },
          child: Text(signingOut ? 'Signing out…' : 'Sign out'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Hello ${widget.user['name']}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text('Fictional card profiles · PKR'),
              const SizedBox(height: 24),
              if (loading) const Center(child: CircularProgressIndicator()),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(onPressed: load, child: const Text('Retry')),
              ],
              if (!loading && error == null && cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text(
                    'Your wallet is ready. Add your first fictional card profile.',
                  ),
                ),
              for (final card in cards)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card['label'] as String,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${(card['network'] as String).toUpperCase()} •••• ${card['last4']}',
                        ),
                        Text(
                          'Expires ${card['expiry_month'].toString().padLeft(2, '0')}/${card['expiry_year']}',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: () => edit(card),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: () => archive(card),
                              child: const Text('Archive'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: loading ? null : () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('Add fictional card'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CardEditor extends StatefulWidget {
  const _CardEditor({
    required this.api,
    required this.card,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final Map<String, dynamic>? card;
  final VoidCallback onExpired;
  @override
  State<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<_CardEditor> {
  final form = GlobalKey<FormState>();
  late final label = TextEditingController(
    text: widget.card?['label'] as String?,
  );
  late final last4 = TextEditingController(
    text: widget.card?['last4'] as String?,
  );
  late final expiry = TextEditingController(
    text: widget.card == null
        ? ''
        : '${widget.card!['expiry_month'].toString().padLeft(2, '0')}/${widget.card!['expiry_year']}',
  );
  late String network = widget.card?['network'] as String? ?? 'visa';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    label.dispose();
    last4.dispose();
    expiry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.card == null
                    ? 'Add fictional card'
                    : 'Edit fictional card',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Use a fictional label and last four digits only.'),
              const SizedBox(height: 20),
              TextFormField(
                controller: label,
                enabled: !busy,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Card label'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter a label.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: network,
                decoration: const InputDecoration(labelText: 'Network'),
                items: const [
                  DropdownMenuItem(value: 'visa', child: Text('Visa')),
                  DropdownMenuItem(
                    value: 'mastercard',
                    child: Text('Mastercard'),
                  ),
                ],
                onChanged: busy ? null : (v) => setState(() => network = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: last4,
                enabled: !busy,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Last four digits',
                ),
                validator: (v) => !RegExp(r'^\d{4}$').hasMatch(v ?? '')
                    ? 'Enter four digits.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: expiry,
                enabled: !busy,
                maxLength: 7,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                  labelText: 'Expiry (MM/YYYY)',
                ),
                validator: (v) {
                  final match = RegExp(
                    r'^(0[1-9]|1[0-2])/(20\d{2}|2100)$',
                  ).firstMatch(v ?? '');
                  if (match == null) return 'Use MM/YYYY.';
                  final now = DateTime.now();
                  final year = int.parse(match[2]!),
                      month = int.parse(match[1]!);
                  if (year < now.year ||
                      (year == now.year && month < now.month)) {
                    return 'Use a current or future expiry.';
                  }
                  return null;
                },
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        final parts = expiry.text.split('/');
                        try {
                          await widget.api.saveCard({
                            'label': label.text.trim(),
                            'network': network,
                            'last4': last4.text,
                            'expiry_month': int.parse(parts[0]),
                            'expiry_year': int.parse(parts[1]),
                          }, id: widget.card?['id'] as String?);
                          if (context.mounted) Navigator.pop(context, true);
                        } on ApiException catch (e) {
                          if (!context.mounted) return;
                          if (e.unauthorized) {
                            Navigator.pop(context);
                            widget.onExpired();
                          } else {
                            setState(() => error = e.message);
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text(busy ? 'Saving…' : 'Save card'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

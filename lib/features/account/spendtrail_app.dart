import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/wallet_style.dart';
import '../../data/providers.dart';
import '../../data/settings.dart';
import '../../data/spendtrail_api.dart';
import '../../data/biometric_vault.dart';
import '../../data/transaction_notifications.dart';
import '../shell/app_shell.dart';
import '../splash/splash_screen.dart';
import 'purchases_screen.dart';
import 'biometric_settings.dart';
import 'monthly_budget_screen.dart';
import 'notification_settings.dart';

class SpendTrailApp extends ConsumerStatefulWidget {
  const SpendTrailApp({
    super.key,
    this.api,
    this.biometricVault,
    this.alertGateway,
  });
  final SpendTrailApi? api;
  final BiometricVault? biometricVault;
  final AlertGateway? alertGateway;

  @override
  ConsumerState<SpendTrailApp> createState() => _SpendTrailAppState();
}

class _SpendTrailAppState extends ConsumerState<SpendTrailApp>
    with WidgetsBindingObserver {
  late final api = widget.api ?? SpendTrailApi();
  late final vault = widget.biometricVault ?? AndroidBiometricVault();
  Map<String, dynamic>? user;
  bool showingSplash = true;
  bool signingOut = false;
  final navigatorKey = GlobalKey<NavigatorState>();
  late final TransactionNotifications alerts;
  final List<StreamSubscription<TransactionAlert>> alertSubscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    alerts = TransactionNotifications(
      api: api,
      gateway: widget.alertGateway ?? FirebaseAlertGateway(),
      onExpired: expireAlertSession,
    );
    alertSubscriptions.add(
      alerts.opens.listen((alert) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || user?['id'] != alert.userId) return;
          navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => PurchaseDetailScreen(
                api: api,
                id: alert.transactionId,
                onExpired: expireAlertSession,
              ),
            ),
          );
        });
        WidgetsBinding.instance.scheduleFrame();
      }),
    );
    alertSubscriptions.add(
      alerts.banners.listen((alert) {
        final context = navigatorKey.currentContext;
        if (!mounted ||
            context == null ||
            !context.mounted ||
            user?['id'] != alert.userId) {
          return;
        }
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text('New account activity'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => alerts.open(alert),
            ),
          ),
        );
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && alerts.enabled && user != null) {
      unawaited(alerts.synchronize());
    }
  }

  void expireAlertSession() {
    final context = navigatorKey.currentContext;
    if (mounted && context != null && user != null) finishSignOut(context);
  }

  void authenticated(Map<String, dynamic> value) {
    setState(() => user = value);
    unawaited(alerts.setUser(value['id'] as String?));
  }

  void openAlerts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NotificationHistoryScreen(api: api, onExpired: expireAlertSession),
      ),
    );
  }

  void finishSignOut(BuildContext context) {
    unawaited(alerts.setUser(null));
    Navigator.of(context).popUntil((route) => route.isFirst);
    ref.read(tabProvider.notifier).select(0);
    setState(() => user = null);
  }

  Future<void> signOut(BuildContext context) async {
    if (signingOut) return;
    signingOut = true;
    try {
      await api.logout();
      try {
        await vault.clear();
      } on BiometricException {
        /* Server credential is already revoked. */
      }
      if (context.mounted) finishSignOut(context);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      if (error.unauthorized) {
        try {
          await vault.clear();
        } on BiometricException {
          /* Password fallback stays available. */
        }
        if (!context.mounted) return;
        finishSignOut(context);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      signingOut = false;
    }
  }

  Future<void> lock(BuildContext context) async {
    if (signingOut) return;
    signingOut = true;
    try {
      await api.lock();
    } on ApiException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'App locked. Connect to SpendTrail to sign in again.',
            ),
          ),
        );
      }
    } finally {
      if (context.mounted) finishSignOut(context);
      signingOut = false;
    }
  }

  void openAccountCards(BuildContext context, Map<String, dynamic> account) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _Wallet(
          api: api,
          user: account,
          onSignOut: () => signOut(context),
          onSignedOut: () {
            if (context.mounted) finishSignOut(context);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in alertSubscriptions) {
      unawaited(subscription.cancel());
    }
    alerts.dispose();
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = user;
    final settings = ref.watch(settingsProvider);
    final style = settings.walletStyle;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SpendTrail',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.wallet(style, Brightness.light),
      darkTheme: AppTheme.wallet(style, Brightness.dark),
      themeMode: settings.themeMode,
      home: showingSplash
          ? SplashScreen(
              onComplete: () => setState(() => showingSplash = false),
            )
          : account == null
          ? _SignIn(
              api: api,
              vault: vault,
              walletStyle: style,
              onAuthenticated: authenticated,
            )
          : Builder(
              builder: (context) => AppShell(
                onNotifications: () => openAlerts(context),
                statisticsScreen: MonthlyBudgetScreen(
                  key: ValueKey(account['id'] ?? account['name']),
                  api: api,
                  active: ref.watch(tabProvider) == 2,
                  onExpired: () {
                    if (context.mounted) finishSignOut(context);
                  },
                ),
                walletStyle: style,
                accountName: account['name'] as String,
                appearanceAction: const _AppearanceMenu(),
                securitySettings: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BiometricSettings(
                      api: api,
                      vault: vault,
                      onLock: () => lock(context),
                      onExpired: () {
                        if (context.mounted) finishSignOut(context);
                      },
                    ),
                    NotificationSettings(
                      alerts: alerts,
                      onHistory: () => openAlerts(context),
                    ),
                  ],
                ),
                onAccountCards: () => openAccountCards(context, account),
                onPurchases: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PurchasesScreen(
                      api: api,
                      onExpired: () {
                        if (context.mounted) finishSignOut(context);
                      },
                    ),
                  ),
                ),
                onSignOut: () => signOut(context),
              ),
            ),
    );
  }
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
      await ref.read(settingsProvider.notifier).save(appearance: appearance);
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
  const _SignIn({
    required this.walletStyle,
    required this.api,
    required this.vault,
    required this.onAuthenticated,
  });
  final SpendTrailApi api;
  final BiometricVault vault;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final WalletStyle walletStyle;
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
  BiometricStatus biometric = const BiometricStatus();
  @override
  void initState() {
    super.initState();
    checkBiometric();
  }

  Future<void> checkBiometric() async {
    try {
      final result = await widget.vault.status();
      if (mounted) setState(() => biometric = result);
    } on BiometricException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> fingerprintSignIn() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final token = await widget.vault.unlock(widget.api.baseUrl);
      final account = await widget.api.biometricLogin(token);
      if (mounted) widget.onAuthenticated(account);
    } on BiometricException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on ApiException catch (e) {
      if (e.unauthorized) {
        try {
          await widget.vault.clear();
        } on BiometricException {
          /* Server credential is invalid. */
        }
      }
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) {
        await checkBiometric();
        if (mounted) setState(() => busy = false);
      }
    }
  }

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
      // Password login deliberately forgets any previous saved account.
      await widget.vault.clear();
      password.clear();
      if (mounted) widget.onAuthenticated(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on BiometricException catch (e) {
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
    final colors = theme.colorScheme;
    final action = colors.primary;
    final fieldFill = colors.surfaceContainerHighest;
    return Scaffold(
      backgroundColor: widget.walletStyle.dockColor,
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
                        walletStyle: widget.walletStyle,
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
                          color: colors.surface,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(switch (widget.walletStyle) {
                              WalletStyle.classic => 28,
                              WalletStyle.cobaltFold => 18,
                              WalletStyle.figCarousel => 36,
                            }),
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
            selectedBackgroundColor: colors.primaryContainer,
            selectedForegroundColor: colors.onPrimaryContainer,
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
            foregroundColor: colors.onPrimary,
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
        if (!registering && biometric.saved) ...[
          OutlinedButton.icon(
            onPressed: busy || !biometric.available ? null : fingerprintSignIn,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Sign in with fingerprint'),
          ),
          if (!biometric.available)
            const Text(
              'Fingerprint is unavailable. Sign in with your password.',
            ),
        ],
      ],
    ),
  );
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({
    required this.registering,
    required this.minHeight,
    required this.walletStyle,
  });

  final bool registering;
  final double minHeight;
  final WalletStyle walletStyle;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        constraints: BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(walletStyle.dockColor, Colors.black, .28)!,
              walletStyle.dockColor,
            ],
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SpendTrail',
              style: TextStyle(
                fontFamily: walletStyle.displayFont,
                color: Color.lerp(walletStyle.accent, Colors.white, .72),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                walletStyle.accent.withValues(alpha: .3),
                BlendMode.srcATop,
              ),
              child: Image.asset(
                'assets/images/login_wallet_hero.png',
                height: (minHeight * .46).clamp(64.0, 134.0),
                width: 280,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              registering ? 'Create your account.' : 'Welcome back.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: walletStyle.displayFont,
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your cards. Your spending. One clear picture.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
      const Positioned(top: 0, right: 10, child: _AppearanceMenu(onDark: true)),
    ],
  );
}

class _Wallet extends StatefulWidget {
  const _Wallet({
    required this.api,
    required this.user,
    required this.onSignedOut,
    required this.onSignOut,
  });
  final SpendTrailApi api;
  final Map<String, dynamic> user;
  final VoidCallback onSignedOut;
  final VoidCallback onSignOut;
  @override
  State<_Wallet> createState() => _WalletState();
}

class _WalletState extends State<_Wallet> {
  List<Map<String, dynamic>> cards = [];
  bool loading = true;
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
      title: const Text('Account cards'),
      actions: [
        const _AppearanceMenu(),
        TextButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
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
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PurchasesScreen(
                      api: widget.api,
                      onExpired: widget.onSignedOut,
                    ),
                  ),
                ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Account purchases'),
              ),
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

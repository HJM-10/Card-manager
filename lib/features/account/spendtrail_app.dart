import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/spendtrail_api.dart';

class SpendTrailApp extends StatefulWidget {
  const SpendTrailApp({super.key, this.api});
  final SpendTrailApi? api;

  @override
  State<SpendTrailApp> createState() => _SpendTrailAppState();
}

class _SpendTrailAppState extends State<SpendTrailApp> {
  late final api = widget.api ?? SpendTrailApi();
  Map<String, dynamic>? user;

  @override
  void dispose() {
    if (widget.api == null) api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SpendTrail',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'PlusJakartaSans',
      scaffoldBackgroundColor: const Color(0xFFFFF7ED),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFEB7867),
        primary: const Color(0xFF102735),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: form,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'SpendTrail',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text('Your cards. Your spending. One clear picture.'),
                const SizedBox(height: 28),
                Text(
                  registering ? 'Create your account' : 'Welcome back',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                if (registering) ...[
                  TextFormField(
                    controller: name,
                    enabled: !busy,
                    maxLength: 50,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter your name.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) =>
                      v == null ||
                          !RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(v.trim())
                      ? 'Enter a valid email.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  maxLength: 128,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 10 characters',
                  ),
                  validator: (v) => (v?.length ?? 0) < 10
                      ? 'Use at least 10 characters.'
                      : null,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Text(
                    busy
                        ? 'Please wait…'
                        : registering
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          registering = !registering;
                          error = null;
                        }),
                  child: Text(
                    registering
                        ? 'Already registered? Sign in'
                        : 'New here? Create account',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Semester prototype · Fictional card profiles · PKR\nSign in again after restarting the app.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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

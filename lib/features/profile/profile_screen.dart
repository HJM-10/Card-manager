import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/wallet_style.dart';
import '../../data/settings.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    this.onSignOut,
    this.showWalletDesign = false,
    this.securitySettings,
  });
  final VoidCallback? onSignOut;
  final bool showWalletDesign;
  final Widget? securitySettings;
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: ref.read(settingsProvider).name,
  );
  late String appearance = ref.read(settingsProvider).appearance;
  late WalletStyle walletStyle = ref.read(settingsProvider).walletStyle;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedAppearance = ref.watch(
      settingsProvider.select((s) => s.appearance),
    );
    ref.listen(
      settingsProvider.select((s) => s.appearance),
      (_, next) => setState(() => appearance = next),
    );
    return SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
          children: [
            Text(
              'Profile & settings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: name,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Demo profile name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Enter your name.' : null,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Currency · PKR'),
            ),
            if (widget.showWalletDesign) ...[
              DropdownButtonFormField<WalletStyle>(
                isExpanded: true,
                initialValue: walletStyle,
                decoration: const InputDecoration(labelText: 'Theme'),
                items: [
                  for (final style in WalletStyle.values)
                    DropdownMenuItem(
                      value: style,
                      child: Text(style.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) => setState(() => walletStyle = value!),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey(savedAppearance),
              initialValue: appearance,
              decoration: const InputDecoration(labelText: 'Appearance'),
              items: ['system', 'light', 'dark']
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text('${v[0].toUpperCase()}${v.substring(1)}'),
                    ),
                  )
                  .toList(),
              onChanged: saving ? null : (v) => setState(() => appearance = v!),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(settingsProvider.notifier)
                            .save(
                              name: name.text,
                              appearance: appearance,
                              walletStyle: widget.showWalletDesign
                                  ? walletStyle
                                  : null,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Settings saved')),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Settings could not be saved. Please try again.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save settings'),
            ),
            const SizedBox(height: 24),
            if (widget.securitySettings != null) widget.securitySettings!,
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.info_outline),
              title: Text('SpendTrail demo wallet'),
              subtitle: Text(
                'Local data on this device. Cards and balances are demo records. No bank connection or real payments.',
              ),
            ),
            if (widget.onSignOut != null)
              OutlinedButton(
                onPressed: widget.onSignOut,
                child: const Text('Sign out'),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/settings.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: ref.read(settingsProvider).name);
  late String currency = ref.read(settingsProvider).currency;
  late String appearance = ref.read(settingsProvider).appearance;
  bool saving = false;
  @override
  void dispose() { name.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SafeArea(child: Form(key: form, child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 140), children: [
    Text('Profile & settings', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 20),
    TextFormField(controller: name, maxLength: 50, decoration: const InputDecoration(labelText: 'Your name'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name.' : null),
    DropdownButtonFormField<String>(initialValue: currency, decoration: const InputDecoration(labelText: 'Display currency'), items: currencies.keys.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: saving ? null : (v) => setState(() => currency = v!)),
    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Currency changes the label on all demo amounts. It does not convert values or exchange money.')),
    DropdownButtonFormField<String>(initialValue: appearance, decoration: const InputDecoration(labelText: 'Appearance'), items: ['system', 'light', 'dark'].map((v) => DropdownMenuItem(value: v, child: Text('${v[0].toUpperCase()}${v.substring(1)}'))).toList(), onChanged: saving ? null : (v) => setState(() => appearance = v!)),
    const SizedBox(height: 24),
    FilledButton(onPressed: saving ? null : () async {
      if (!form.currentState!.validate()) return;
      setState(() => saving = true);
      try {
        await ref.read(settingsProvider.notifier).save(name: name.text, currency: currency, appearance: appearance);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
      } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings could not be saved. Please try again.')));
      } finally { if (mounted) setState(() => saving = false); }
    }, child: Text(saving ? 'Saving…' : 'Save settings')),
    const SizedBox(height: 24),
    const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.info_outline), title: Text('Magpie demo wallet'), subtitle: Text('Local data on this device. Cards and balances are demo records. No bank connection or real payments.')),
  ])));
}

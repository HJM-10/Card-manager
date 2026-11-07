import 'package:flutter/material.dart';

import '../../data/biometric_vault.dart';
import '../../data/spendtrail_api.dart';

class BiometricSettings extends StatefulWidget {
  const BiometricSettings({
    super.key,
    required this.api,
    required this.vault,
    required this.onLock,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final BiometricVault vault;
  final VoidCallback onLock, onExpired;
  @override
  State<BiometricSettings> createState() => _BiometricSettingsState();
}

class _BiometricSettingsState extends State<BiometricSettings> {
  BiometricStatus status = const BiometricStatus();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.vault.status();
      if (mounted) setState(() => status = value);
    } on BiometricException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> change(bool enabled) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    var issued = false;
    try {
      if (enabled) {
        final token = await widget.api.enableBiometric();
        issued = true;
        await widget.vault.save(token, widget.api.baseUrl);
      } else {
        await widget.api.disableBiometric();
        await widget.vault.clear();
      }
    } on ApiException catch (e) {
      if (e.unauthorized) {
        widget.onExpired();
      } else if (mounted) {
        setState(() => error = e.message);
      }
    } on BiometricException catch (e) {
      if (issued) {
        // Cancelled/failed enrollment must not leave a usable server credential.
        try {
          await widget.api.disableBiometric();
        } on ApiException {
          /* Expires server-side even if offline. */
        }
        try {
          await widget.vault.clear();
        } on BiometricException {
          /* The server credential has been revoked. */
        }
      }
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) {
        await load();
        if (mounted) setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!status.supported && error == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.fingerprint),
          title: const Text('Fingerprint login'),
          value: status.saved,
          subtitle: Text(
            busy
                ? 'Please wait…'
                : status.saved
                ? 'Enabled on this phone. Valid for up to 30 days.'
                : status.available
                ? 'Use your fingerprint to unlock a saved login.'
                : 'Set up a fingerprint in your phone settings, then reopen the app.',
          ),
          onChanged: busy || (!status.available && !status.saved)
              ? null
              : change,
        ),
        if (status.saved)
          TextButton.icon(
            onPressed: busy ? null : widget.onLock,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Lock app'),
          ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

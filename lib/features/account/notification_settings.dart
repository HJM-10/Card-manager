import 'package:flutter/material.dart';

import '../../data/spendtrail_api.dart';
import '../../data/transaction_notifications.dart';
import 'purchases_screen.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({
    super.key,
    required this.alerts,
    required this.onHistory,
  });
  final TransactionNotifications alerts;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: alerts,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Transaction alerts'),
          subtitle: Text(
            alerts.configured
                ? 'Alerts pause when you lock the app or sign out. Purchases save even when alerts are off.'
                : 'Phone alerts are not connected yet. Purchases still save normally.',
          ),
          value: alerts.enabled,
          onChanged: !alerts.configured || alerts.busy
              ? null
              : (value) => value
                    ? alerts.synchronize(requestPermission: true)
                    : alerts.disable(),
        ),
        if (alerts.busy) const LinearProgressIndicator(),
        if (alerts.error != null) ...[
          Text(
            alerts.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          if (alerts.enabled && !alerts.busy)
            TextButton(
              onPressed: alerts.synchronize,
              child: const Text('Retry alert connection'),
            ),
        ],
        if (alerts.pending != null && !alerts.busy)
          TextButton(
            onPressed: alerts.retryOpen,
            child: const Text('Retry opening alert'),
          ),
        TextButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.notifications_outlined),
          label: const Text('Alert history'),
        ),
      ],
    ),
  );
}

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({
    super.key,
    required this.api,
    required this.onExpired,
  });
  final SpendTrailApi api;
  final VoidCallback onExpired;
  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final records = <Map<String, dynamic>>[];
  bool loading = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      if (reset) records.clear();
    });
    try {
      final page = await widget.api.notifications(
        offset: reset ? 0 : records.length,
      );
      if (mounted) {
        setState(() {
          records.addAll(page);
          more = page.length == 25;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        widget.onExpired();
        return;
      }
      setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String status(Map<String, dynamic> record) {
    if (record['opened_at'] != null) return 'Opened in app';
    if (record['received_at'] != null) return 'Received in app';
    return switch (record['status']) {
      'accepted' =>
        'Accepted by notification service; phone receipt unconfirmed',
      'failed' => 'Delivery could not be confirmed',
      'cancelled' => 'Alert cancelled',
      _ => 'Waiting for delivery',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaction alerts')),
    body: RefreshIndicator(
      onRefresh: () => load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Alerts for this account. Opening an alert checks your access to its transaction.',
          ),
          TextButton.icon(
            onPressed: loading ? null : () => load(reset: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh alerts'),
          ),
          if (records.isEmpty && !loading && error == null)
            const Text(
              'No transaction alerts yet. Enable Transaction alerts in Profile after phone alerts are connected.',
            ),
          for (final record in records)
            Card(
              child: ListTile(
                title: const Text('Account transaction'),
                subtitle: Text(status(record)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  try {
                    await widget.api.observeNotification(
                      record['id'] as String,
                      'opened',
                    );
                  } on ApiException {
                    /* The detail route independently checks access. */
                  }
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PurchaseDetailScreen(
                        api: widget.api,
                        id: record['transaction_id'] as String,
                        onExpired: widget.onExpired,
                      ),
                    ),
                  );
                  if (mounted) await load(reset: true);
                },
              ),
            ),
          if (loading) const Center(child: CircularProgressIndicator()),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: load, child: const Text('Retry')),
          ],
          if (!loading && error == null && more && records.isNotEmpty)
            TextButton(onPressed: load, child: const Text('Load more')),
        ],
      ),
    ),
  );
}

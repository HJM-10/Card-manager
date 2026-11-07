import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/spendtrail_api.dart';

const maxCsvBytes = 256 * 1024;

Future<XFile?> chooseCsvFile() => openFile(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'CSV files',
      extensions: ['csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
      mimeTypes: [
        'text/csv',
        'text/comma-separated-values',
        'application/csv',
        'text/plain',
        'application/vnd.ms-excel',
      ],
    ),
  ],
);

class CsvImportScreen extends StatefulWidget {
  const CsvImportScreen({
    super.key,
    required this.api,
    required this.onExpired,
    this.chooseFile,
  });
  final SpendTrailApi api;
  final VoidCallback onExpired;
  final Future<XFile?> Function()? chooseFile;
  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  List<Map<String, dynamic>> cards = [];
  String? cardId, fileName, contents, error;
  Map<String, dynamic>? preview;
  bool loading = true, busy = false, uncertain = false, stale = false;

  @override
  void initState() {
    super.initState();
    loadCards();
  }

  void handle(ApiException e) {
    if (!mounted) return;
    if (e.unauthorized) {
      widget.onExpired();
      return;
    }
    setState(() => error = e.message);
  }

  Future<void> loadCards() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.cards();
      if (mounted) {
        setState(() {
          cards = result;
          cardId = cards.isEmpty ? null : cards.first['id'] as String;
        });
      }
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> selectFile({bool sample = false}) async {
    if (busy || cardId == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = sample ? null : await (widget.chooseFile ?? chooseCsvFile)();
      if (!mounted || (!sample && file == null)) return;
      setState(() {
        preview = null;
        contents = null;
        fileName = null;
        uncertain = false;
        stale = false;
      });
      final name = sample ? 'spendtrail-sample.csv' : file!.name;
      if (!name.toLowerCase().endsWith('.csv')) {
        throw const FormatException('Choose a .csv file.');
      }
      if (name.length > 120) {
        throw const FormatException(
          'Use a file name no longer than 120 characters.',
        );
      }
      if (!sample && await file!.length() > maxCsvBytes) {
        throw const FormatException(
          'Choose a CSV file no larger than 256 KiB.',
        );
      }
      final text = sample
          ? await rootBundle.loadString('assets/imports/sample_purchases.csv')
          : utf8.decode(await file!.readAsBytes());
      if (utf8.encode(text).length > maxCsvBytes) {
        throw const FormatException(
          'Choose a CSV file no larger than 256 KiB.',
        );
      }
      if (!mounted) return;
      setState(() {
        fileName = name;
        contents = text;
      });
      await requestPreview();
    } on FormatException catch (e) {
      if (mounted) {
        setState(
          () => error = e.message.contains('UTF') || e.message.contains('byte')
              ? 'Save the file as UTF-8 CSV and try again.'
              : e.message,
        );
      }
    } on ApiException catch (e) {
      handle(e);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The file could not be opened. Choose it again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestPreview() async {
    final result = await widget.api.previewCsv(
      cardId: cardId!,
      fileName: fileName!,
      text: contents!,
    );
    if (mounted) {
      setState(() {
        preview = result;
        stale = false;
        uncertain = false;
      });
    }
  }

  Future<void> retryPreview() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      preview = null;
    });
    try {
      await requestPreview();
    } on ApiException catch (e) {
      handle(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm() async {
    if (busy || preview == null) return;
    setState(() {
      busy = true;
      uncertain = true;
      error = null;
    });
    try {
      final result = await widget.api.confirmCsv(
        preview!['id'] as String,
        preview!['preview_token'] as String,
      );
      if (mounted) {
        setState(() {
          preview = result;
          uncertain = false;
        });
      }
    } on ApiException catch (e) {
      if (e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 408) {
        if (mounted) {
          setState(() {
            uncertain = false;
            stale = true;
          });
        }
      }
      handle(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = preview;
    final confirmed = batch?['status'] == 'confirmed';
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import CSV')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Choose one card and preview your purchases before saving.',
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Center(child: CircularProgressIndicator())
                else if (cards.isEmpty) ...[
                  const Text(
                    'Add an account card profile before importing purchases.',
                  ),
                  TextButton(
                    onPressed: loadCards,
                    child: const Text('Reload cards'),
                  ),
                ] else ...[
                  DropdownButtonFormField<String>(
                    initialValue: cardId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Import into card',
                    ),
                    items: [
                      for (final card in cards)
                        DropdownMenuItem(
                          value: card['id'] as String,
                          child: Text(
                            '${card['label']} •••• ${card['last4']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy || uncertain
                        ? null
                        : (value) => setState(() {
                            cardId = value;
                            preview = null;
                            stale = false;
                          }),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: busy || uncertain
                            ? null
                            : () => selectFile(),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Choose CSV file'),
                      ),
                      TextButton(
                        onPressed: busy || uncertain
                            ? null
                            : () => selectFile(sample: true),
                        child: const Text('Try sample CSV'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('UTF-8 · up to 256 KiB · up to 500 purchases'),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('CSV format & example'),
                    children: [
                      const Text(
                        'Columns: reference, merchant, amount, occurred_at, channel, category (optional). Use a stable receipt reference, PKR amounts such as 1250.05, dates with a timezone, and online or pos. Category names must already exist in your account.',
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final text = await rootBundle.loadString(
                            'assets/imports/sample_purchases.csv',
                          );
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sample CSV copied'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy sample CSV'),
                      ),
                    ],
                  ),
                ],
                if (fileName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      fileName!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                if (busy) const Center(child: CircularProgressIndicator()),
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
                if (uncertain && !busy)
                  const Text(
                    'The response was interrupted. Retry confirmation safely using this same preview.',
                  ),
                if (batch == null && contents != null && !busy && !uncertain)
                  TextButton(
                    onPressed: retryPreview,
                    child: const Text('Retry preview'),
                  ),
                if (batch != null) ...[
                  if (confirmed) ...[
                    Text(
                      'Import complete',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '${batch['imported_count']} added · ${batch['duplicate_count']} duplicates skipped',
                    ),
                    Text('Imported total: PKR ${batch['total_amount']}'),
                    FilledButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: const Text('View purchases'),
                    ),
                  ] else ...[
                    Text(
                      '${batch['ready_count']} ready · ${batch['duplicate_count']} duplicates · ${batch['error_count']} errors',
                    ),
                    Text('New purchase total: PKR ${batch['total_amount']}'),
                    const SizedBox(height: 8),
                    if (batch['error_count'] != 0)
                      const Text(
                        'Nothing will be imported until every error is fixed. Correct the file and choose it again.',
                      ),
                    if (stale)
                      TextButton(
                        onPressed: busy ? null : retryPreview,
                        child: const Text('Preview again'),
                      ),
                    FilledButton(
                      onPressed: busy || stale || batch['can_confirm'] != true
                          ? null
                          : confirm,
                      child: Text(
                        uncertain ? 'Retry confirmation' : 'Confirm import',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  for (final item
                      in (batch['rows'] as List).cast<Map<String, dynamic>>())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Row ${item['row']} · ${item['state']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: item['state'] == 'error'
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            Text(item['merchant'] as String? ?? ''),
                            Text(
                              'PKR ${item['amount']} · ${item['category'] == '' || item['category'] == null ? 'Uncategorized' : item['category']}',
                            ),
                            Text(item['message'] as String),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

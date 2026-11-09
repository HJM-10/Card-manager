# PostgreSQL index experiment results

Seed: `20261109`. 11 measured executions per query/phase after 3 warmups.

Times below are PostgreSQL EXPLAIN execution times in milliseconds, excluding planning, client transport and rendering. These are warm-cache measurements; caches were not flushed and background activity was not controlled. Raw JSON plans preserve every measured sample. B-tree/hash medians pool two counterbalanced rounds.

The baseline keeps all application indexes. Only one experimental candidate exists at a time. All constraints and audit/outbox triggers remain enabled. Pending ten-row import previews number one tenth of the transaction count; JSON diagnostics are an experimental workload, not an existing API endpoint.

## 10,000 transactions

Correctness: 10,000 transactions and the same number of audit/outbox rows; PKR 22668085.05 approved spending. 1,000 pending import previews. Every workload returned identical results across its index variants.

| Phase | Query | Samples | Median ms | p95 ms | Hits / reads (median) | Scan / index in first sample |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| baseline | history_month | 11 | 0.2000 | 0.4200 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_year | 11 | 0.2670 | 0.5370 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_all_cards_control | 11 | 0.1270 | 0.1740 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| baseline | reference_hit | 11 | 1.2280 | 2.1840 | 286 / 0 | Seq Scan / spending_transactions |
| baseline | reference_miss | 11 | 1.2280 | 1.4010 | 286 / 0 | Seq Scan / spending_transactions |
| baseline | reference_api_control | 11 | 0.0470 | 0.0820 | 5 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | json_reference | 11 | 2.4300 | 2.9980 | 72 / 0 | Seq Scan / import_batches |
| baseline | json_rare_error | 11 | 2.2000 | 2.7670 | 72 / 0 | Seq Scan / import_batches |
| baseline | json_common_ready_control | 11 | 1.3850 | 3.5810 | 72 / 0 | Seq Scan / import_batches |
| history_btree | history_month | 11 | 0.1570 | 0.4140 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_year | 11 | 0.2280 | 0.5160 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_all_cards_control | 11 | 0.1190 | 0.2160 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| history_after_drop | history_month | 11 | 0.2390 | 0.4080 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_year | 11 | 0.3570 | 0.5710 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_all_cards_control | 11 | 0.1300 | 0.2330 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| reference_btree | reference_hit | 22 | 0.0170 | 0.0330 | 3 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_miss | 22 | 0.0240 | 0.0440 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_api_control | 22 | 0.0510 | 0.0660 | 5 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_hash | reference_hit | 22 | 0.0105 | 0.0270 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_miss | 22 | 0.0090 | 0.0110 | 1 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_api_control | 22 | 0.0375 | 0.0530 | 4 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_after_drop | reference_hit | 11 | 1.2090 | 2.0440 | 286 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_miss | 11 | 1.2110 | 1.7010 | 286 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_api_control | 11 | 0.0440 | 0.1180 | 5 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| json_gin | json_reference | 11 | 0.0210 | 0.0260 | 4 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_rare_error | 11 | 0.0380 | 0.1100 | 13 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_common_ready_control | 11 | 1.3250 | 2.6650 | 75 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_after_drop | json_reference | 11 | 2.2290 | 4.1300 | 72 / 0 | Seq Scan / import_batches |
| json_after_drop | json_rare_error | 11 | 2.3130 | 4.0930 | 72 / 0 | Seq Scan / import_batches |
| json_after_drop | json_common_ready_control | 11 | 0.9770 | 2.5730 | 72 / 0 | Seq Scan / import_batches |

| Candidate phase | Index bytes | Build wall ms |
| --- | ---: | ---: |
| history_btree | 425984 | 15.133 |
| reference_btree_round1 | 606208 | 48.517 |
| reference_hash_round1 | 540672 | 13.811 |
| reference_hash_round2 | 540672 | 12.848 |
| reference_btree_round2 | 606208 | 41.143 |
| json_gin | 622592 | 35.361 |

Environment, data fingerprint and table sizes: `10000/metadata.json`. Existing index definitions/sizes: `10000/baseline.json`. Exact SQL/parameters: `10000/workloads.json`.

## 100,000 transactions

Correctness: 100,000 transactions and the same number of audit/outbox rows; PKR 224933124.15 approved spending. 10,000 pending import previews. Every workload returned identical results across its index variants.

| Phase | Query | Samples | Median ms | p95 ms | Hits / reads (median) | Scan / index in first sample |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| baseline | history_month | 11 | 0.5930 | 0.7390 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| baseline | history_year | 11 | 2.3290 | 3.4120 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_all_cards_control | 11 | 0.1120 | 0.2620 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| baseline | reference_hit | 11 | 13.4960 | 16.4300 | 2858 / 0 | Seq Scan / spending_transactions |
| baseline | reference_miss | 11 | 12.9470 | 13.7540 | 2858 / 0 | Seq Scan / spending_transactions |
| baseline | reference_api_control | 11 | 0.0500 | 0.1090 | 6 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | json_reference | 11 | 23.8020 | 25.3320 | 715 / 0 | Seq Scan / import_batches |
| baseline | json_rare_error | 11 | 22.7200 | 25.5300 | 715 / 0 | Seq Scan / import_batches |
| baseline | json_common_ready_control | 11 | 13.2020 | 15.0040 | 715 / 0 | Seq Scan / import_batches |
| history_btree | history_month | 11 | 0.5690 | 0.8880 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| history_btree | history_year | 11 | 1.9970 | 3.0460 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_all_cards_control | 11 | 0.1330 | 0.3200 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| history_after_drop | history_month | 11 | 0.5890 | 0.9020 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| history_after_drop | history_year | 11 | 2.1360 | 3.1830 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_all_cards_control | 11 | 0.1140 | 0.2340 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| reference_btree | reference_hit | 22 | 0.0335 | 0.0700 | 4 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_miss | 22 | 0.0225 | 0.0480 | 3 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_api_control | 22 | 0.0535 | 0.1210 | 6 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_hash | reference_hit | 22 | 0.0100 | 0.0190 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_miss | 22 | 0.0085 | 0.0180 | 1 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_api_control | 22 | 0.0350 | 0.1110 | 4 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_after_drop | reference_hit | 11 | 12.4440 | 13.9500 | 2858 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_miss | 11 | 13.8820 | 14.5750 | 2858 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_api_control | 11 | 0.0440 | 0.0650 | 6 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| json_gin | json_reference | 11 | 0.0240 | 0.0450 | 5 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_rare_error | 11 | 0.2100 | 0.3890 | 104 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_common_ready_control | 11 | 15.8850 | 18.3250 | 722 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_after_drop | json_reference | 11 | 28.1780 | 30.8600 | 715 / 0 | Seq Scan / import_batches |
| json_after_drop | json_rare_error | 11 | 25.9940 | 28.3030 | 715 / 0 | Seq Scan / import_batches |
| json_after_drop | json_common_ready_control | 11 | 15.2820 | 16.1100 | 715 / 0 | Seq Scan / import_batches |

| Candidate phase | Index bytes | Build wall ms |
| --- | ---: | ---: |
| history_btree | 4087808 | 164.212 |
| reference_btree_round1 | 5931008 | 533.982 |
| reference_hash_round1 | 4210688 | 191.503 |
| reference_hash_round2 | 4210688 | 167.418 |
| reference_btree_round2 | 5931008 | 494.939 |
| json_gin | 6275072 | 450.433 |

Environment, data fingerprint and table sizes: `100000/metadata.json`. Existing index definitions/sizes: `100000/baseline.json`. Exact SQL/parameters: `100000/workloads.json`.

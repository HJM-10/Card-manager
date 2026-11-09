# PostgreSQL index experiment results

Seed: `20261109`. 11 measured executions per query/phase after 3 warmups.

Times below are PostgreSQL EXPLAIN execution times in milliseconds, excluding planning, client transport and rendering. These are warm-cache measurements; caches were not flushed and background activity was not controlled. Raw JSON plans preserve every measured sample. B-tree/hash medians pool two counterbalanced rounds.

The baseline keeps all application indexes. Only one experimental candidate exists at a time. All constraints and audit/outbox triggers remain enabled. Pending ten-row import previews number one tenth of the transaction count; JSON diagnostics are an experimental workload, not an existing API endpoint.

## 10,000 transactions

Correctness: 10,000 transactions and the same number of audit/outbox rows; PKR 22668085.05 approved spending. 1,000 pending import previews. Every workload returned identical results across its index variants.

| Phase | Query | Samples | Median ms | p95 ms | Hits / reads (median) | Scan / index in first sample |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| baseline | history_month | 11 | 0.1230 | 0.1390 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_year | 11 | 0.2020 | 0.4960 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_all_cards_control | 11 | 0.1130 | 0.1800 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| baseline | reference_hit | 11 | 0.9410 | 1.3650 | 286 / 0 | Seq Scan / spending_transactions |
| baseline | reference_miss | 11 | 1.5040 | 5.3570 | 286 / 0 | Seq Scan / spending_transactions |
| baseline | reference_api_control | 11 | 0.0790 | 0.1150 | 5 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | json_reference | 11 | 4.9390 | 6.1270 | 72 / 0 | Seq Scan / import_batches |
| baseline | json_rare_error | 11 | 3.7190 | 7.6150 | 72 / 0 | Seq Scan / import_batches |
| baseline | json_common_ready_control | 11 | 2.9920 | 3.5580 | 72 / 0 | Seq Scan / import_batches |
| history_btree | history_month | 11 | 0.2380 | 0.4270 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_year | 11 | 0.2720 | 0.6660 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_all_cards_control | 11 | 0.1490 | 0.2740 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| history_after_drop | history_month | 11 | 0.2310 | 0.5230 | 31 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_year | 11 | 0.2910 | 0.5500 | 78 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_all_cards_control | 11 | 0.1330 | 0.5430 | 48 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| reference_btree | reference_hit | 22 | 0.0380 | 0.0490 | 3 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_miss | 22 | 0.0350 | 0.0470 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_api_control | 22 | 0.1065 | 0.1680 | 5 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_hash | reference_hit | 22 | 0.0240 | 0.0610 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_miss | 22 | 0.0205 | 0.0450 | 1 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_api_control | 22 | 0.0775 | 0.1500 | 4 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_after_drop | reference_hit | 11 | 2.6360 | 3.0680 | 286 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_miss | 11 | 2.0830 | 3.5530 | 286 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_api_control | 11 | 0.0880 | 0.1180 | 5 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| json_gin | json_reference | 11 | 0.0450 | 0.0620 | 4 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_rare_error | 11 | 0.0800 | 0.1020 | 13 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_common_ready_control | 11 | 2.8830 | 5.2070 | 75 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_after_drop | json_reference | 11 | 5.9600 | 12.5550 | 72 / 0 | Seq Scan / import_batches |
| json_after_drop | json_rare_error | 11 | 3.5370 | 6.7600 | 72 / 0 | Seq Scan / import_batches |
| json_after_drop | json_common_ready_control | 11 | 2.8370 | 4.2400 | 72 / 0 | Seq Scan / import_batches |

| Candidate phase | Index bytes | Build wall ms |
| --- | ---: | ---: |
| history_btree | 425984 | 22.489 |
| reference_btree_round1 | 606208 | 67.396 |
| reference_hash_round1 | 540672 | 35.984 |
| reference_hash_round2 | 540672 | 18.770 |
| reference_btree_round2 | 606208 | 107.087 |
| json_gin | 622592 | 65.673 |

Environment, data fingerprint and table sizes: `10000/metadata.json`. Existing index definitions/sizes: `10000/baseline.json`. Exact SQL/parameters: `10000/workloads.json`.

## 100,000 transactions

Correctness: 100,000 transactions and the same number of audit/outbox rows; PKR 224933124.15 approved spending. 10,000 pending import previews. Every workload returned identical results across its index variants.

| Phase | Query | Samples | Median ms | p95 ms | Hits / reads (median) | Scan / index in first sample |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| baseline | history_month | 11 | 1.0890 | 1.6670 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| baseline | history_year | 11 | 2.9870 | 4.2720 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | history_all_cards_control | 11 | 0.1280 | 0.2380 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| baseline | reference_hit | 11 | 19.6090 | 27.1980 | 2858 / 0 | Seq Scan / spending_transactions |
| baseline | reference_miss | 11 | 21.9170 | 27.0680 | 2858 / 0 | Seq Scan / spending_transactions |
| baseline | reference_api_control | 11 | 0.1090 | 0.3370 | 6 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| baseline | json_reference | 11 | 37.8740 | 58.0120 | 715 / 0 | Seq Scan / import_batches |
| baseline | json_rare_error | 11 | 18.3470 | 36.9370 | 715 / 0 | Seq Scan / import_batches |
| baseline | json_common_ready_control | 11 | 8.9110 | 20.9520 | 715 / 0 | Seq Scan / import_batches |
| history_btree | history_month | 11 | 0.9950 | 1.5010 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| history_btree | history_year | 11 | 2.5560 | 5.1420 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_btree | history_all_cards_control | 11 | 0.1530 | 0.3360 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| history_after_drop | history_month | 11 | 0.6920 | 1.3280 | 105 / 0 | Seq Scan / merchants; Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_history; Bitmap Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / categories |
| history_after_drop | history_year | 11 | 2.2700 | 3.5640 | 843 / 0 | Bitmap Heap Scan / spending_transactions; Bitmap Index Scan / spending_transactions_user_id_card_id_id_key; Seq Scan / merchants; Seq Scan / categories |
| history_after_drop | history_all_cards_control | 11 | 0.1060 | 0.4010 | 47 / 0 | Index Scan / spending_transactions_user_history; Index Scan / merchants_pkey; Seq Scan / categories |
| reference_btree | reference_hit | 22 | 0.0165 | 0.0690 | 4 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_miss | 22 | 0.0280 | 0.0700 | 3 / 0 | Index Scan / benchmark_candidate |
| reference_btree | reference_api_control | 22 | 0.0705 | 0.1350 | 6 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_hash | reference_hit | 22 | 0.0160 | 0.0250 | 2 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_miss | 22 | 0.0150 | 0.0230 | 1 / 0 | Index Scan / benchmark_candidate |
| reference_hash | reference_api_control | 22 | 0.0630 | 0.1640 | 4 / 0 | Index Scan / benchmark_candidate; Seq Scan / merchants; Seq Scan / categories |
| reference_after_drop | reference_hit | 11 | 23.9770 | 26.8790 | 2858 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_miss | 11 | 16.4220 | 20.4720 | 2858 / 0 | Seq Scan / spending_transactions |
| reference_after_drop | reference_api_control | 11 | 0.0340 | 0.0380 | 6 / 0 | Index Scan / spending_transactions_card_id_source_source_reference_key; Seq Scan / merchants; Seq Scan / categories |
| json_gin | json_reference | 11 | 0.0490 | 0.0830 | 5 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_rare_error | 11 | 0.2900 | 0.4300 | 104 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_gin | json_common_ready_control | 11 | 21.7450 | 35.4710 | 722 / 0 | Bitmap Heap Scan / import_batches; Bitmap Index Scan / benchmark_candidate |
| json_after_drop | json_reference | 11 | 24.3320 | 54.2830 | 715 / 0 | Seq Scan / import_batches |
| json_after_drop | json_rare_error | 11 | 37.9390 | 49.5330 | 715 / 0 | Seq Scan / import_batches |
| json_after_drop | json_common_ready_control | 11 | 9.1080 | 20.3010 | 715 / 0 | Seq Scan / import_batches |

| Candidate phase | Index bytes | Build wall ms |
| --- | ---: | ---: |
| history_btree | 4087808 | 220.529 |
| reference_btree_round1 | 5931008 | 541.816 |
| reference_hash_round1 | 4210688 | 218.079 |
| reference_hash_round2 | 4210688 | 316.532 |
| reference_btree_round2 | 5931008 | 764.630 |
| json_gin | 6275072 | 438.668 |

Environment, data fingerprint and table sizes: `100000/metadata.json`. Existing index definitions/sizes: `100000/baseline.json`. Exact SQL/parameters: `100000/workloads.json`.

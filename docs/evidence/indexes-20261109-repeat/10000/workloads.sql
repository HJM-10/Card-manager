-- history_month

    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel,
           t.category_id, t.recorded_category_id, c.name AS category, t.original_purchase_id
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
    LEFT JOIN categories c ON (c.user_id, c.id) = (t.user_id, t.category_id)
 WHERE t.user_id = %s AND t.card_id = %s
        AND t.occurred_at >= %s AND t.occurred_at < %s
        ORDER BY t.occurred_at DESC, t.id DESC LIMIT 25 OFFSET 0;

-- history_year

    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel,
           t.category_id, t.recorded_category_id, c.name AS category, t.original_purchase_id
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
    LEFT JOIN categories c ON (c.user_id, c.id) = (t.user_id, t.category_id)
 WHERE t.user_id = %s AND t.card_id = %s
        AND t.occurred_at >= %s AND t.occurred_at < %s
        ORDER BY t.occurred_at DESC, t.id DESC LIMIT 25 OFFSET 0;

-- history_all_cards_control

    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel,
           t.category_id, t.recorded_category_id, c.name AS category, t.original_purchase_id
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
    LEFT JOIN categories c ON (c.user_id, c.id) = (t.user_id, t.category_id)
 WHERE t.user_id = %s
            ORDER BY t.occurred_at DESC, t.id DESC LIMIT 25 OFFSET 0;

-- reference_hit
SELECT id, card_id, amount FROM spending_transactions WHERE source_reference = %s;

-- reference_miss
SELECT id, card_id, amount FROM spending_transactions WHERE source_reference = %s;

-- reference_api_control

    SELECT t.id, t.card_id, m.name AS merchant, t.amount, t.occurred_at,
           t.source, t.source_reference, t.kind, t.status, t.channel,
           t.category_id, t.recorded_category_id, c.name AS category, t.original_purchase_id
    FROM spending_transactions t
    JOIN merchants m ON (m.user_id, m.id) = (t.user_id, t.merchant_id)
    LEFT JOIN categories c ON (c.user_id, c.id) = (t.user_id, t.category_id)
 WHERE t.user_id = %s AND t.card_id = %s
            AND t.source = %s AND t.source_reference = %s;

-- json_reference
SELECT count(*) AS n FROM import_batches WHERE rows @> %s;

-- json_rare_error
SELECT count(*) AS n FROM import_batches WHERE rows @> %s;

-- json_common_ready_control
SELECT count(*) AS n FROM import_batches WHERE rows @> %s;

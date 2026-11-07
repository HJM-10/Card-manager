CREATE TABLE import_batches (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    card_id UUID NOT NULL,
    file_name TEXT NOT NULL CHECK (length(file_name) BETWEEN 1 AND 120),
    file_hash TEXT NOT NULL CHECK (file_hash ~ '^[0-9a-f]{64}$'),
    preview_token UUID NOT NULL,
    rows JSONB NOT NULL CHECK (jsonb_typeof(rows) = 'array'),
    status TEXT NOT NULL DEFAULT 'preview' CHECK (status IN ('preview', 'confirmed')),
    imported_count INTEGER NOT NULL DEFAULT 0 CHECK (imported_count >= 0),
    duplicate_count INTEGER NOT NULL DEFAULT 0 CHECK (duplicate_count >= 0),
    total_amount NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at TIMESTAMPTZ,
    FOREIGN KEY (user_id, card_id) REFERENCES card_profiles(user_id, id),
    UNIQUE (user_id, card_id, file_hash),
    UNIQUE (user_id, card_id, id)
);

ALTER TABLE spending_transactions
    DROP CONSTRAINT spending_transactions_source_check,
    ADD CONSTRAINT spending_transactions_source_check CHECK (source IN ('manual', 'csv')),
    ADD COLUMN import_batch_id UUID,
    ADD FOREIGN KEY (user_id, card_id, import_batch_id) REFERENCES import_batches(user_id, card_id, id),
    ADD CHECK ((source = 'csv') = (import_batch_id IS NOT NULL));

ALTER TABLE card_profiles ADD UNIQUE (user_id, id);

CREATE TABLE merchants (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
    UNIQUE (user_id, name),
    UNIQUE (user_id, id)
);

CREATE TABLE spending_transactions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    card_id UUID NOT NULL,
    merchant_id UUID NOT NULL,
    amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
    occurred_at TIMESTAMPTZ NOT NULL,
    source TEXT NOT NULL CHECK (source = 'manual'),
    source_reference TEXT NOT NULL CHECK (length(trim(source_reference)) > 0),
    kind TEXT NOT NULL CHECK (kind = 'purchase'),
    status TEXT NOT NULL CHECK (status = 'approved'),
    channel TEXT NOT NULL CHECK (channel IN ('online', 'pos')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, card_id) REFERENCES card_profiles(user_id, id),
    FOREIGN KEY (user_id, merchant_id) REFERENCES merchants(user_id, id),
    UNIQUE (card_id, source, source_reference)
);

CREATE INDEX spending_transactions_user_history
    ON spending_transactions(user_id, occurred_at DESC, id DESC);

CREATE TABLE transaction_audit_events (
    transaction_id UUID PRIMARY KEY REFERENCES spending_transactions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE transaction_outbox (
    transaction_id UUID PRIMARY KEY REFERENCES spending_transactions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE FUNCTION record_transaction_created() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO transaction_audit_events (transaction_id) VALUES (NEW.id);
    INSERT INTO transaction_outbox (transaction_id) VALUES (NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER spending_transaction_created
    AFTER INSERT ON spending_transactions
    FOR EACH ROW EXECUTE FUNCTION record_transaction_created();

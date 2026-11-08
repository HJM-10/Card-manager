ALTER TABLE spending_transactions
    DROP CONSTRAINT spending_transactions_source_check,
    DROP CONSTRAINT spending_transactions_kind_check,
    DROP CONSTRAINT spending_transactions_status_check,
    ADD CHECK (source IN ('manual', 'csv', 'simulation')),
    ADD CHECK (kind IN ('purchase', 'refund')),
    ADD CHECK (status IN ('approved', 'declined')),
    ADD COLUMN original_purchase_id UUID,
    ADD UNIQUE (user_id, card_id, id),
    ADD FOREIGN KEY (user_id, card_id, original_purchase_id)
        REFERENCES spending_transactions(user_id, card_id, id),
    ADD CHECK ((kind = 'refund') = (original_purchase_id IS NOT NULL)),
    ADD CHECK (kind <> 'refund' OR (source = 'simulation' AND status = 'approved')),
    ADD CHECK (source = 'simulation' OR (kind = 'purchase' AND status = 'approved'));

CREATE INDEX spending_transactions_refunds ON spending_transactions(original_purchase_id)
    WHERE original_purchase_id IS NOT NULL;

CREATE FUNCTION enforce_refund_rules() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE original spending_transactions%ROWTYPE;
DECLARE refunded NUMERIC;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF ROW(NEW.id, NEW.user_id, NEW.card_id, NEW.merchant_id, NEW.amount,
               NEW.occurred_at, NEW.source, NEW.source_reference, NEW.kind,
               NEW.status, NEW.channel, NEW.original_purchase_id,
               NEW.recorded_category_id, NEW.import_batch_id)
           IS DISTINCT FROM
           ROW(OLD.id, OLD.user_id, OLD.card_id, OLD.merchant_id, OLD.amount,
               OLD.occurred_at, OLD.source, OLD.source_reference, OLD.kind,
               OLD.status, OLD.channel, OLD.original_purchase_id,
               OLD.recorded_category_id, OLD.import_batch_id) THEN
            RAISE EXCEPTION 'Transaction creation fields are immutable' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;
    IF NEW.kind = 'refund' THEN
        SELECT * INTO original FROM spending_transactions
            WHERE id = NEW.original_purchase_id FOR UPDATE;
        IF NOT FOUND OR original.user_id <> NEW.user_id OR original.card_id <> NEW.card_id
           OR original.merchant_id <> NEW.merchant_id OR original.kind <> 'purchase'
           OR original.status <> 'approved' OR NEW.occurred_at < original.occurred_at
           OR NEW.channel <> original.channel THEN
            RAISE EXCEPTION 'Invalid refund purchase' USING ERRCODE = '23514';
        END IF;
        SELECT COALESCE(sum(amount), 0) INTO refunded FROM spending_transactions
            WHERE original_purchase_id = original.id AND status = 'approved';
        IF refunded + NEW.amount > original.amount THEN
            RAISE EXCEPTION 'Refund exceeds remaining amount' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER spending_transaction_refund_rules BEFORE INSERT OR UPDATE
    ON spending_transactions FOR EACH ROW EXECUTE FUNCTION enforce_refund_rules();

CREATE VIEW transaction_spending AS
    SELECT t.*, CASE WHEN status = 'declined' THEN 0::numeric
                    WHEN kind = 'refund' THEN -amount ELSE amount END AS spending_amount
    FROM spending_transactions t;

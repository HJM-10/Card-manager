CREATE TABLE categories (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 50),
    UNIQUE (user_id, id)
);
CREATE UNIQUE INDEX categories_owner_name ON categories (user_id, lower(name));

INSERT INTO categories (id, user_id, name)
SELECT md5(u.id::text || ':' || defaults.name)::uuid, u.id, defaults.name
FROM users u CROSS JOIN (VALUES ('Groceries'), ('Food'), ('Transport'),
    ('Shopping'), ('Bills'), ('Other')) AS defaults(name);

ALTER TABLE spending_transactions
    ADD COLUMN category_id UUID,
    -- Preserve the creation request independently of later categorization.
    ADD COLUMN recorded_category_id UUID,
    ADD FOREIGN KEY (user_id, category_id) REFERENCES categories(user_id, id),
    ADD FOREIGN KEY (user_id, recorded_category_id) REFERENCES categories(user_id, id);

CREATE FUNCTION check_transaction_category_owner() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.category_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM categories WHERE user_id = NEW.user_id AND id = NEW.category_id
    )) OR (NEW.recorded_category_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM categories WHERE user_id = NEW.user_id AND id = NEW.recorded_category_id
    )) THEN
        RAISE EXCEPTION 'Category must belong to the transaction owner' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER spending_transaction_category_owner
    BEFORE INSERT OR UPDATE OF user_id, category_id, recorded_category_id ON spending_transactions
    FOR EACH ROW EXECUTE FUNCTION check_transaction_category_owner();

CREATE INDEX spending_transactions_category_history
    ON spending_transactions (user_id, category_id, occurred_at DESC, id DESC);

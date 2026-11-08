CREATE TABLE budgets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    category_id UUID NOT NULL,
    month DATE NOT NULL CHECK (EXTRACT(DAY FROM month) = 1 AND month >= DATE '2000-01-01' AND month < DATE '2101-01-01'),
    amount NUMERIC(14,2) NOT NULL CHECK (amount > 0 AND amount <> 'NaN'::numeric),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, category_id) REFERENCES categories(user_id, id),
    UNIQUE (user_id, category_id, month)
);

CREATE VIEW monthly_category_spending AS
    SELECT user_id, card_id, category_id,
           date_trunc('month', occurred_at AT TIME ZONE 'Asia/Karachi')::date AS month,
           sum(spending_amount) AS spent,
           sum(CASE WHEN kind = 'purchase' AND status = 'approved' THEN amount ELSE 0 END) AS purchases,
           sum(CASE WHEN kind = 'refund' AND status = 'approved' THEN amount ELSE 0 END) AS refunds,
           count(*) AS transaction_count
    FROM transaction_spending
    GROUP BY user_id, card_id, category_id, date_trunc('month', occurred_at AT TIME ZONE 'Asia/Karachi')::date;

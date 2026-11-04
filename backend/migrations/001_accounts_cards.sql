CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT NOT NULL UNIQUE CHECK (email = lower(email)),
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 50),
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
    token_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_id ON sessions(user_id);

CREATE TABLE card_profiles (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    label TEXT NOT NULL CHECK (length(trim(label)) BETWEEN 1 AND 50),
    network TEXT NOT NULL CHECK (network IN ('visa', 'mastercard')),
    last4 TEXT NOT NULL CHECK (last4 ~ '^[0-9]{4}$'),
    expiry_month INTEGER NOT NULL CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year INTEGER NOT NULL CHECK (expiry_year BETWEEN 2026 AND 2100),
    archived BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, network, last4)
);
CREATE INDEX card_profiles_user_created ON card_profiles(user_id, created_at);

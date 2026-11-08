CREATE TABLE device_registrations (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    token TEXT NOT NULL CHECK (octet_length(token) BETWEEN 32 AND 2048),
    session_hash TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform = 'android'),
    enabled BOOLEAN NOT NULL DEFAULT true,
    enabled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, id)
);
CREATE UNIQUE INDEX device_active_token ON device_registrations(token) WHERE enabled;
ALTER TABLE spending_transactions ADD UNIQUE (user_id, id);
ALTER TABLE transaction_outbox ADD COLUMN expanded_at TIMESTAMPTZ;

CREATE TABLE notification_events (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    transaction_id UUID NOT NULL,
    device_id UUID NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'accepted', 'failed', 'cancelled')),
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    lease_id UUID,
    lease_until TIMESTAMPTZ,
    last_error TEXT CHECK (length(last_error) <= 100),
    provider_message_id TEXT CHECK (length(provider_message_id) <= 512),
    accepted_at TIMESTAMPTZ,
    received_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (user_id, transaction_id) REFERENCES spending_transactions(user_id, id),
    FOREIGN KEY (user_id, device_id) REFERENCES device_registrations(user_id, id),
    UNIQUE (transaction_id, device_id)
);
CREATE INDEX notification_due ON notification_events(next_attempt_at, created_at)
    WHERE status IN ('pending', 'processing');
CREATE INDEX notification_owner_history ON notification_events(user_id, created_at DESC, id DESC);

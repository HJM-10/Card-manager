CREATE TABLE biometric_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, id)
);
ALTER TABLE sessions ADD COLUMN biometric_session_id UUID;
ALTER TABLE sessions ADD FOREIGN KEY (user_id, biometric_session_id)
    REFERENCES biometric_sessions(user_id, id) ON DELETE CASCADE;
CREATE INDEX sessions_biometric_session ON sessions (biometric_session_id);

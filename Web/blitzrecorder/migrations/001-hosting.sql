CREATE TABLE IF NOT EXISTS hosting_accounts (
  id UUID PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  active_until TIMESTAMPTZ NOT NULL,
  storage_limit BIGINT NOT NULL CHECK (storage_limit > 0),
  stripe_customer_id TEXT UNIQUE,
  stripe_subscription_id TEXT UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hosting_assets (
  id UUID PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  account_id UUID NOT NULL REFERENCES hosting_accounts(id),
  request_key TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('uploading','queued','processing','ready','failed','revoked')),
  content_type TEXT NOT NULL,
  source_key TEXT NOT NULL UNIQUE,
  upload_id TEXT,
  declared_bytes BIGINT NOT NULL CHECK (declared_bytes > 0),
  declared_seconds DOUBLE PRECISION NOT NULL CHECK (declared_seconds > 0),
  reserved_bytes BIGINT NOT NULL CHECK (reserved_bytes > 0),
  stored_bytes BIGINT NOT NULL DEFAULT 0 CHECK (stored_bytes >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  lease_token UUID,
  lease_until TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0,
  stream_prefix TEXT,
  files JSONB NOT NULL DEFAULT '[]'::jsonb,
  duration DOUBLE PRECISION,
  width INTEGER,
  height INTEGER,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (account_id, request_key)
);

CREATE INDEX IF NOT EXISTS hosting_assets_owner ON hosting_assets(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS hosting_assets_jobs ON hosting_assets(status, lease_until, created_at);

CREATE TABLE IF NOT EXISTS hosting_upload_usage (
  asset_id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES hosting_accounts(id) ON DELETE CASCADE,
  seconds DOUBLE PRECISION NOT NULL CHECK (seconds > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS hosting_upload_usage_window
  ON hosting_upload_usage(account_id, created_at);

ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS inactive_since TIMESTAMPTZ;

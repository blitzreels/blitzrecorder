ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS identity_id TEXT UNIQUE;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS checkout_session_id TEXT;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS checkout_url TEXT;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS checkout_expires_at TIMESTAMPTZ;
CREATE TABLE IF NOT EXISTS hosting_connections (
  token_hash TEXT PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES hosting_accounts(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '90 days'
);
CREATE INDEX IF NOT EXISTS hosting_connections_account ON hosting_connections(account_id);

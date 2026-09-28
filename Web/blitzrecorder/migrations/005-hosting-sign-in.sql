CREATE TABLE IF NOT EXISTS hosting_sign_in_codes (
  challenge_hash TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  network_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '10 minutes'
);
CREATE INDEX IF NOT EXISTS hosting_sign_in_email ON hosting_sign_in_codes(email, created_at);
CREATE INDEX IF NOT EXISTS hosting_sign_in_network ON hosting_sign_in_codes(network_hash, created_at);
CREATE INDEX IF NOT EXISTS hosting_accounts_email ON hosting_accounts(lower(email));

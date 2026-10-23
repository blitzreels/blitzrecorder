ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS checked_at TIMESTAMPTZ;
ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS check_attempts INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS hosting_assets_unchecked ON hosting_assets (created_at)
  WHERE status = 'ready' AND checked_at IS NULL AND media_origin IS NULL;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS billing_event_at TIMESTAMPTZ;
ALTER TABLE hosting_accounts ADD COLUMN IF NOT EXISTS checkout_claimed_until TIMESTAMPTZ;

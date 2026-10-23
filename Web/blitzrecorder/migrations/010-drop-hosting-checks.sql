DROP INDEX IF EXISTS hosting_assets_unchecked;
ALTER TABLE hosting_assets DROP COLUMN IF EXISTS checked_at;
ALTER TABLE hosting_assets DROP COLUMN IF EXISTS check_attempts;

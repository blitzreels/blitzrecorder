ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS viewer_details JSONB NOT NULL DEFAULT
  '{"version":1,"summary":null,"language":null,"recordedAt":null,"transcript":[],"chapters":[]}'::jsonb;
ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS frame_rate DOUBLE PRECISION;
ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS video_codec TEXT;

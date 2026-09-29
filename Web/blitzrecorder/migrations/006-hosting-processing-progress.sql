ALTER TABLE hosting_assets ADD COLUMN IF NOT EXISTS processing_progress REAL
  CHECK (processing_progress IS NULL OR processing_progress BETWEEN 0 AND 1);

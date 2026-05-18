-- 海优 (Overseas Excellent Young Scientists) simulated scoring.
-- Reuse analysis_jobs for scoring jobs via a `kind` discriminator.

ALTER TABLE analysis_jobs ADD COLUMN kind TEXT NOT NULL DEFAULT 'analysis';

CREATE INDEX IF NOT EXISTS idx_jobs_scholar_kind
  ON analysis_jobs(scholar_id, kind, status, completed_at DESC);

-- Persisted score reports (latest-wins per scholar; history kept for trend).
CREATE TABLE IF NOT EXISTS haiyou_scores (
  id TEXT PRIMARY KEY,
  scholar_id TEXT NOT NULL,
  total_score REAL NOT NULL,
  funding_prediction TEXT NOT NULL,
  report_json TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (scholar_id) REFERENCES scholars(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_haiyou_scores_scholar
  ON haiyou_scores(scholar_id, created_at DESC);

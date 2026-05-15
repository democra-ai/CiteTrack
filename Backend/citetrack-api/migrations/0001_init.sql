-- CiteTrack analysis schema
-- Stores citing papers enriched with OpenAlex metadata, plus computed analysis results.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS scholars (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  affiliation TEXT,
  h_index INTEGER,
  total_citations INTEGER,
  last_analyzed_at INTEGER
);

CREATE TABLE IF NOT EXISTS publications (
  id TEXT PRIMARY KEY,
  scholar_id TEXT NOT NULL,
  title TEXT NOT NULL,
  year INTEGER,
  citation_count INTEGER,
  cluster_id TEXT,
  openalex_work_id TEXT,
  FOREIGN KEY (scholar_id) REFERENCES scholars(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_publications_scholar ON publications(scholar_id);

CREATE TABLE IF NOT EXISTS citing_papers (
  id TEXT PRIMARY KEY,
  scholar_id TEXT NOT NULL,
  cited_publication_id TEXT,
  title TEXT NOT NULL,
  authors_json TEXT,
  year INTEGER,
  venue TEXT,
  citation_count INTEGER,
  abstract TEXT,
  scholar_url TEXT,
  pdf_url TEXT,
  openalex_work_id TEXT,
  topic_cluster_id INTEGER,
  enrichment_status TEXT DEFAULT 'pending',
  fetched_at INTEGER NOT NULL,
  enriched_at INTEGER,
  FOREIGN KEY (scholar_id) REFERENCES scholars(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_citing_papers_scholar ON citing_papers(scholar_id);
CREATE INDEX IF NOT EXISTS idx_citing_papers_cited ON citing_papers(cited_publication_id);
CREATE INDEX IF NOT EXISTS idx_citing_papers_count ON citing_papers(scholar_id, citation_count DESC);

CREATE TABLE IF NOT EXISTS authors (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  openalex_id TEXT UNIQUE,
  orcid TEXT,
  h_index INTEGER,
  works_count INTEGER,
  cited_by_count INTEGER,
  is_notable INTEGER DEFAULT 0,
  last_enriched_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_authors_name ON authors(display_name);
CREATE INDEX IF NOT EXISTS idx_authors_notable ON authors(is_notable, h_index DESC);

CREATE TABLE IF NOT EXISTS paper_authors (
  citing_paper_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  scholar_id TEXT NOT NULL,
  PRIMARY KEY (citing_paper_id, author_id),
  FOREIGN KEY (citing_paper_id) REFERENCES citing_papers(id) ON DELETE CASCADE,
  FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_paper_authors_scholar ON paper_authors(scholar_id);

CREATE TABLE IF NOT EXISTS institutions (
  id TEXT PRIMARY KEY,
  openalex_id TEXT UNIQUE,
  ror_id TEXT,
  display_name TEXT NOT NULL,
  country_code TEXT,
  type TEXT
);

CREATE INDEX IF NOT EXISTS idx_institutions_name ON institutions(display_name);

CREATE TABLE IF NOT EXISTS author_institutions (
  author_id TEXT NOT NULL,
  institution_id TEXT NOT NULL,
  PRIMARY KEY (author_id, institution_id),
  FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE CASCADE,
  FOREIGN KEY (institution_id) REFERENCES institutions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS topic_clusters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scholar_id TEXT NOT NULL,
  cluster_index INTEGER NOT NULL,
  label TEXT,
  summary TEXT,
  keywords_json TEXT,
  paper_count INTEGER,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (scholar_id) REFERENCES scholars(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_clusters_scholar ON topic_clusters(scholar_id);

CREATE TABLE IF NOT EXISTS analysis_jobs (
  id TEXT PRIMARY KEY,
  scholar_id TEXT NOT NULL,
  status TEXT NOT NULL,
  progress INTEGER DEFAULT 0,
  current_step TEXT,
  error TEXT,
  result_json TEXT,
  citing_papers_count INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  started_at INTEGER,
  completed_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_jobs_scholar ON analysis_jobs(scholar_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON analysis_jobs(status);

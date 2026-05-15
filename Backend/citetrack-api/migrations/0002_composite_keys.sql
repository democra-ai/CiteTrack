-- Move to composite (scholar_id, id) primary keys for per-scholar entity scoping.
-- The same citing paper can cite multiple scholars; the same author can appear
-- under multiple scholars' citation networks.

PRAGMA foreign_keys = OFF;

DROP TABLE IF EXISTS paper_authors;
DROP TABLE IF EXISTS citing_papers;

CREATE TABLE citing_papers (
  scholar_id TEXT NOT NULL,
  id TEXT NOT NULL,
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
  PRIMARY KEY (scholar_id, id),
  FOREIGN KEY (scholar_id) REFERENCES scholars(id) ON DELETE CASCADE
);

CREATE INDEX idx_citing_papers_scholar ON citing_papers(scholar_id);
CREATE INDEX idx_citing_papers_count ON citing_papers(scholar_id, citation_count DESC);

CREATE TABLE paper_authors (
  scholar_id TEXT NOT NULL,
  citing_paper_id TEXT NOT NULL,
  author_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (scholar_id, citing_paper_id, author_id),
  FOREIGN KEY (scholar_id, citing_paper_id) REFERENCES citing_papers(scholar_id, id) ON DELETE CASCADE,
  FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE CASCADE
);

CREATE INDEX idx_paper_authors_scholar ON paper_authors(scholar_id);
CREATE INDEX idx_paper_authors_author ON paper_authors(author_id);

PRAGMA foreign_keys = ON;

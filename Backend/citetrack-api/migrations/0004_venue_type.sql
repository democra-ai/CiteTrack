-- 0004: venue type for the "top venues" analysis metric.
-- citing_papers.venue already exists (often empty for Semantic-Scholar-sourced
-- citations). venue_type holds the OpenAlex primary_location.source.type
-- ("journal" | "conference" | "repository" | ...), populated during enrichment.
ALTER TABLE citing_papers ADD COLUMN venue_type TEXT;

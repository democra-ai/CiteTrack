import type { D1Database } from "@cloudflare/workers-types";
import type { CitingPaperInput, JobRecord, JobStatus } from "../types";

export async function upsertScholar(
  db: D1Database,
  scholar: { id: string; name: string; affiliation?: string | null }
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO scholars (id, name, affiliation)
       VALUES (?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET name=excluded.name, affiliation=excluded.affiliation`
    )
    .bind(scholar.id, scholar.name, scholar.affiliation ?? null)
    .run();
}

export async function upsertPublications(
  db: D1Database,
  scholarId: string,
  pubs: Array<{ id: string; title: string; year: number | null; citationCount: number | null }>
): Promise<void> {
  if (pubs.length === 0) return;
  const stmts = pubs.map((p) =>
    db
      .prepare(
        `INSERT INTO publications (id, scholar_id, title, year, citation_count)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET title=excluded.title, year=excluded.year, citation_count=excluded.citation_count`
      )
      .bind(p.id, scholarId, p.title, p.year, p.citationCount)
  );
  await db.batch(stmts);
}

export async function clearScholarCitingData(db: D1Database, scholarId: string): Promise<void> {
  await db.batch([
    db.prepare(`DELETE FROM paper_authors WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM citing_papers WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM topic_clusters WHERE scholar_id = ?`).bind(scholarId),
  ]);
}

export async function insertCitingPapers(
  db: D1Database,
  scholarId: string,
  papers: CitingPaperInput[]
): Promise<void> {
  if (papers.length === 0) return;
  const now = Date.now();
  for (let i = 0; i < papers.length; i += 50) {
    const slice = papers.slice(i, i + 50);
    const stmts = slice.map((p) =>
      db
        .prepare(
          `INSERT INTO citing_papers
            (scholar_id, id, title, authors_json, year, venue, citation_count,
             abstract, scholar_url, pdf_url, fetched_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(scholar_id, id) DO UPDATE SET
             title=excluded.title,
             authors_json=excluded.authors_json,
             year=excluded.year,
             venue=excluded.venue,
             citation_count=excluded.citation_count,
             abstract=excluded.abstract,
             scholar_url=excluded.scholar_url,
             pdf_url=excluded.pdf_url,
             fetched_at=excluded.fetched_at`
        )
        .bind(
          scholarId,
          p.id,
          p.title,
          JSON.stringify(p.authors ?? []),
          p.year,
          p.venue,
          p.citationCount,
          p.abstract,
          p.scholarUrl,
          p.pdfUrl,
          now
        )
    );
    await db.batch(stmts);
  }
}

export interface DBCitingPaper {
  id: string;
  scholarId: string;
  title: string;
  authors: string[];
  year: number | null;
  venue: string | null;
  citationCount: number | null;
  abstract: string | null;
  scholarUrl: string | null;
  pdfUrl: string | null;
  openalexWorkId: string | null;
  topicClusterId: number | null;
}

export async function getCitingPapers(
  db: D1Database,
  scholarId: string
): Promise<DBCitingPaper[]> {
  const { results } = await db
    .prepare(
      `SELECT id, scholar_id, title, authors_json, year, venue, citation_count,
              abstract, scholar_url, pdf_url, openalex_work_id, topic_cluster_id
       FROM citing_papers WHERE scholar_id = ?`
    )
    .bind(scholarId)
    .all<{
      id: string;
      scholar_id: string;
      title: string;
      authors_json: string | null;
      year: number | null;
      venue: string | null;
      citation_count: number | null;
      abstract: string | null;
      scholar_url: string | null;
      pdf_url: string | null;
      openalex_work_id: string | null;
      topic_cluster_id: number | null;
    }>();
  return (results ?? []).map((r) => ({
    id: r.id,
    scholarId: r.scholar_id,
    title: r.title,
    authors: safeParseArray(r.authors_json),
    year: r.year,
    venue: r.venue,
    citationCount: r.citation_count,
    abstract: r.abstract,
    scholarUrl: r.scholar_url,
    pdfUrl: r.pdf_url,
    openalexWorkId: r.openalex_work_id,
    topicClusterId: r.topic_cluster_id,
  }));
}

function safeParseArray(s: string | null): string[] {
  if (!s) return [];
  try {
    const v = JSON.parse(s);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

export async function setCitingPaperEnrichment(
  db: D1Database,
  scholarId: string,
  paperId: string,
  openalexWorkId: string | null,
  abstract: string | null,
  citationCount: number | null
): Promise<void> {
  await db
    .prepare(
      `UPDATE citing_papers
       SET openalex_work_id = COALESCE(?, openalex_work_id),
           abstract = COALESCE(?, abstract),
           citation_count = COALESCE(?, citation_count),
           enrichment_status = 'enriched',
           enriched_at = ?
       WHERE scholar_id = ? AND id = ?`
    )
    .bind(openalexWorkId, abstract, citationCount, Date.now(), scholarId, paperId)
    .run();
}

export async function setTopicCluster(
  db: D1Database,
  scholarId: string,
  paperId: string,
  clusterDbId: number
): Promise<void> {
  await db
    .prepare(`UPDATE citing_papers SET topic_cluster_id = ? WHERE scholar_id = ? AND id = ?`)
    .bind(clusterDbId, scholarId, paperId)
    .run();
}

export async function upsertAuthor(
  db: D1Database,
  a: {
    id: string;
    displayName: string;
    openalexId?: string | null;
    orcid?: string | null;
    hIndex?: number | null;
    worksCount?: number | null;
    citedByCount?: number | null;
    isNotable?: boolean;
  }
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO authors (id, display_name, openalex_id, orcid, h_index, works_count, cited_by_count, is_notable, last_enriched_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         display_name=excluded.display_name,
         openalex_id=COALESCE(excluded.openalex_id, authors.openalex_id),
         orcid=COALESCE(excluded.orcid, authors.orcid),
         h_index=COALESCE(excluded.h_index, authors.h_index),
         works_count=COALESCE(excluded.works_count, authors.works_count),
         cited_by_count=COALESCE(excluded.cited_by_count, authors.cited_by_count),
         is_notable=excluded.is_notable,
         last_enriched_at=excluded.last_enriched_at`
    )
    .bind(
      a.id,
      a.displayName,
      a.openalexId ?? null,
      a.orcid ?? null,
      a.hIndex ?? null,
      a.worksCount ?? null,
      a.citedByCount ?? null,
      a.isNotable ? 1 : 0,
      Date.now()
    )
    .run();
}

export async function linkPaperAuthor(
  db: D1Database,
  citingPaperId: string,
  authorId: string,
  position: number,
  scholarId: string
): Promise<void> {
  await db
    .prepare(
      `INSERT OR IGNORE INTO paper_authors (scholar_id, citing_paper_id, author_id, position)
       VALUES (?, ?, ?, ?)`
    )
    .bind(scholarId, citingPaperId, authorId, position)
    .run();
}

export async function upsertInstitution(
  db: D1Database,
  inst: {
    id: string;
    displayName: string;
    openalexId?: string | null;
    rorId?: string | null;
    countryCode?: string | null;
    type?: string | null;
  }
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO institutions (id, display_name, openalex_id, ror_id, country_code, type)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         display_name=excluded.display_name,
         openalex_id=COALESCE(excluded.openalex_id, institutions.openalex_id),
         ror_id=COALESCE(excluded.ror_id, institutions.ror_id),
         country_code=COALESCE(excluded.country_code, institutions.country_code),
         type=COALESCE(excluded.type, institutions.type)`
    )
    .bind(
      inst.id,
      inst.displayName,
      inst.openalexId ?? null,
      inst.rorId ?? null,
      inst.countryCode ?? null,
      inst.type ?? null
    )
    .run();
}

export async function linkAuthorInstitution(
  db: D1Database,
  authorId: string,
  institutionId: string
): Promise<void> {
  await db
    .prepare(
      `INSERT OR IGNORE INTO author_institutions (author_id, institution_id) VALUES (?, ?)`
    )
    .bind(authorId, institutionId)
    .run();
}

export async function insertTopicCluster(
  db: D1Database,
  scholarId: string,
  clusterIndex: number,
  label: string,
  summary: string,
  keywords: string[],
  paperCount: number
): Promise<number> {
  const r = await db
    .prepare(
      `INSERT INTO topic_clusters (scholar_id, cluster_index, label, summary, keywords_json, paper_count, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
    .bind(scholarId, clusterIndex, label, summary, JSON.stringify(keywords), paperCount, Date.now())
    .run();
  return Number(r.meta?.last_row_id ?? 0);
}

export async function updateTopicClusterLabel(
  db: D1Database,
  clusterDbId: number,
  label: string
): Promise<void> {
  await db
    .prepare(`UPDATE topic_clusters SET label = ? WHERE id = ?`)
    .bind(label, clusterDbId)
    .run();
}

export async function clearTopicClusters(db: D1Database, scholarId: string): Promise<void> {
  await db.prepare(`DELETE FROM topic_clusters WHERE scholar_id = ?`).bind(scholarId).run();
  await db
    .prepare(`UPDATE citing_papers SET topic_cluster_id = NULL WHERE scholar_id = ?`)
    .bind(scholarId)
    .run();
}

export async function createJob(
  db: D1Database,
  scholarId: string,
  citingPapersCount: number,
  kind: string = "analysis"
): Promise<string> {
  const id = crypto.randomUUID();
  await db
    .prepare(
      `INSERT INTO analysis_jobs (id, scholar_id, status, progress, current_step, citing_papers_count, created_at, kind)
       VALUES (?, ?, 'pending', 0, 'queued', ?, ?, ?)`
    )
    .bind(id, scholarId, citingPapersCount, Date.now(), kind)
    .run();
  return id;
}

export async function updateJob(
  db: D1Database,
  id: string,
  patch: {
    status?: JobStatus;
    progress?: number;
    currentStep?: string;
    error?: string | null;
    resultJson?: string | null;
    started?: boolean;
    completed?: boolean;
  }
): Promise<void> {
  const sets: string[] = [];
  const vals: (string | number | null)[] = [];
  if (patch.status !== undefined) {
    sets.push("status = ?");
    vals.push(patch.status);
  }
  if (patch.progress !== undefined) {
    sets.push("progress = ?");
    vals.push(patch.progress);
  }
  if (patch.currentStep !== undefined) {
    sets.push("current_step = ?");
    vals.push(patch.currentStep);
  }
  if (patch.error !== undefined) {
    sets.push("error = ?");
    vals.push(patch.error);
  }
  if (patch.resultJson !== undefined) {
    sets.push("result_json = ?");
    vals.push(patch.resultJson);
  }
  if (patch.started) {
    sets.push("started_at = ?");
    vals.push(Date.now());
  }
  if (patch.completed) {
    sets.push("completed_at = ?");
    vals.push(Date.now());
  }
  if (sets.length === 0) return;
  vals.push(id);
  await db
    .prepare(`UPDATE analysis_jobs SET ${sets.join(", ")} WHERE id = ?`)
    .bind(...vals)
    .run();
}

export async function getJob(db: D1Database, id: string): Promise<JobRecord | null> {
  const row = await db
    .prepare(
      `SELECT id, scholar_id, status, progress, current_step, error, citing_papers_count,
              created_at, started_at, completed_at
       FROM analysis_jobs WHERE id = ?`
    )
    .bind(id)
    .first<{
      id: string;
      scholar_id: string;
      status: JobStatus;
      progress: number;
      current_step: string | null;
      error: string | null;
      citing_papers_count: number;
      created_at: number;
      started_at: number | null;
      completed_at: number | null;
    }>();
  if (!row) return null;
  return {
    id: row.id,
    scholarId: row.scholar_id,
    status: row.status,
    progress: row.progress,
    currentStep: row.current_step,
    error: row.error,
    citingPapersCount: row.citing_papers_count,
    createdAt: row.created_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
  };
}

export async function getLatestJobResult(
  db: D1Database,
  scholarId: string,
  kind: string = "analysis"
): Promise<{ resultJson: string; completedAt: number } | null> {
  const row = await db
    .prepare(
      `SELECT result_json, completed_at
       FROM analysis_jobs
       WHERE scholar_id = ? AND kind = ? AND status = 'done' AND result_json IS NOT NULL
       ORDER BY completed_at DESC LIMIT 1`
    )
    .bind(scholarId, kind)
    .first<{ result_json: string; completed_at: number }>();
  if (!row) return null;
  return { resultJson: row.result_json, completedAt: row.completed_at };
}

/** Fetch + parse the latest completed analysis result (the `.result` payload). */
export async function getLatestAnalysisResult(
  db: D1Database,
  scholarId: string
): Promise<unknown | null> {
  const latest = await getLatestJobResult(db, scholarId, "analysis");
  if (!latest) return null;
  try {
    const parsed = JSON.parse(latest.resultJson) as { result?: unknown };
    return parsed.result ?? null;
  } catch {
    return null;
  }
}

export async function saveHaiyouScore(
  db: D1Database,
  scholarId: string,
  totalScore: number,
  fundingPrediction: string,
  reportJson: string
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO haiyou_scores (id, scholar_id, total_score, funding_prediction, report_json, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`
    )
    .bind(crypto.randomUUID(), scholarId, totalScore, fundingPrediction, reportJson, Date.now())
    .run();
}

/** Wipe everything for a scholar: citing papers, links, clusters, jobs, scores. */
export async function deleteScholarAnalysis(db: D1Database, scholarId: string): Promise<void> {
  await db.batch([
    db.prepare(`DELETE FROM paper_authors WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM citing_papers WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM topic_clusters WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM publications WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM haiyou_scores WHERE scholar_id = ?`).bind(scholarId),
    db.prepare(`DELETE FROM analysis_jobs WHERE scholar_id = ?`).bind(scholarId),
  ]);
}

/**
 * Like deleteScholarAnalysis, but also removes every per-publication scoped
 * partition ("<scholarId>~pub~<pubId>") created by the per-paper analysis flow.
 * Deleting just the base id would otherwise orphan those rows.
 */
export async function deleteScholarAnalysisDeep(db: D1Database, scholarId: string): Promise<void> {
  const like = `${scholarId}~pub~%`;
  const tables = [
    "paper_authors",
    "citing_papers",
    "topic_clusters",
    "publications",
    "haiyou_scores",
    "analysis_jobs",
  ];
  await db.batch(
    tables.map((t) =>
      db.prepare(`DELETE FROM ${t} WHERE scholar_id = ? OR scholar_id LIKE ?`).bind(scholarId, like)
    )
  );
}

/** Mark a job cancelled so the running orchestrator can bail at the next checkpoint. */
export async function cancelJob(db: D1Database, jobId: string): Promise<boolean> {
  const r = await db
    .prepare(
      `UPDATE analysis_jobs SET status='cancelled', current_step='cancelled', completed_at=?
       WHERE id = ? AND status IN ('pending','running')`
    )
    .bind(Date.now(), jobId)
    .run();
  return Number(r.meta?.changes ?? 0) > 0;
}

/** Cheap check used between pipeline steps to honour a cancel request. */
export async function isJobCancelled(db: D1Database, jobId: string): Promise<boolean> {
  const row = await db
    .prepare(`SELECT status FROM analysis_jobs WHERE id = ?`)
    .bind(jobId)
    .first<{ status: string }>();
  return row?.status === "cancelled";
}

export async function getLatestHaiyouScore(
  db: D1Database,
  scholarId: string
): Promise<{ reportJson: string; createdAt: number } | null> {
  const row = await db
    .prepare(
      `SELECT report_json, created_at FROM haiyou_scores
       WHERE scholar_id = ? ORDER BY created_at DESC LIMIT 1`
    )
    .bind(scholarId)
    .first<{ report_json: string; created_at: number }>();
  if (!row) return null;
  return { reportJson: row.report_json, createdAt: row.created_at };
}

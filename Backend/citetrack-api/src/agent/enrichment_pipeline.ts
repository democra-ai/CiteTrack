import type { D1Database, KVNamespace } from "@cloudflare/workers-types";
import {
  getCitingPapers,
  linkAuthorInstitution,
  linkPaperAuthor,
  setCitingPaperEnrichment,
  upsertAuthor,
  upsertInstitution,
} from "../db/queries";
import {
  decodeAbstract,
  OpenAlexClient,
  type OpenAlexAuthor,
  type OpenAlexWork,
} from "../enrichment/openalex";
import type { EnrichedCitingPaperInput } from "../types";

const NOTABLE_H_INDEX = 30;

function normalizeAuthorKey(name: string, openalexId?: string | null): string {
  if (openalexId) return openalexId.replace(/^https?:\/\/openalex\.org\//, "");
  return "name:" + name.trim().toLowerCase().replace(/\s+/g, "_");
}

function normalizeInstKey(displayName: string, openalexId?: string | null): string {
  if (openalexId) return openalexId.replace(/^https?:\/\/openalex\.org\//, "");
  return "name:" + displayName.trim().toLowerCase().replace(/\s+/g, "_");
}

async function persistClientEnrichment(
  db: D1Database,
  scholarId: string,
  enriched: EnrichedCitingPaperInput[],
  onProgress?: (msg: string, pct: number) => Promise<void>
): Promise<{ enrichedCount: number; authorCount: number; institutionCount: number }> {
  await onProgress?.(`Storing ${enriched.length} client-enriched papers`, 20);

  const seenAuthorKeys = new Set<string>();
  const seenInstKeys = new Set<string>();
  const stmts: D1PreparedStatement[] = [];
  const nowTs = Date.now();

  const paperEnrichSQL = `UPDATE citing_papers
       SET openalex_work_id = COALESCE(?, openalex_work_id),
           abstract = COALESCE(?, abstract),
           citation_count = COALESCE(?, citation_count),
           enrichment_status = 'enriched',
           enriched_at = ?
       WHERE scholar_id = ? AND id = ?`;
  const authorSQL = `INSERT INTO authors (id, display_name, openalex_id, orcid, h_index, works_count, cited_by_count, is_notable, last_enriched_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         display_name=excluded.display_name,
         openalex_id=COALESCE(excluded.openalex_id, authors.openalex_id),
         orcid=COALESCE(excluded.orcid, authors.orcid),
         h_index=COALESCE(excluded.h_index, authors.h_index),
         works_count=COALESCE(excluded.works_count, authors.works_count),
         cited_by_count=COALESCE(excluded.cited_by_count, authors.cited_by_count),
         is_notable=excluded.is_notable,
         last_enriched_at=excluded.last_enriched_at`;
  const linkPaperAuthorSQL = `INSERT OR IGNORE INTO paper_authors (scholar_id, citing_paper_id, author_id, position) VALUES (?, ?, ?, ?)`;
  const instSQL = `INSERT INTO institutions (id, display_name, openalex_id, ror_id, country_code, type)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         display_name=excluded.display_name,
         openalex_id=COALESCE(excluded.openalex_id, institutions.openalex_id),
         ror_id=COALESCE(excluded.ror_id, institutions.ror_id),
         country_code=COALESCE(excluded.country_code, institutions.country_code),
         type=COALESCE(excluded.type, institutions.type)`;
  const linkAuthorInstSQL = `INSERT OR IGNORE INTO author_institutions (author_id, institution_id) VALUES (?, ?)`;

  // Build all statements once, then run them in batches. The previous version awaited
  // every INSERT/UPDATE one at a time — thousands of sequential D1 round-trips that
  // dominated the job time and made large analyses time out. db.batch() ships a whole
  // chunk per round-trip. Statement order keeps author/institution rows before the
  // link rows that reference them, so FK constraints hold across chunks.
  for (const e of enriched) {
    stmts.push(
      db.prepare(paperEnrichSQL).bind(
        e.openalexWorkId ?? null,
        e.abstract ?? null,
        typeof e.citationCount === "number" ? e.citationCount : null,
        nowTs,
        scholarId,
        e.id
      )
    );

    for (let pos = 0; pos < (e.authors ?? []).length; pos++) {
      const a = e.authors[pos];
      const aKey = normalizeAuthorKey(a.displayName, a.openalexId);
      if (!seenAuthorKeys.has(aKey)) {
        seenAuthorKeys.add(aKey);
        stmts.push(
          db.prepare(authorSQL).bind(
            aKey,
            a.displayName,
            a.openalexId ?? null,
            a.orcid ?? null,
            typeof a.hIndex === "number" ? a.hIndex : null,
            typeof a.worksCount === "number" ? a.worksCount : null,
            typeof a.citedByCount === "number" ? a.citedByCount : null,
            (a.hIndex ?? 0) >= NOTABLE_H_INDEX ? 1 : 0,
            nowTs
          )
        );
      }
      stmts.push(db.prepare(linkPaperAuthorSQL).bind(scholarId, e.id, aKey, pos));

      for (const inst of a.institutions ?? []) {
        if (!inst.displayName) continue;
        const iKey = normalizeInstKey(inst.displayName, inst.openalexId);
        if (!seenInstKeys.has(iKey)) {
          seenInstKeys.add(iKey);
          stmts.push(
            db.prepare(instSQL).bind(
              iKey,
              inst.displayName,
              inst.openalexId ?? null,
              inst.rorId ?? null,
              inst.countryCode ?? null,
              inst.type ?? null
            )
          );
        }
        stmts.push(db.prepare(linkAuthorInstSQL).bind(aKey, iKey));
      }
    }
  }

  const CHUNK = 50;
  for (let i = 0; i < stmts.length; i += CHUNK) {
    try {
      await db.batch(stmts.slice(i, i + CHUNK));
    } catch (err) {
      console.error("[enrich:client] batch failed", err instanceof Error ? err.message : String(err));
    }
    const done = Math.min(i + CHUNK, stmts.length);
    await onProgress?.(
      `Storing… ${done}/${stmts.length}`,
      20 + Math.floor((done / Math.max(stmts.length, 1)) * 40)
    );
  }

  await onProgress?.(`Stored ${enriched.length} enriched papers`, 60);

  return {
    enrichedCount: enriched.length,
    authorCount: seenAuthorKeys.size,
    institutionCount: seenInstKeys.size,
  };
}

export async function runEnrichment(
  db: D1Database,
  scholarId: string,
  mailto: string,
  cache: KVNamespace | null,
  clientEnriched: EnrichedCitingPaperInput[] | null,
  onProgress?: (msg: string, pct: number) => Promise<void>
): Promise<{ enrichedCount: number; authorCount: number; institutionCount: number }> {
  // Fast path: if the iOS client pre-fetched OpenAlex from the user's own IP
  // (which is NOT shared with thousands of CF customers), skip the server-side
  // OpenAlex calls entirely and just persist what the client provided.
  if (clientEnriched && clientEnriched.length > 0) {
    return await persistClientEnrichment(db, scholarId, clientEnriched, onProgress);
  }

  const oa = new OpenAlexClient(mailto, cache);

  const papers = await getCitingPapers(db, scholarId);
  await onProgress?.(`OpenAlex: matching ${papers.length} papers`, 15);

  const inputs = papers
    .filter((p) => p.title && p.title.trim().length > 4)
    .map((p) => ({ id: p.id, title: p.title, year: p.year }));

  const worksMap = await oa.batchSearchWorks(inputs, 6);

  await onProgress?.(`OpenAlex: enriching paper metadata`, 30);

  const seenAuthorKeys = new Set<string>();
  const seenInstKeys = new Set<string>();
  const authorRefs: Array<{
    key: string;
    openalexId?: string;
    name: string;
    affiliationHint?: string;
    citingPaperId: string;
    position: number;
    institutionKeys: string[];
  }> = [];

  for (const p of papers) {
    const w: OpenAlexWork | undefined = worksMap.get(p.id);
    if (!w) continue;
    try {
      const abstract = decodeAbstract(w.abstract_inverted_index) ?? p.abstract;
      await setCitingPaperEnrichment(
        db,
        scholarId,
        p.id,
        w.id ?? null,
        abstract ?? null,
        typeof w.cited_by_count === "number" ? w.cited_by_count : null
      );
    } catch (e) {
      console.error("[enrich] setCitingPaperEnrichment failed for", p.id, e instanceof Error ? e.message : String(e));
      continue;
    }

    for (let pos = 0; pos < (w.authorships ?? []).length; pos++) {
      const ship = w.authorships[pos];
      if (!ship || !ship.author) continue;
      const aName = ship.author.display_name || "Unknown";
      const aKey = normalizeAuthorKey(aName, ship.author.id);

      const instKeys: string[] = [];
      for (const inst of ship.institutions ?? []) {
        if (!inst || !inst.display_name) continue;
        const iKey = normalizeInstKey(inst.display_name, inst.id);
        if (!seenInstKeys.has(iKey)) {
          seenInstKeys.add(iKey);
          try {
            await upsertInstitution(db, {
              id: iKey,
              displayName: inst.display_name,
              openalexId: inst.id ?? null,
              rorId: inst.ror ?? null,
              countryCode: inst.country_code ?? null,
              type: inst.type ?? null,
            });
          } catch (e) {
            console.error("[enrich] upsertInstitution failed for", iKey, JSON.stringify(inst), e instanceof Error ? e.message : String(e));
          }
        }
        instKeys.push(iKey);
      }

      if (!seenAuthorKeys.has(aKey)) {
        seenAuthorKeys.add(aKey);
        authorRefs.push({
          key: aKey,
          openalexId: ship.author.id,
          name: aName,
          affiliationHint: ship.institutions?.[0]?.display_name,
          citingPaperId: p.id,
          position: pos,
          institutionKeys: instKeys,
        });
      }

      try {
        await upsertAuthor(db, {
          id: aKey,
          displayName: aName,
          openalexId: ship.author.id ?? null,
          orcid: ship.author.orcid ?? null,
        });
        await linkPaperAuthor(db, p.id, aKey, pos, scholarId);
        for (const iKey of instKeys) {
          await linkAuthorInstitution(db, aKey, iKey);
        }
      } catch (e) {
        console.error("[enrich] author/link failed for", aKey, JSON.stringify(ship.author), e instanceof Error ? e.message : String(e));
      }
    }
  }

  await onProgress?.(`OpenAlex: fetching ${authorRefs.length} authors' h-index`, 55);

  const authorDetailRefs = authorRefs.map((a) => ({
    key: a.key,
    openalexId: a.openalexId,
    name: a.name,
    affiliationHint: a.affiliationHint,
  }));
  const authorMap = await oa.batchFetchAuthors(authorDetailRefs, 6);

  for (const [key, a] of authorMap.entries()) {
    const oaA = a as OpenAlexAuthor;
    const hIndex = oaA.summary_stats?.h_index ?? null;
    try {
      await upsertAuthor(db, {
        id: key,
        displayName: oaA.display_name ?? "Unknown",
        openalexId: oaA.id ?? null,
        orcid: oaA.orcid ?? null,
        hIndex,
        worksCount: typeof oaA.works_count === "number" ? oaA.works_count : null,
        citedByCount: typeof oaA.cited_by_count === "number" ? oaA.cited_by_count : null,
        isNotable: (hIndex ?? 0) >= NOTABLE_H_INDEX,
      });
    } catch (e) {
      console.error("[enrich] upsertAuthor(detail) failed for", key, e instanceof Error ? e.message : String(e));
    }

    for (const inst of oaA.last_known_institutions ?? []) {
      if (!inst || !inst.display_name) continue;
      const iKey = normalizeInstKey(inst.display_name, inst.id);
      if (!seenInstKeys.has(iKey)) {
        seenInstKeys.add(iKey);
        try {
          await upsertInstitution(db, {
            id: iKey,
            displayName: inst.display_name,
            openalexId: inst.id ?? null,
            rorId: inst.ror ?? null,
            countryCode: inst.country_code ?? null,
            type: inst.type ?? null,
          });
        } catch (e) {
          console.error("[enrich] upsertInstitution(detail) failed", JSON.stringify(inst), e instanceof Error ? e.message : String(e));
        }
      }
      try {
        await linkAuthorInstitution(db, key, iKey);
      } catch (e) {
        console.error("[enrich] linkAuthorInstitution(detail) failed", e instanceof Error ? e.message : String(e));
      }
    }
  }

  return {
    enrichedCount: worksMap.size,
    authorCount: seenAuthorKeys.size,
    institutionCount: seenInstKeys.size,
  };
}

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

  for (const e of enriched) {
    try {
      await setCitingPaperEnrichment(
        db,
        scholarId,
        e.id,
        e.openalexWorkId ?? null,
        e.abstract ?? null,
        typeof e.citationCount === "number" ? e.citationCount : null
      );
    } catch (err) {
      console.error("[enrich:client] setCitingPaperEnrichment failed", e.id, err instanceof Error ? err.message : String(err));
      continue;
    }

    for (let pos = 0; pos < (e.authors ?? []).length; pos++) {
      const a = e.authors[pos];
      const aKey = normalizeAuthorKey(a.displayName, a.openalexId);

      try {
        await upsertAuthor(db, {
          id: aKey,
          displayName: a.displayName,
          openalexId: a.openalexId ?? null,
          orcid: a.orcid ?? null,
          hIndex: typeof a.hIndex === "number" ? a.hIndex : null,
          worksCount: typeof a.worksCount === "number" ? a.worksCount : null,
          citedByCount: typeof a.citedByCount === "number" ? a.citedByCount : null,
          isNotable: (a.hIndex ?? 0) >= NOTABLE_H_INDEX,
        });
        seenAuthorKeys.add(aKey);
        await linkPaperAuthor(db, e.id, aKey, pos, scholarId);
      } catch (err) {
        console.error("[enrich:client] upsertAuthor/linkPaperAuthor failed", aKey, err instanceof Error ? err.message : String(err));
        continue;
      }

      for (const inst of a.institutions ?? []) {
        if (!inst.displayName) continue;
        const iKey = normalizeInstKey(inst.displayName, inst.openalexId);
        try {
          if (!seenInstKeys.has(iKey)) {
            seenInstKeys.add(iKey);
            await upsertInstitution(db, {
              id: iKey,
              displayName: inst.displayName,
              openalexId: inst.openalexId ?? null,
              rorId: inst.rorId ?? null,
              countryCode: inst.countryCode ?? null,
              type: inst.type ?? null,
            });
          }
          await linkAuthorInstitution(db, aKey, iKey);
        } catch (err) {
          console.error("[enrich:client] institution upsert/link failed", iKey, err instanceof Error ? err.message : String(err));
        }
      }
    }
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

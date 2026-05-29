import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { D1Database } from "@cloudflare/workers-types";
import type { TopVenue } from "../../types";
import { isNotableVenue, venueKey } from "../notable_venues";

function parseAuthors(json: string | null): string[] {
  if (!json) return [];
  try {
    const v = JSON.parse(json);
    return Array.isArray(v) ? v.map((x) => String(x)).filter(Boolean) : [];
  } catch {
    return [];
  }
}

export function makeExtractTopVenuesTool(db: D1Database, scholarId: string) {
  return tool(
    async ({ topN }: { topN: number }): Promise<TopVenue[]> => {
      const limit = Math.max(1, Math.min(50, topN));
      // Pull every citing paper that has a venue, then keep only the ones whose
      // venue is in the curated notable-venue library (Nature/Science/Cell, IEEE
      // Transactions, top conferences, …). Group by venue and attach the citing
      // papers so the iOS card can drill down into "which papers in this venue
      // cited me".
      const { results } = await db
        .prepare(
          `SELECT id, title, authors_json, year, venue, venue_type, citation_count, scholar_url
           FROM citing_papers
           WHERE scholar_id = ? AND venue IS NOT NULL AND TRIM(venue) <> ''`
        )
        .bind(scholarId)
        .all<{
          id: string;
          title: string;
          authors_json: string | null;
          year: number | null;
          venue: string;
          venue_type: string | null;
          citation_count: number | null;
          scholar_url: string | null;
        }>();

      interface Group {
        name: string;
        type: string | null;
        paperCount: number;
        totalCitations: number;
        papers: TopVenue["papers"];
      }
      const byVenue = new Map<string, Group>();

      for (const r of results ?? []) {
        if (!isNotableVenue(r.venue)) continue;
        const key = venueKey(r.venue);
        let g = byVenue.get(key);
        if (!g) {
          g = { name: r.venue, type: r.venue_type, paperCount: 0, totalCitations: 0, papers: [] };
          byVenue.set(key, g);
        }
        g.paperCount += 1;
        g.totalCitations += r.citation_count ?? 0;
        if (g.papers.length < 25) {
          g.papers.push({
            id: r.id,
            title: r.title,
            authors: parseAuthors(r.authors_json),
            year: r.year,
            scholarUrl: r.scholar_url,
          });
        }
      }

      return Array.from(byVenue.values())
        .sort((a, b) => b.paperCount - a.paperCount || b.totalCitations - a.totalCitations)
        .slice(0, limit)
        .map((g) => ({
          name: g.name,
          type: g.type,
          paperCount: g.paperCount,
          totalCitations: g.totalCitations,
          papers: g.papers,
        }));
    },
    {
      name: "extract_top_venues",
      description:
        "Among the citing papers, keep only those published in NOTABLE venues (curated list of prestigious journals + top conferences), grouped by venue with the citing papers attached. Returns the notable venues that cited this scholar, most-citing first.",
      schema: z.object({
        topN: z
          .number()
          .int()
          .min(1)
          .max(50)
          .default(20)
          .describe("How many notable venues to return"),
      }),
    }
  );
}

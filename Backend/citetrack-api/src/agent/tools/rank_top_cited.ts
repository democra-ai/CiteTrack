import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { D1Database } from "@cloudflare/workers-types";
import type { TopCitedPaper } from "../../types";

export function makeRankTopCitedTool(db: D1Database, scholarId: string) {
  return tool(
    async ({ topN }: { topN: number }): Promise<TopCitedPaper[]> => {
      const limit = Math.max(1, Math.min(50, topN));
      const { results } = await db
        .prepare(
          `SELECT id, title, authors_json, year, venue, citation_count, scholar_url
           FROM citing_papers
           WHERE scholar_id = ? AND citation_count IS NOT NULL
           ORDER BY citation_count DESC, year DESC
           LIMIT ?`
        )
        .bind(scholarId, limit)
        .all<{
          id: string;
          title: string;
          authors_json: string | null;
          year: number | null;
          venue: string | null;
          citation_count: number;
          scholar_url: string | null;
        }>();
      return (results ?? []).map((r) => ({
        id: r.id,
        title: r.title,
        authors: safeArr(r.authors_json),
        year: r.year,
        venue: r.venue,
        citationCount: r.citation_count,
        scholarUrl: r.scholar_url,
      }));
    },
    {
      name: "rank_top_cited",
      description:
        "Return the top-N citing papers ranked by their own citation count. These are the most impactful papers that cite this scholar.",
      schema: z.object({
        topN: z.number().int().min(1).max(50).default(10).describe("How many top papers to return"),
      }),
    }
  );
}

function safeArr(s: string | null): string[] {
  if (!s) return [];
  try {
    const v = JSON.parse(s);
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

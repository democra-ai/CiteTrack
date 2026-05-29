import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { D1Database } from "@cloudflare/workers-types";
import type { TopVenue } from "../../types";

export function makeExtractTopVenuesTool(db: D1Database, scholarId: string) {
  return tool(
    async ({ topN }: { topN: number }): Promise<TopVenue[]> => {
      const limit = Math.max(1, Math.min(50, topN));
      // Aggregate the venues (journals / conferences / repositories) the citing
      // papers appeared in, ranked by how many citing papers came from each — i.e.
      // the venues whose papers cite this scholar the most. venue/venue_type are
      // populated from OpenAlex primary_location.source during enrichment.
      const { results } = await db
        .prepare(
          `SELECT venue AS name,
                  MAX(venue_type) AS type,
                  COUNT(*) AS paper_count,
                  COALESCE(SUM(citation_count), 0) AS total_citations
           FROM citing_papers
           WHERE scholar_id = ?
             AND venue IS NOT NULL AND TRIM(venue) <> ''
           GROUP BY LOWER(TRIM(venue))
           ORDER BY paper_count DESC, total_citations DESC
           LIMIT ?`
        )
        .bind(scholarId, limit)
        .all<{
          name: string;
          type: string | null;
          paper_count: number;
          total_citations: number;
        }>();
      return (results ?? []).map((r) => ({
        name: r.name,
        type: r.type,
        paperCount: r.paper_count,
        totalCitations: r.total_citations,
      }));
    },
    {
      name: "extract_top_venues",
      description:
        "Aggregate the venues (journals / conferences / repositories) that the citing papers were published in, ranked by how many citing papers each venue contributed — the top venues citing this scholar's work.",
      schema: z.object({
        topN: z
          .number()
          .int()
          .min(1)
          .max(50)
          .default(20)
          .describe("How many top venues to return"),
      }),
    }
  );
}

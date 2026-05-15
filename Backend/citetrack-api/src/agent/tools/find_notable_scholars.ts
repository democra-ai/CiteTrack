import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { D1Database } from "@cloudflare/workers-types";
import type { NotableCiter } from "../../types";

export function makeFindNotableScholarsTool(db: D1Database, scholarId: string) {
  return tool(
    async ({
      hIndexThreshold,
      topN,
    }: {
      hIndexThreshold: number;
      topN: number;
    }): Promise<NotableCiter[]> => {
      const limit = Math.max(1, Math.min(50, topN));
      const threshold = Math.max(0, hIndexThreshold);

      const { results } = await db
        .prepare(
          `SELECT a.id, a.display_name, a.openalex_id, a.h_index, a.cited_by_count, a.works_count,
                  COUNT(DISTINCT pa.citing_paper_id) AS paper_count,
                  (SELECT i.display_name FROM author_institutions ai
                   JOIN institutions i ON i.id = ai.institution_id
                   WHERE ai.author_id = a.id LIMIT 1) AS affiliation
           FROM authors a
           JOIN paper_authors pa ON pa.author_id = a.id
           WHERE pa.scholar_id = ? AND a.h_index IS NOT NULL AND a.h_index >= ?
           GROUP BY a.id
           ORDER BY a.h_index DESC, a.cited_by_count DESC
           LIMIT ?`
        )
        .bind(scholarId, threshold, limit)
        .all<{
          id: string;
          display_name: string;
          openalex_id: string | null;
          h_index: number | null;
          cited_by_count: number | null;
          works_count: number | null;
          paper_count: number;
          affiliation: string | null;
        }>();

      const out: NotableCiter[] = [];
      for (const r of results ?? []) {
        const { results: examples } = await db
          .prepare(
            `SELECT cp.id, cp.title
             FROM paper_authors pa
             JOIN citing_papers cp ON cp.id = pa.citing_paper_id
             WHERE pa.author_id = ? AND pa.scholar_id = ?
             ORDER BY cp.citation_count DESC NULLS LAST
             LIMIT 3`
          )
          .bind(r.id, scholarId)
          .all<{ id: string; title: string }>();
        out.push({
          id: r.id,
          name: r.display_name,
          openalexId: r.openalex_id,
          affiliation: r.affiliation,
          hIndex: r.h_index,
          citedByCount: r.cited_by_count,
          worksCount: r.works_count,
          paperCount: r.paper_count,
          examplePapers: (examples ?? []).map((e) => ({ id: e.id, title: e.title })),
        });
      }
      return out;
    },
    {
      name: "find_notable_scholars",
      description:
        "Find notable scholars among the authors who cited this scholar. Notable scholars are those whose own h-index is at or above the threshold. Returns each notable citer with their h-index, citation count, primary affiliation, and example citing papers.",
      schema: z.object({
        hIndexThreshold: z
          .number()
          .int()
          .min(0)
          .max(200)
          .default(30)
          .describe("Minimum h-index. 30 is a typical threshold for established researchers."),
        topN: z.number().int().min(1).max(50).default(20).describe("How many notable scholars to return"),
      }),
    }
  );
}

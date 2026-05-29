import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { D1Database } from "@cloudflare/workers-types";
import type { CitingInstitution } from "../../types";

export function makeExtractInstitutionsTool(db: D1Database, scholarId: string) {
  return tool(
    async ({ topN }: { topN: number }): Promise<CitingInstitution[]> => {
      const limit = Math.max(1, Math.min(50, topN));
      const { results } = await db
        .prepare(
          `SELECT i.id, i.display_name, i.country_code, i.type,
                  COUNT(DISTINCT pa.citing_paper_id) AS paper_count,
                  COUNT(DISTINCT ai.author_id) AS author_count,
                  GROUP_CONCAT(DISTINCT a.display_name) AS author_names
           FROM institutions i
           JOIN author_institutions ai ON ai.institution_id = i.id
           JOIN paper_authors pa ON pa.author_id = ai.author_id
           JOIN authors a ON a.id = ai.author_id
           WHERE pa.scholar_id = ?
           GROUP BY i.id, i.display_name, i.country_code, i.type
           ORDER BY paper_count DESC, author_count DESC
           LIMIT ?`
        )
        .bind(scholarId, limit)
        .all<{
          id: string;
          display_name: string;
          country_code: string | null;
          type: string | null;
          paper_count: number;
          author_count: number;
          author_names: string | null;
        }>();
      return (results ?? []).map((r) => ({
        id: r.id,
        name: r.display_name,
        country: r.country_code,
        type: r.type,
        paperCount: r.paper_count,
        uniqueAuthorCount: r.author_count,
        // GROUP_CONCAT(DISTINCT ...) is comma-joined (SQLite can't combine DISTINCT
        // with a custom separator); split + trim + cap for the drill-down list.
        authors: (r.author_names ?? "")
          .split(",")
          .map((s) => s.trim())
          .filter((s) => s.length > 0)
          .slice(0, 30),
      }));
    },
    {
      name: "extract_institutions",
      description:
        "Aggregate the institutions that appear in the citing-papers' author affiliations, ranked by how many citing papers each institution contributed to.",
      schema: z.object({
        topN: z
          .number()
          .int()
          .min(1)
          .max(50)
          .default(15)
          .describe("How many top institutions to return"),
      }),
    }
  );
}

import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { Ai, D1Database } from "@cloudflare/workers-types";
import type { ResearchDirection } from "../../types";
import { embedTexts } from "../../enrichment/embeddings";
import { kmeans, pickK } from "../../lib/kmeans";
import { clearTopicClusters, insertTopicCluster, setTopicCluster } from "../../db/queries";

const LABEL_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

interface ClusterInput {
  paperId: string;
  title: string;
  abstract: string | null;
}

interface ClusterLabel {
  label: string;
  summary: string;
  keywords: string[];
}

async function labelCluster(
  ai: Ai,
  papers: Array<{ title: string; abstract: string | null }>,
  scholarName: string,
  scholarFieldHint?: string
): Promise<ClusterLabel> {
  const sample = papers.slice(0, 12);
  const bulletList = sample
    .map((p, i) => {
      const abs = p.abstract ? ` — ${p.abstract.slice(0, 200)}` : "";
      return `  ${i + 1}. ${p.title}${abs}`;
    })
    .join("\n");

  const fieldHint = scholarFieldHint ? ` The cited scholar's field is around: ${scholarFieldHint}.` : "";

  const prompt = `You are an academic analyst. Below are ${sample.length} research papers that all cite the work of researcher "${scholarName}".${fieldHint} They form one topical cluster.

Papers:
${bulletList}

Identify the unifying research direction of this cluster. Reply strictly as compact JSON with this exact shape:
{"label": "<concise 2-6 word topic label>", "summary": "<one sentence, <=180 chars, explaining the cluster theme>", "keywords": ["<keyword>", "<keyword>", "<keyword>", "<keyword>", "<keyword>"]}

Do not include any text outside the JSON object.`;

  let resp: unknown;
  try {
    resp = await withTimeout(
      ai.run(LABEL_MODEL, {
        messages: [
          { role: "system", content: "You output only valid compact JSON. No prose, no markdown fences." },
          { role: "user", content: prompt },
        ],
        max_tokens: 256,
        temperature: 0.2,
      }),
      20000,
      "ai.run(label)"
    );
  } catch (e) {
    console.error("[cluster_topics] labelCluster timeout/err:", e instanceof Error ? e.message : String(e));
    return fallbackLabel(sample);
  }

  const parsed = extractStructured(resp);
  if (parsed) {
    return {
      label: (parsed.label || "").toString().slice(0, 80) || fallbackLabel(sample).label,
      summary: (parsed.summary || "").toString().slice(0, 240),
      keywords: Array.isArray(parsed.keywords) ? parsed.keywords.map(String).slice(0, 8) : [],
    };
  }
  console.error("[cluster_topics] could not extract structured label. raw=", JSON.stringify(resp).slice(0, 400));
  return fallbackLabel(sample);
}

function fallbackLabel(papers: Array<{ title: string }>): ClusterLabel {
  const first = papers[0]?.title?.slice(0, 60) ?? "Cluster";
  return { label: first, summary: "", keywords: [] };
}

function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    p.then((v) => {
      clearTimeout(timer);
      resolve(v);
    }).catch((e) => {
      clearTimeout(timer);
      reject(e);
    });
  });
}

function extractStructured(resp: unknown): Partial<ClusterLabel> | null {
  const tryParse = (s: string): Partial<ClusterLabel> | null => {
    const m = s.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      return JSON.parse(m[0]) as Partial<ClusterLabel>;
    } catch {
      return null;
    }
  };
  if (typeof resp === "string") return tryParse(resp);
  if (resp && typeof resp === "object") {
    const r = resp as Record<string, unknown>;
    if (r.response && typeof r.response === "object") return r.response as Partial<ClusterLabel>;
    if (typeof r.response === "string") return tryParse(r.response);
    if (Array.isArray(r.choices) && r.choices.length > 0) {
      const first = r.choices[0] as Record<string, unknown>;
      const msg = first?.message as Record<string, unknown> | undefined;
      const content = msg?.content;
      if (typeof content === "string") return tryParse(content);
      if (content && typeof content === "object") return content as Partial<ClusterLabel>;
    }
    if (typeof r.result === "string") return tryParse(r.result);
    if (typeof r.text === "string") return tryParse(r.text);
  }
  return null;
}

export function makeClusterTopicsTool(
  db: D1Database,
  ai: Ai,
  scholarId: string,
  scholarName: string,
  scholarAffiliation: string | null | undefined
) {
  return tool(
    async ({ maxClusters }: { maxClusters: number }): Promise<ResearchDirection[]> => {
      const { results } = await db
        .prepare(
          `SELECT id, title, abstract
           FROM citing_papers
           WHERE scholar_id = ?
             AND ((abstract IS NOT NULL AND length(abstract) > 30) OR length(title) > 12)`
        )
        .bind(scholarId)
        .all<{ id: string; title: string; abstract: string | null }>();
      const inputs: ClusterInput[] = (results ?? []).map((r) => ({
        paperId: r.id,
        title: r.title,
        abstract: r.abstract,
      }));
      if (inputs.length === 0) return [];

      const texts = inputs.map((p) =>
        p.abstract ? `${p.title}. ${p.abstract}`.slice(0, 1800) : p.title
      );
      const vectors = await embedTexts(ai, texts);
      const k = Math.min(maxClusters, pickK(inputs.length));
      const { assignments } = kmeans(vectors, k);

      const byCluster: Map<number, ClusterInput[]> = new Map();
      for (let i = 0; i < inputs.length; i++) {
        const ci = assignments[i];
        if (!byCluster.has(ci)) byCluster.set(ci, []);
        byCluster.get(ci)!.push(inputs[i]);
      }

      await clearTopicClusters(db, scholarId);

      const directions: ResearchDirection[] = [];
      const sortedClusters = Array.from(byCluster.entries()).sort(
        (a, b) => b[1].length - a[1].length
      );

      for (const [origIdx, papers] of sortedClusters) {
        const label = await labelCluster(
          ai,
          papers.map((p) => ({ title: p.title, abstract: p.abstract })),
          scholarName,
          scholarAffiliation ?? undefined
        );
        const clusterIndex = directions.length;
        const clusterDbId = await insertTopicCluster(
          db,
          scholarId,
          clusterIndex,
          label.label,
          label.summary,
          label.keywords,
          papers.length
        );
        for (const p of papers) {
          await setTopicCluster(db, scholarId, p.paperId, clusterDbId);
        }
        directions.push({
          clusterIndex,
          label: label.label,
          summary: label.summary,
          keywords: label.keywords,
          paperCount: papers.length,
          examplePapers: papers.slice(0, 4).map((p) => ({ id: p.paperId, title: p.title })),
        });
        void origIdx;
      }
      return directions;
    },
    {
      name: "cluster_topics",
      description:
        "Cluster the citing papers by research topic using embeddings + k-means, then ask an LLM to label each cluster with a concise research-direction name, summary, and keywords. Returns the discovered research directions ordered by paper count.",
      schema: z.object({
        maxClusters: z
          .number()
          .int()
          .min(2)
          .max(12)
          .default(7)
          .describe("Upper bound on number of research directions to discover."),
      }),
    }
  );
}

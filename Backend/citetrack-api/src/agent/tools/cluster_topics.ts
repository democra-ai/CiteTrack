import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { Ai, D1Database } from "@cloudflare/workers-types";
import type { ResearchDirection } from "../../types";
import { embedTexts } from "../../enrichment/embeddings";
import { kmeans, pickK } from "../../lib/kmeans";
import {
  clearTopicClusters,
  insertTopicCluster,
  setTopicCluster,
  updateTopicClusterLabel,
} from "../../db/queries";

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
        max_tokens: 220,
        temperature: 0.2,
      }),
      15000,
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

interface LabeledCluster {
  clusterDbId: number;
  direction: ResearchDirection;
}

async function deduplicateLabels(
  ai: Ai,
  items: LabeledCluster[],
  scholarName: string
): Promise<string[]> {
  const list = items
    .map((it, i) => {
      const titles = it.direction.examplePapers
        .slice(0, 3)
        .map((p) => `"${p.title.slice(0, 80)}"`)
        .join("; ");
      return `Cluster ${i + 1} (${it.direction.paperCount} papers, current label: "${it.direction.label}")
  keywords: ${it.direction.keywords.join(", ") || "(none)"}
  example titles: ${titles}`;
    })
    .join("\n\n");

  const prompt = `下面是 ${items.length} 个研究方向聚类，来自引用学者"${scholarName}"工作的论文集合。其中多个聚类被独立标注成了几乎相同的标签（例如多个"Federated Graph Learning"）。请你结合每个聚类的关键词和示例标题，**重写这 ${items.length} 个标签**，使得：
- 所有标签**互不相同**
- 每个标签精准抓住该聚类相对其他聚类的**独特切入点**（方法 / 应用领域 / 数据形态 / 安全维度 / 系统层级等差异）
- 保持简洁（2-6 个词，与原始标签语言一致：中文或英文）

聚类详情：
${list}

严格输出 JSON，不要任何额外文字或 markdown：
{"labels": ["<label1>", "<label2>", ..., "<label${items.length}>"]}
数组长度必须正好为 ${items.length}，按聚类顺序对应。`;

  try {
    const resp = await withTimeout(
      ai.run(LABEL_MODEL, {
        messages: [
          { role: "system", content: "你只输出合法紧凑 JSON，不输出多余文字或 markdown。" },
          { role: "user", content: prompt },
        ],
        max_tokens: 280,
        temperature: 0.3,
      }),
      18000,
      "ai.run(dedup)"
    );
    const parsed = extractStructured(resp) as { labels?: unknown } | null;
    if (parsed && Array.isArray(parsed.labels) && parsed.labels.length === items.length) {
      return parsed.labels.map((l, i) => {
        const s = String(l ?? "").trim().slice(0, 80);
        return s || items[i].direction.label;
      });
    }
    console.error(
      "[cluster_topics] dedup parse failed or length mismatch:",
      JSON.stringify(parsed).slice(0, 300)
    );
  } catch (e) {
    console.error("[cluster_topics] dedup LLM err:", e instanceof Error ? e.message : String(e));
  }
  // Fallback: append distinguishing keyword to each duplicated label
  const seen = new Map<string, number>();
  return items.map((it) => {
    const base = it.direction.label;
    const key = base.toLowerCase();
    const n = seen.get(key) ?? 0;
    seen.set(key, n + 1);
    if (n === 0) return base;
    const kw = it.direction.keywords.find((k) => !base.toLowerCase().includes(k.toLowerCase()));
    return kw ? `${base} (${kw})` : `${base} #${n + 1}`;
  });
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

      const sortedClusters = Array.from(byCluster.entries()).sort(
        (a, b) => b[1].length - a[1].length
      );

      // Label all clusters concurrently — Workers AI handles parallel inference,
      // so wall time is ~one LLM call instead of N. Sequential was hitting the
      // Worker wall-time budget on scholars with many citing papers.
      const labeled = await Promise.all(
        sortedClusters.map(async ([, papers], clusterIndex) => {
          const label = await labelCluster(
            ai,
            papers.map((p) => ({ title: p.title, abstract: p.abstract })),
            scholarName,
            scholarAffiliation ?? undefined
          );
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
          return {
            clusterDbId,
            direction: {
              clusterIndex,
              label: label.label,
              summary: label.summary,
              keywords: label.keywords,
              paperCount: papers.length,
              examplePapers: papers
                .slice(0, 4)
                .map((p) => ({ id: p.paperId, title: p.title })),
            } as ResearchDirection,
          };
        })
      );

      // Parallel labeling doesn't see peer clusters, so very topic-focused
      // scholars often end up with several near-identical labels (e.g. 4×
      // "Federated Graph Learning"). One extra LLM pass rewrites them into
      // mutually-distinct labels emphasising each cluster's unique angle.
      const labels = labeled.map((x) => x.direction.label.trim().toLowerCase());
      const hasDupes = new Set(labels).size !== labels.length;
      if (hasDupes && labeled.length >= 2) {
        const distinct = await deduplicateLabels(ai, labeled, scholarName);
        for (let i = 0; i < labeled.length; i++) {
          const newLabel = distinct[i];
          if (newLabel && newLabel !== labeled[i].direction.label) {
            try {
              await updateTopicClusterLabel(db, labeled[i].clusterDbId, newLabel);
              labeled[i].direction.label = newLabel;
            } catch (e) {
              console.error(
                "[cluster_topics] updateTopicClusterLabel failed",
                labeled[i].clusterDbId,
                e instanceof Error ? e.message : String(e)
              );
            }
          }
        }
      }

      return labeled.map((x) => x.direction);
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

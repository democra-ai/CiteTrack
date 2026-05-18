import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { Ai } from "@cloudflare/workers-types";
import type {
  AnalysisResult,
  DimensionScore,
  FundingPrediction,
  HaiyouScoreReport,
  HaiyouScoreRequest,
  RepresentativePaperInput,
} from "../../types";

const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

interface DimensionSpec {
  key: string;
  label: string;
  maxScore: number;
  reviewerFocus: string;
  buildEvidence: (ctx: ScoringContext) => string;
  baseConfidence: (ctx: ScoringContext) => "high" | "medium" | "low";
}

interface ScoringContext {
  scholarName: string;
  analysis: AnalysisResult | null;
  cvText: string | null;
  returnPlanText: string | null;
  representativePapers: RepresentativePaperInput[];
}

function fmtPapers(a: AnalysisResult | null): string {
  if (!a || a.topCitedPapers.length === 0) return "（无引用分析数据）";
  return a.topCitedPapers
    .slice(0, 10)
    .map(
      (p, i) =>
        `  ${i + 1}. [${p.citationCount} 被引] ${p.title}${p.year ? ` (${p.year})` : ""}${
          p.venue ? ` — ${p.venue}` : ""
        }`
    )
    .join("\n");
}

function fmtRepPapers(rs: RepresentativePaperInput[]): string {
  if (rs.length === 0) return "（申请人未提供代表作信息）";
  return rs
    .map(
      (r, i) =>
        `  ${i + 1}. ${r.title}${r.year ? ` (${r.year})` : ""} | 期刊:${r.journal ?? "?"} | IF:${
          r.impactFactor ?? "?"
        } | 他引:${r.citationCount ?? "?"} | 署名:${r.authorRole ?? "?"} | ESI高被引:${
          r.esiHighlyCited ? "是" : "否"
        }`
    )
    .join("\n");
}

function fmtDirections(a: AnalysisResult | null): string {
  if (!a || a.researchDirections.length === 0) return "（无研究方向聚类数据）";
  return a.researchDirections
    .map(
      (d) =>
        `  · ${d.label}（${d.paperCount} 篇相关引用）${
          d.keywords.length ? ` [${d.keywords.join(", ")}]` : ""
        }`
    )
    .join("\n");
}

function fmtNotable(a: AnalysisResult | null): string {
  if (!a || a.notableCiters.length === 0) return "（暂无知名学者引用数据）";
  return a.notableCiters
    .slice(0, 10)
    .map((n) => `  · ${n.name} (h=${n.hIndex ?? "?"}, 总被引=${n.citedByCount ?? "?"})${n.affiliation ? ` @ ${n.affiliation}` : ""}`)
    .join("\n");
}

function fmtInstitutions(a: AnalysisResult | null): string {
  if (!a || a.citingInstitutions.length === 0) return "（暂无引用机构数据）";
  return a.citingInstitutions
    .slice(0, 10)
    .map((i) => `  · ${i.name}${i.country ? ` (${i.country})` : ""} — ${i.paperCount} 篇引用`)
    .join("\n");
}

const DIMENSIONS: DimensionSpec[] = [
  {
    key: "education_experience",
    label: "教育及学术经历",
    maxScore: 15,
    reviewerFocus:
      "国际顶级机构的教育与工作经历、师承、参与的重要项目与课题。强调海外高水平平台与国际化训练。",
    buildEvidence: (c) =>
      `申请人简历（教育/工作经历）：\n${c.cvText ?? "（申请人未提供简历文本，仅能从引用网络间接推断学术圈层）"}\n\n` +
      `引用其工作的机构（侧面反映其所处学术圈层）：\n${fmtInstitutions(c.analysis)}`,
    baseConfidence: (c) => (c.cvText ? "high" : "low"),
  },
  {
    key: "research_output",
    label: "科研成果与创新",
    maxScore: 30,
    reviewerFocus:
      "凝练 2-3 项代表性成果，阐明其创新性、科学价值与本人贡献；代表作质量（影响因子、他引次数、ESI 高被引、署名位置）；成果的系统性与高水平。这是权重最高的维度。",
    buildEvidence: (c) =>
      `代表性论著（申请人填报）：\n${fmtRepPapers(c.representativePapers)}\n\n` +
      `引用影响力最高的论文（系统抓取）：\n${fmtPapers(c.analysis)}\n\n` +
      `引用论文总数：${c.analysis?.citingPapersCount ?? "未知"}`,
    baseConfidence: (c) =>
      c.representativePapers.length >= 3 || (c.analysis && c.analysis.topCitedPapers.length >= 5)
        ? "high"
        : "medium",
  },
  {
    key: "originality",
    label: "原始创新性",
    maxScore: 20,
    reviewerFocus:
      "研究的差异性、独特性、原始创新性；是否提出新观点/新方法/开辟新方向；是否避免重复性工作。同行的认可是原创性的强证据。",
    buildEvidence: (c) =>
      `研究方向聚类（反映研究主线的聚焦与独特性）：\n${fmtDirections(c.analysis)}\n\n` +
      `引用其工作的知名学者（领域内大佬的关注是原创性的同行背书）：\n${fmtNotable(c.analysis)}`,
    baseConfidence: (c) =>
      c.analysis && (c.analysis.notableCiters.length > 0 || c.analysis.researchDirections.length > 0)
        ? "medium"
        : "low",
  },
  {
    key: "potential",
    label: "发展潜力",
    maxScore: 20,
    reviewerFocus:
      "持续产出高水平成果的能力、研究的可持续性、所在领域的重大需求、上升势头；成果集中且高水平优于分散低水平。",
    buildEvidence: (c) =>
      `研究方向聚焦度：\n${fmtDirections(c.analysis)}\n\n` +
      `引用机构的广度与国际化（反映领域需求与国际辐射力）：\n${fmtInstitutions(c.analysis)}\n\n` +
      `知名学者引用情况（领域领军人物是否在跟进其工作）：\n${fmtNotable(c.analysis)}`,
    baseConfidence: (c) =>
      c.analysis && c.analysis.citingInstitutions.length > 0 ? "medium" : "low",
  },
  {
    key: "return_plan",
    label: "回国设想与依托单位支持",
    maxScore: 15,
    reviewerFocus:
      "拟解决的关键科学问题是否清晰、工作计划是否可行、与已有积累是否延续、依托单位是否提供量化的平台/团队/经费支持。",
    buildEvidence: (c) =>
      `回国设想与依托单位支持（申请人填报）：\n${
        c.returnPlanText ?? "（申请人未提供回国设想文本，仅能基于研究方向的延续性做有限评估）"
      }\n\n` + `已有研究方向（用于判断回国计划与既往积累的延续性）：\n${fmtDirections(c.analysis)}`,
    baseConfidence: (c) => (c.returnPlanText ? "high" : "low"),
  },
];

interface RawDimScore {
  score?: number;
  confidence?: string;
  reasoning?: string;
  evidence?: unknown;
  suggestions?: unknown;
}

function extractJSON(resp: unknown): Record<string, unknown> | null {
  const tryParse = (s: string): Record<string, unknown> | null => {
    const m = s.match(/\{[\s\S]*\}/);
    if (!m) return null;
    try {
      return JSON.parse(m[0]) as Record<string, unknown>;
    } catch {
      return null;
    }
  };
  if (typeof resp === "string") return tryParse(resp);
  if (resp && typeof resp === "object") {
    const r = resp as Record<string, unknown>;
    if (r.response && typeof r.response === "object") return r.response as Record<string, unknown>;
    if (typeof r.response === "string") return tryParse(r.response);
    if (Array.isArray(r.choices) && r.choices.length > 0) {
      const msg = (r.choices[0] as Record<string, unknown>)?.message as
        | Record<string, unknown>
        | undefined;
      if (typeof msg?.content === "string") return tryParse(msg.content);
      if (msg?.content && typeof msg.content === "object")
        return msg.content as Record<string, unknown>;
    }
  }
  return null;
}

function withTimeout<T>(p: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        resolve(v);
      },
      (e) => {
        clearTimeout(t);
        reject(e);
      }
    );
  });
}

function clampScore(v: unknown, max: number): number {
  const n = typeof v === "number" ? v : parseFloat(String(v ?? ""));
  if (!isFinite(n)) return Math.round(max * 0.5);
  return Math.max(0, Math.min(max, Math.round(n * 10) / 10));
}

function toStrArray(v: unknown, limit = 4): string[] {
  if (!Array.isArray(v)) return [];
  return v.map((x) => String(x)).filter((s) => s.trim().length > 0).slice(0, limit);
}

async function scoreDimension(
  ai: Ai,
  spec: DimensionSpec,
  ctx: ScoringContext
): Promise<DimensionScore> {
  const evidence = spec.buildEvidence(ctx);
  const prompt = `你是国家自然科学基金"优秀青年科学基金项目（海外）"（海优）的资深评审专家。请对以下申请人在【${spec.label}】维度上评分。

该维度满分 ${spec.maxScore} 分。评审专家在此维度重点关注：${spec.reviewerFocus}

申请人：${ctx.scholarName || "（匿名）"}

可用证据：
${evidence}

评分标准锚点（占满分比例）：
- 顶尖（90-100%）：国际领先，证据充分，明显优于同侪
- 优秀（75-89%）：高水平，证据较充分，有竞争力
- 合格（60-74%）：中等水平，证据一般
- 偏弱（<60%）：证据不足或水平有限

严格只输出如下 JSON（不要任何额外文字、不要 markdown 代码块）：
{"score": <0到${spec.maxScore}的数字>, "confidence": "high|medium|low", "reasoning": "<2-3句中文评分理由，引用具体证据>", "evidence": ["<支撑性证据点>", "..."], "suggestions": ["<针对该维度的具体提升建议>", "..."]}`;

  let resp: unknown;
  try {
    resp = await withTimeout(
      ai.run(MODEL, {
        messages: [
          {
            role: "system",
            content:
              "你是严谨的国家自然科学基金海优评审专家，只输出合法紧凑 JSON，不输出多余文字或 markdown。",
          },
          { role: "user", content: prompt },
        ],
        max_tokens: 420,
        temperature: 0.2,
      }),
      18000,
      `score:${spec.key}`
    );
  } catch (e) {
    console.error(`[haiyou] ${spec.key} LLM failed:`, e instanceof Error ? e.message : String(e));
    return fallbackDimension(spec, ctx);
  }

  const parsed = extractJSON(resp) as RawDimScore | null;
  if (!parsed) {
    console.error(`[haiyou] ${spec.key} unparseable:`, JSON.stringify(resp).slice(0, 300));
    return fallbackDimension(spec, ctx);
  }

  const conf =
    parsed.confidence === "high" || parsed.confidence === "medium" || parsed.confidence === "low"
      ? parsed.confidence
      : spec.baseConfidence(ctx);

  return {
    key: spec.key,
    label: spec.label,
    maxScore: spec.maxScore,
    score: clampScore(parsed.score, spec.maxScore),
    confidence: conf,
    reasoning: String(parsed.reasoning ?? "").slice(0, 600) || "（模型未给出理由）",
    evidence: toStrArray(parsed.evidence, 5),
    suggestions: toStrArray(parsed.suggestions, 5),
  };
}

function fallbackDimension(spec: DimensionSpec, ctx: ScoringContext): DimensionScore {
  // Conservative midpoint estimate when the LLM call fails.
  const conf = spec.baseConfidence(ctx);
  const ratio = conf === "high" ? 0.7 : conf === "medium" ? 0.62 : 0.55;
  return {
    key: spec.key,
    label: spec.label,
    maxScore: spec.maxScore,
    score: Math.round(spec.maxScore * ratio * 10) / 10,
    confidence: conf,
    reasoning: "评分模型暂时不可用，此处为基于数据完整度的保守估计，请稍后重试以获得准确评分。",
    evidence: [],
    suggestions: ["稍后重新运行评分以获得该维度的详细分析。"],
  };
}

function predictFunding(total: number): FundingPrediction {
  if (total >= 85) return "priority";
  if (total >= 70) return "approved";
  return "rejected";
}

async function summarize(
  ai: Ai,
  ctx: ScoringContext,
  dims: DimensionScore[],
  total: number,
  prediction: FundingPrediction
): Promise<{ overall: string; top: string[] }> {
  const dimLines = dims
    .map((d) => `- ${d.label}: ${d.score}/${d.maxScore}（${d.confidence}）— ${d.reasoning}`)
    .join("\n");
  const predLabel =
    prediction === "priority" ? "优先资助 (≥85)" : prediction === "approved" ? "同意资助 (70-84)" : "不同意资助 (<70)";

  const prompt = `你是海优资深评审专家。基于以下分维度评分，给出整体评价与最关键的改进建议。

申请人：${ctx.scholarName || "（匿名）"}
分维度结果：
${dimLines}

合计：${total}/100，预测：${predLabel}

严格只输出如下 JSON：
{"overall": "<3-4句中文整体评价，指出最强项与最大短板>", "top": ["<最高优先级的提升建议1>", "<建议2>", "<建议3>"]}`;

  try {
    const resp = await withTimeout(
      ai.run(MODEL, {
        messages: [
          { role: "system", content: "你只输出合法紧凑 JSON，不输出多余文字。" },
          { role: "user", content: prompt },
        ],
        max_tokens: 400,
        temperature: 0.3,
      }),
      18000,
      "score:summary"
    );
    const parsed = extractJSON(resp);
    if (parsed) {
      return {
        overall: String(parsed.overall ?? "").slice(0, 800) || defaultOverall(total, prediction),
        top: toStrArray(parsed.top, 5),
      };
    }
  } catch (e) {
    console.error("[haiyou] summary failed:", e instanceof Error ? e.message : String(e));
  }
  return {
    overall: defaultOverall(total, prediction),
    top: dims
      .flatMap((d) => d.suggestions.slice(0, 1))
      .filter(Boolean)
      .slice(0, 3),
  };
}

function defaultOverall(total: number, prediction: FundingPrediction): string {
  const label =
    prediction === "priority"
      ? "处于优先资助区间，竞争力强"
      : prediction === "approved"
        ? "处于同意资助区间，仍有提升空间"
        : "低于资助线，需要重点补强";
  return `综合模拟评分 ${total}/100，${label}。请结合各维度的具体建议进行针对性打磨。`;
}

/** LangChain tool: assess a scholar against the 海优 5-dimension rubric. */
export function makeHaiyouScoreTool(ai: Ai) {
  return tool(
    async (input: {
      scholarName: string;
      analysis: AnalysisResult | null;
      cvText: string | null;
      returnPlanText: string | null;
      representativePapers: RepresentativePaperInput[];
    }): Promise<HaiyouScoreReport> => {
      const ctx: ScoringContext = {
        scholarName: input.scholarName,
        analysis: input.analysis,
        cvText: input.cvText,
        returnPlanText: input.returnPlanText,
        representativePapers: input.representativePapers ?? [],
      };

      // Score all 5 dimensions concurrently — Workers AI handles parallel
      // inference, so wall time is ~one call instead of the sum of six.
      const dims: DimensionScore[] = await Promise.all(
        DIMENSIONS.map((spec) => scoreDimension(ai, spec, ctx))
      );

      const total =
        Math.round(dims.reduce((s, d) => s + d.score, 0) * 10) / 10;
      const prediction = predictFunding(total);
      const { overall, top } = await summarize(ai, ctx, dims, total, prediction);

      return {
        scholarId: "",
        generatedAt: Date.now(),
        dimensions: dims,
        totalScore: total,
        maxTotal: 100,
        fundingPrediction: prediction,
        overallAssessment: overall,
        topSuggestions: top,
        dataCompleteness: {
          hasAnalysis: Boolean(ctx.analysis),
          hasCvText: Boolean(ctx.cvText),
          hasReturnPlan: Boolean(ctx.returnPlanText),
          representativePaperCount: ctx.representativePapers.length,
        },
      };
    },
    {
      name: "assess_haiyou",
      description:
        "Score a scholar against the NSFC Overseas Excellent Young Scientists (海优) 5-dimension review rubric (15+30+20+20+15=100), returning per-dimension scores, reasoning, evidence, improvement suggestions, total, and a funding prediction.",
      schema: z.object({
        scholarName: z.string().default(""),
        analysis: z.any().nullable(),
        cvText: z.string().nullable(),
        returnPlanText: z.string().nullable(),
        representativePapers: z.array(z.any()).default([]),
      }),
    }
  );
}

export async function runHaiyouScoring(
  ai: Ai,
  req: HaiyouScoreRequest & { analysis: AnalysisResult | null }
): Promise<HaiyouScoreReport> {
  const t = makeHaiyouScoreTool(ai);
  const report = (await t.invoke({
    scholarName: req.scholarName ?? "",
    analysis: req.analysis,
    cvText: req.cvText ?? null,
    returnPlanText: req.returnPlanText ?? null,
    representativePapers: req.representativePapers ?? [],
  })) as HaiyouScoreReport;
  report.scholarId = req.scholarId;
  return report;
}

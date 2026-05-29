import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { Ai } from "@cloudflare/workers-types";
import type {
  AnalysisResult,
  DimensionScore,
  FundingPrediction,
  HaiyouScoreReport,
  HaiyouScoreRequest,
} from "../../types";

const MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";

type Lang = "en" | "zh";
function asLang(l: string | null | undefined): Lang {
  return l === "zh" ? "zh" : "en";
}
function T(lang: Lang, zh: string, en: string): string {
  return lang === "zh" ? zh : en;
}

// "Score your impact": assess a scholar PURELY from their own work's citation
// footprint (the analysis). No CV / return-plan / self-reported representative
// papers — everything is inferred from the academic record we already have.
interface ScoringContext {
  scholarName: string;
  analysis: AnalysisResult | null;
  lang: Lang;
}

interface DimensionSpec {
  key: string;
  maxScore: number;
  label: (l: Lang) => string;
  reviewerFocus: (l: Lang) => string;
  buildEvidence: (ctx: ScoringContext) => string;
  baseConfidence: (ctx: ScoringContext) => "high" | "medium" | "low";
}

// --- evidence formatters (analysis-only; never reference missing uploads) ---

function fmtPapers(a: AnalysisResult | null, lang: Lang): string {
  if (!a || a.topCitedPapers.length === 0) return T(lang, "（暂无引用分析数据）", "(no citation-analysis data yet)");
  const cited = T(lang, "被引", "citations");
  return a.topCitedPapers
    .slice(0, 10)
    .map(
      (p, i) =>
        `  ${i + 1}. [${p.citationCount} ${cited}] ${p.title}${p.year ? ` (${p.year})` : ""}${
          p.venue ? ` — ${p.venue}` : ""
        }`
    )
    .join("\n");
}

function fmtDirections(a: AnalysisResult | null, lang: Lang): string {
  if (!a || a.researchDirections.length === 0) return T(lang, "（无研究方向聚类数据）", "(no research-direction clusters)");
  const papers = T(lang, "篇相关引用", "citing papers");
  return a.researchDirections
    .map(
      (d) =>
        `  · ${d.label}（${d.paperCount} ${papers}）${d.keywords.length ? ` [${d.keywords.join(", ")}]` : ""}`
    )
    .join("\n");
}

function fmtNotable(a: AnalysisResult | null, lang: Lang): string {
  if (!a || a.notableCiters.length === 0) return T(lang, "（暂无知名学者引用数据）", "(no notable-scholar citations yet)");
  const total = T(lang, "总被引", "total cites");
  return a.notableCiters
    .slice(0, 10)
    .map((n) => `  · ${n.name} (h=${n.hIndex ?? "?"}, ${total}=${n.citedByCount ?? "?"})${n.affiliation ? ` @ ${n.affiliation}` : ""}`)
    .join("\n");
}

function fmtInstitutions(a: AnalysisResult | null, lang: Lang): string {
  if (!a || a.citingInstitutions.length === 0) return T(lang, "（暂无引用机构数据）", "(no citing-institution data yet)");
  const cites = T(lang, "篇引用", "citing papers");
  return a.citingInstitutions
    .slice(0, 10)
    .map((i) => `  · ${i.name}${i.country ? ` (${i.country})` : ""} — ${i.paperCount} ${cites}`)
    .join("\n");
}

function fmtVenues(a: AnalysisResult | null, lang: Lang): string {
  if (!a || !a.topVenues || a.topVenues.length === 0) return T(lang, "（暂无引用刊物数据）", "(no citing-venue data yet)");
  const cites = T(lang, "篇引用", "citing papers");
  return a.topVenues
    .slice(0, 10)
    .map((v) => `  · ${v.name}${v.type ? ` [${v.type}]` : ""} — ${v.paperCount} ${cites}`)
    .join("\n");
}

const DIMENSIONS: DimensionSpec[] = [
  {
    key: "academic_standing",
    maxScore: 15,
    label: (l) => T(l, "学术圈层与认可", "Academic standing & recognition"),
    reviewerFocus: (l) =>
      T(
        l,
        "从引用网络反映的学术圈层：引用其工作的机构层次与国际化程度、知名学者的关注，侧面体现其所处的学术平台与训练水平。",
        "Academic standing inferred from the citation network: the calibre and internationality of the institutions citing the work, and attention from well-known scholars — a proxy for the platform and training level."
      ),
    buildEvidence: (c) =>
      `${T(c.lang, "引用其工作的机构", "Institutions citing the work")}:\n${fmtInstitutions(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "引用其工作的知名学者", "Notable scholars citing the work")}:\n${fmtNotable(c.analysis, c.lang)}`,
    baseConfidence: (c) =>
      c.analysis && (c.analysis.citingInstitutions.length > 0 || c.analysis.notableCiters.length > 0) ? "medium" : "low",
  },
  {
    key: "research_output",
    maxScore: 30,
    label: (l) => T(l, "科研成果与影响", "Research output & impact"),
    reviewerFocus: (l) =>
      T(
        l,
        "代表性成果的影响力：高被引论文的他引规模、引用论文总量、发表/被引刊物的层次，体现成果的系统性与高水平。这是权重最高的维度。",
        "Impact of the body of work: citation volume of the most-cited papers, total citing-paper count, and the calibre of the venues citing it — reflecting a systematic, high-level output. This is the highest-weighted dimension."
      ),
    buildEvidence: (c) =>
      `${T(c.lang, "影响力最高的论文（被其引用）", "Highest-impact citing papers")}:\n${fmtPapers(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "引用论文总数", "Total citing papers")}: ${c.analysis?.citingPapersCount ?? T(c.lang, "未知", "unknown")}\n\n` +
      `${T(c.lang, "引用其工作的刊物/会议", "Venues citing the work")}:\n${fmtVenues(c.analysis, c.lang)}`,
    baseConfidence: (c) => (c.analysis && c.analysis.topCitedPapers.length >= 5 ? "high" : c.analysis ? "medium" : "low"),
  },
  {
    key: "originality",
    maxScore: 20,
    label: (l) => T(l, "原始创新性", "Originality"),
    reviewerFocus: (l) =>
      T(
        l,
        "研究的差异性与原创性：研究方向是否聚焦且独特、是否开辟新方向；领域内知名学者的引用是原创性的同行背书。",
        "Distinctiveness and originality of the research: whether the directions are focused and unique or open new ground; citations from well-known scholars are peer endorsement of originality."
      ),
    buildEvidence: (c) =>
      `${T(c.lang, "研究方向聚类（反映研究主线的聚焦与独特性）", "Research-direction clusters (focus & distinctiveness)")}:\n${fmtDirections(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "引用其工作的知名学者（同行背书）", "Notable scholars citing the work (peer endorsement)")}:\n${fmtNotable(c.analysis, c.lang)}`,
    baseConfidence: (c) =>
      c.analysis && (c.analysis.notableCiters.length > 0 || c.analysis.researchDirections.length > 0) ? "medium" : "low",
  },
  {
    key: "potential",
    maxScore: 20,
    label: (l) => T(l, "发展潜力", "Development potential"),
    reviewerFocus: (l) =>
      T(
        l,
        "持续产出高水平成果的能力与上升势头：研究方向的聚焦度、引用机构的广度与国际化、领域领军人物是否在跟进其工作。",
        "Capacity for sustained high-level output and upward momentum: focus of the research directions, breadth and internationality of citing institutions, and whether field leaders are following the work."
      ),
    buildEvidence: (c) =>
      `${T(c.lang, "研究方向聚焦度", "Research-direction focus")}:\n${fmtDirections(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "引用机构的广度与国际化", "Breadth & internationality of citing institutions")}:\n${fmtInstitutions(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "知名学者引用情况", "Notable-scholar attention")}:\n${fmtNotable(c.analysis, c.lang)}`,
    baseConfidence: (c) => (c.analysis && c.analysis.citingInstitutions.length > 0 ? "medium" : "low"),
  },
  {
    key: "field_recognition",
    maxScore: 15,
    label: (l) => T(l, "领域与国际认可", "Field & international recognition"),
    reviewerFocus: (l) =>
      T(
        l,
        "在领域内与国际上的被认可程度：引用其工作的顶级刊物/会议的层次、引用机构的国际分布、知名学者的跨国关注。",
        "Recognition within the field and internationally: the calibre of top venues/conferences citing the work, the international spread of citing institutions, and cross-border attention from notable scholars."
      ),
    buildEvidence: (c) =>
      `${T(c.lang, "引用其工作的顶级刊物/会议", "Top venues/conferences citing the work")}:\n${fmtVenues(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "引用机构（国际分布）", "Citing institutions (international spread)")}:\n${fmtInstitutions(c.analysis, c.lang)}\n\n` +
      `${T(c.lang, "知名学者引用", "Notable-scholar citations")}:\n${fmtNotable(c.analysis, c.lang)}`,
    baseConfidence: (c) =>
      c.analysis && ((c.analysis.topVenues?.length ?? 0) > 0 || c.analysis.citingInstitutions.length > 0) ? "medium" : "low",
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
  const lang = ctx.lang;
  const label = spec.label(lang);
  const evidence = spec.buildEvidence(ctx);

  const anchors = T(
    lang,
    `评分标准锚点（占满分比例）：
- 顶尖（90-100%）：国际领先，证据充分，明显优于同侪
- 优秀（75-89%）：高水平，证据较充分，有竞争力
- 合格（60-74%）：中等水平，证据一般
- 偏弱（<60%）：证据不足或水平有限`,
    `Scoring anchors (share of the maximum):
- Outstanding (90-100%): internationally leading, strong evidence, clearly above peers
- Strong (75-89%): high level, solid evidence, competitive
- Adequate (60-74%): mid-level, modest evidence
- Weak (<60%): limited evidence or impact`
  );

  const prompt = T(
    lang,
    `你是一位资深学术影响力评估专家。请仅根据该学者**自身工作被引用的情况**，对其在【${label}】维度上评分。不要假设或要求任何简历、回国计划或自报材料——只用下面给出的引用分析证据。

该维度满分 ${spec.maxScore} 分。重点关注：${spec.reviewerFocus(lang)}

学者：${ctx.scholarName || "（匿名）"}

可用证据（全部来自其论文的引用分析）：
${evidence}

${anchors}

严格只输出如下 JSON（不要任何额外文字、不要 markdown）：
{"score": <0到${spec.maxScore}的数字>, "confidence": "high|medium|low", "reasoning": "<2-3句中文评分理由，引用上面的具体证据>", "evidence": ["<支撑性证据点>", "..."], "suggestions": ["<针对该维度的具体提升建议>", "..."]}`,
    `You are a senior academic-impact assessor. Score this scholar on the "${label}" dimension using ONLY the evidence of how their OWN work has been cited. Do not assume or ask for any CV, relocation plan, or self-reported materials — use only the citation-analysis evidence below.

This dimension is out of ${spec.maxScore}. Focus on: ${spec.reviewerFocus(lang)}

Scholar: ${ctx.scholarName || "(anonymous)"}

Available evidence (all from the citation analysis of their papers):
${evidence}

${anchors}

Output strictly as JSON only (no extra text, no markdown):
{"score": <number 0 to ${spec.maxScore}>, "confidence": "high|medium|low", "reasoning": "<2-3 sentences citing the specific evidence above>", "evidence": ["<supporting point>", "..."], "suggestions": ["<concrete suggestion to strengthen this dimension>", "..."]}`
  );

  let resp: unknown;
  try {
    resp = await withTimeout(
      ai.run(MODEL, {
        messages: [
          {
            role: "system",
            content: T(
              lang,
              "你是严谨的学术影响力评估专家，只输出合法紧凑 JSON，不输出多余文字或 markdown。",
              "You are a rigorous academic-impact assessor. Output only valid compact JSON, no prose or markdown."
            ),
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
    console.error(`[impact] ${spec.key} LLM failed:`, e instanceof Error ? e.message : String(e));
    return fallbackDimension(spec, ctx);
  }

  const parsed = extractJSON(resp) as RawDimScore | null;
  if (!parsed) {
    console.error(`[impact] ${spec.key} unparseable:`, JSON.stringify(resp).slice(0, 300));
    return fallbackDimension(spec, ctx);
  }

  const conf =
    parsed.confidence === "high" || parsed.confidence === "medium" || parsed.confidence === "low"
      ? parsed.confidence
      : spec.baseConfidence(ctx);

  return {
    key: spec.key,
    label,
    maxScore: spec.maxScore,
    score: clampScore(parsed.score, spec.maxScore),
    confidence: conf,
    reasoning:
      String(parsed.reasoning ?? "").slice(0, 600) ||
      T(lang, "（模型未给出理由）", "(model gave no rationale)"),
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
    label: spec.label(ctx.lang),
    maxScore: spec.maxScore,
    score: Math.round(spec.maxScore * ratio * 10) / 10,
    confidence: conf,
    reasoning: T(
      ctx.lang,
      "评分模型暂时不可用，此处为基于数据完整度的保守估计，请稍后重试以获得准确评分。",
      "The scoring model was momentarily unavailable; this is a conservative estimate based on data completeness — re-run shortly for an accurate score."
    ),
    evidence: [],
    suggestions: [
      T(ctx.lang, "稍后重新运行评分以获得该维度的详细分析。", "Re-run the score shortly for a detailed analysis of this dimension."),
    ],
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
  const lang = ctx.lang;
  const dimLines = dims
    .map((d) => `- ${d.label}: ${d.score}/${d.maxScore}（${d.confidence}）— ${d.reasoning}`)
    .join("\n");
  const tierLabel =
    prediction === "priority"
      ? T(lang, "影响力突出 (≥85)", "Outstanding impact (≥85)")
      : prediction === "approved"
        ? T(lang, "影响力较强 (70-84)", "Strong impact (70-84)")
        : T(lang, "影响力成长中 (<70)", "Developing impact (<70)");

  const prompt = T(
    lang,
    `你是学术影响力评估专家。基于以下分维度评分，给出整体评价与最关键的改进建议。评价完全基于该学者自身工作的引用表现，不要提及简历或自报材料。

学者：${ctx.scholarName || "（匿名）"}
分维度结果：
${dimLines}

合计：${total}/100，影响力档位：${tierLabel}

严格只输出如下 JSON：
{"overall": "<3-4句中文整体评价，指出最强项与最大短板>", "top": ["<最高优先级的提升建议1>", "<建议2>", "<建议3>"]}`,
    `You are an academic-impact assessor. Based on the per-dimension scores below, give an overall assessment and the most important suggestions. Base everything on the scholar's own citation footprint; do not mention a CV or self-reported materials.

Scholar: ${ctx.scholarName || "(anonymous)"}
Per-dimension results:
${dimLines}

Total: ${total}/100, impact tier: ${tierLabel}

Output strictly as JSON:
{"overall": "<3-4 sentence overall assessment naming the biggest strength and weakness>", "top": ["<highest-priority suggestion 1>", "<2>", "<3>"]}`
  );

  try {
    const resp = await withTimeout(
      ai.run(MODEL, {
        messages: [
          {
            role: "system",
            content: T(
              lang,
              "你只输出合法紧凑 JSON，不输出多余文字。",
              "Output only valid compact JSON, no extra text."
            ),
          },
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
        overall: String(parsed.overall ?? "").slice(0, 800) || defaultOverall(ctx.lang, total, prediction),
        top: toStrArray(parsed.top, 5),
      };
    }
  } catch (e) {
    console.error("[impact] summary failed:", e instanceof Error ? e.message : String(e));
  }
  return {
    overall: defaultOverall(ctx.lang, total, prediction),
    top: dims
      .flatMap((d) => d.suggestions.slice(0, 1))
      .filter(Boolean)
      .slice(0, 3),
  };
}

function defaultOverall(lang: Lang, total: number, prediction: FundingPrediction): string {
  const label =
    prediction === "priority"
      ? T(lang, "影响力突出，竞争力强", "outstanding impact and strong competitiveness")
      : prediction === "approved"
        ? T(lang, "影响力较强，仍有提升空间", "strong impact with room to grow")
        : T(lang, "影响力成长中，需要重点补强", "developing impact that needs focused strengthening");
  return T(
    lang,
    `综合影响力评分 ${total}/100，${label}。请结合各维度的具体建议进行针对性打磨。`,
    `Overall impact score ${total}/100 — ${label}. Use the per-dimension suggestions to focus your next steps.`
  );
}

/** LangChain tool: assess a scholar's academic impact from their citation footprint. */
export function makeHaiyouScoreTool(ai: Ai) {
  return tool(
    async (input: {
      scholarName: string;
      analysis: AnalysisResult | null;
      lang?: string | null;
    }): Promise<HaiyouScoreReport> => {
      const ctx: ScoringContext = {
        scholarName: input.scholarName,
        analysis: input.analysis,
        lang: asLang(input.lang),
      };

      // Score all dimensions concurrently — Workers AI handles parallel inference,
      // so wall time is ~one call instead of the sum.
      const dims: DimensionScore[] = await Promise.all(
        DIMENSIONS.map((spec) => scoreDimension(ai, spec, ctx))
      );

      const total = Math.round(dims.reduce((s, d) => s + d.score, 0) * 10) / 10;
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
          hasCvText: false,
          hasReturnPlan: false,
          representativePaperCount: 0,
        },
      };
    },
    {
      name: "assess_impact",
      description:
        "Score a scholar's academic impact PURELY from their own work's citation footprint (top-cited citers, citing institutions, notable citers, research directions, top venues) across five dimensions (15+30+20+20+15=100). No CV or self-reported inputs.",
      schema: z.object({
        scholarName: z.string().default(""),
        analysis: z.any().nullable(),
        lang: z.string().nullable().optional(),
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
    lang: req.lang ?? "en",
  })) as HaiyouScoreReport;
  report.scholarId = req.scholarId;
  return report;
}

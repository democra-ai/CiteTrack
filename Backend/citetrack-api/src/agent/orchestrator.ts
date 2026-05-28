import type { D1Database } from "@cloudflare/workers-types";
import type { StructuredTool } from "@langchain/core/tools";
import type {
  Env,
  AnalysisResult,
  AnalyzeRequest,
  HaiyouScoreRequest,
} from "../types";
import {
  clearScholarCitingData,
  createJob,
  getLatestAnalysisResult,
  insertCitingPapers,
  saveHaiyouScore,
  updateJob,
  upsertPublications,
  upsertScholar,
} from "../db/queries";
import { runEnrichment } from "./enrichment_pipeline";
import { makeClusterTopicsTool } from "./tools/cluster_topics";
import { makeRankTopCitedTool } from "./tools/rank_top_cited";
import { makeExtractInstitutionsTool } from "./tools/extract_institutions";
import { makeFindNotableScholarsTool } from "./tools/find_notable_scholars";
import { runHaiyouScoring } from "./scoring/haiyou";

export async function startAnalysisJob(
  env: Env,
  req: AnalyzeRequest
): Promise<string> {
  await upsertScholar(env.DB, {
    id: req.scholarId,
    name: req.scholarName,
    affiliation: req.scholarAffiliation ?? null,
  });
  await upsertPublications(env.DB, req.scholarId, req.publications);
  await clearScholarCitingData(env.DB, req.scholarId);
  await insertCitingPapers(env.DB, req.scholarId, req.citingPapers);
  return createJob(env.DB, req.scholarId, req.citingPapers.length);
}

export async function startHaiyouScoreJob(
  env: Env,
  req: HaiyouScoreRequest
): Promise<string> {
  // Ensure the scholar row exists — haiyou_scores has an FK to scholars(id).
  // The user may open 海优 scoring for a scholar that hasn't been analyzed yet
  // (or whose row was cleared), so upsert defensively before any score insert.
  await upsertScholar(env.DB, {
    id: req.scholarId,
    name: req.scholarName ?? req.scholarId,
    affiliation: null,
  });
  return createJob(env.DB, req.scholarId, 0, "haiyou");
}

export async function runHaiyouScoreJob(
  env: Env,
  jobId: string,
  req: HaiyouScoreRequest
): Promise<void> {
  const tStart = Date.now();
  try {
    await updateJob(env.DB, jobId, {
      status: "running",
      started: true,
      progress: 10,
      currentStep: "loading analysis",
    });

    const analysis = (await getLatestAnalysisResult(
      env.DB,
      req.scholarId
    )) as AnalysisResult | null;

    await updateJob(env.DB, jobId, {
      progress: 25,
      currentStep: "scoring 5 dimensions",
    });

    const report = await runHaiyouScoring(env.AI, { ...req, analysis });

    await saveHaiyouScore(
      env.DB,
      req.scholarId,
      report.totalScore,
      report.fundingPrediction,
      JSON.stringify(report)
    );

    await updateJob(env.DB, jobId, {
      status: "done",
      progress: 100,
      currentStep: "done",
      completed: true,
      resultJson: JSON.stringify({
        report,
        totalMs: Date.now() - tStart,
      }),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await updateJob(env.DB, jobId, {
      status: "error",
      error: msg,
      currentStep: "failed",
      completed: true,
      resultJson: JSON.stringify({ error: msg }),
    });
  }
}

interface ToolCallTrace {
  name: string;
  ok: boolean;
  durationMs: number;
  itemCount: number;
  error?: string;
}

async function invokeTool<T>(
  t: StructuredTool,
  input: Record<string, unknown>,
  trace: ToolCallTrace[]
): Promise<T> {
  const t0 = Date.now();
  try {
    const out = (await t.invoke(input)) as T;
    const count = Array.isArray(out) ? out.length : 0;
    trace.push({ name: t.name, ok: true, durationMs: Date.now() - t0, itemCount: count });
    return out;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    trace.push({
      name: t.name,
      ok: false,
      durationMs: Date.now() - t0,
      itemCount: 0,
      error: msg,
    });
    throw e;
  }
}

export async function runAnalysisJob(env: Env, jobId: string, req: AnalyzeRequest): Promise<void> {
  const tStart = Date.now();
  const trace: ToolCallTrace[] = [];

  const setStep = async (step: string, pct: number) => {
    await updateJob(env.DB, jobId, { currentStep: step, progress: pct });
  };

  try {
    await updateJob(env.DB, jobId, { status: "running", started: true, progress: 5, currentStep: "enriching" });

    const enrichSummary = await runEnrichment(
      env.DB,
      req.scholarId,
      env.OPENALEX_MAILTO,
      env.CACHE,
      req.enrichedCitingPapers ?? null,
      async (msg, pct) => {
        await setStep(msg, pct);
      }
    );

    await setStep("clustering topics", 65);
    const clusterTool = makeClusterTopicsTool(
      env.DB,
      env.AI,
      req.scholarId,
      req.scholarName,
      req.scholarAffiliation ?? null
    );
    const directions = await invokeTool<AnalysisResult["researchDirections"]>(
      clusterTool,
      { maxClusters: 7 },
      trace
    );

    await setStep("ranking top-cited papers", 80);
    const rankTool = makeRankTopCitedTool(env.DB, req.scholarId);
    const topCited = await invokeTool<AnalysisResult["topCitedPapers"]>(
      rankTool,
      { topN: 15 },
      trace
    );

    await setStep("aggregating institutions", 88);
    const instTool = makeExtractInstitutionsTool(env.DB, req.scholarId);
    const institutions = await invokeTool<AnalysisResult["citingInstitutions"]>(
      instTool,
      { topN: 20 },
      trace
    );

    await setStep("finding notable citers", 95);
    const notableTool = makeFindNotableScholarsTool(env.DB, req.scholarId);
    const notableCiters = await invokeTool<AnalysisResult["notableCiters"]>(
      notableTool,
      { hIndexThreshold: 30, topN: 25 },
      trace
    );

    const result: AnalysisResult = {
      scholarId: req.scholarId,
      generatedAt: Date.now(),
      citingPapersCount: req.citingPapers.length,
      enrichedPapersCount: enrichSummary.enrichedCount,
      researchDirections: directions,
      topCitedPapers: topCited,
      citingInstitutions: institutions,
      notableCiters,
    };

    await updateJob(env.DB, jobId, {
      status: "done",
      progress: 100,
      currentStep: "done",
      completed: true,
      resultJson: JSON.stringify({ result, trace, totalMs: Date.now() - tStart }),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await updateJob(env.DB, jobId, {
      status: "error",
      error: msg,
      currentStep: "failed",
      completed: true,
      resultJson: JSON.stringify({ trace, error: msg }),
    });
  }
}

import { Hono } from "hono";
import type { Context } from "hono";
import { z } from "zod";
import type { Env, AnalyzeRequest, HaiyouScoreRequest } from "../types";
import {
  runAnalysisJob,
  runHaiyouScoreJob,
  startAnalysisJob,
  startHaiyouScoreJob,
} from "../agent/orchestrator";
import {
  cancelJob,
  deleteScholarAnalysis,
  getJob,
  getLatestHaiyouScore,
  getLatestJobResult,
} from "../db/queries";

const citingPaperSchema = z.object({
  id: z.string().min(1).max(128),
  title: z.string().min(1).max(2048),
  authors: z.array(z.string().max(256)).max(50).default([]),
  year: z.number().int().nullable().optional(),
  venue: z.string().max(256).nullable().optional(),
  citationCount: z.number().int().nullable().optional(),
  abstract: z.string().max(8192).nullable().optional(),
  scholarUrl: z.string().max(2048).nullable().optional(),
  pdfUrl: z.string().max(2048).nullable().optional(),
});

const enrichedInstitutionSchema = z.object({
  openalexId: z.string().max(256).nullable().optional(),
  rorId: z.string().max(64).nullable().optional(),
  displayName: z.string().min(1).max(512),
  countryCode: z.string().max(8).nullable().optional(),
  type: z.string().max(64).nullable().optional(),
});

const enrichedAuthorSchema = z.object({
  displayName: z.string().min(1).max(256),
  openalexId: z.string().max(256).nullable().optional(),
  orcid: z.string().max(64).nullable().optional(),
  hIndex: z.number().int().nullable().optional(),
  citedByCount: z.number().int().nullable().optional(),
  worksCount: z.number().int().nullable().optional(),
  institutions: z.array(enrichedInstitutionSchema).max(10).default([]),
});

const enrichedCitingPaperSchema = z.object({
  id: z.string().min(1).max(128),
  openalexWorkId: z.string().max(256).nullable().optional(),
  abstract: z.string().max(16384).nullable().optional(),
  citationCount: z.number().int().nullable().optional(),
  authors: z.array(enrichedAuthorSchema).max(100).default([]),
});

const analyzeBody = z.object({
  scholarId: z.string().min(1).max(128),
  scholarName: z.string().min(1).max(256),
  scholarAffiliation: z.string().max(512).nullable().optional(),
  publications: z
    .array(
      z.object({
        id: z.string().max(128),
        title: z.string().max(2048),
        year: z.number().int().nullable().optional(),
        citationCount: z.number().int().nullable().optional(),
      })
    )
    .max(500)
    .default([]),
  citingPapers: z.array(citingPaperSchema).min(1).max(2000),
  enrichedCitingPapers: z.array(enrichedCitingPaperSchema).max(2000).optional(),
});

export function makeAnalyzeRouter() {
  const app = new Hono<{ Bindings: Env }>();

  app.post("/v1/analyze", async (c: Context<{ Bindings: Env }>) => {
    let parsedBody: AnalyzeRequest;
    try {
      const raw = await c.req.json();
      const result = analyzeBody.safeParse(raw);
      if (!result.success) {
        return c.json({ error: "validation_error", issues: result.error.flatten() }, 400);
      }
      parsedBody = {
        scholarId: result.data.scholarId,
        scholarName: result.data.scholarName,
        scholarAffiliation: result.data.scholarAffiliation ?? null,
        publications: result.data.publications.map((p) => ({
          id: p.id,
          title: p.title,
          year: p.year ?? null,
          citationCount: p.citationCount ?? null,
        })),
        citingPapers: result.data.citingPapers.map((p) => ({
          id: p.id,
          title: p.title,
          authors: p.authors,
          year: p.year ?? null,
          venue: p.venue ?? null,
          citationCount: p.citationCount ?? null,
          abstract: p.abstract ?? null,
          scholarUrl: p.scholarUrl ?? null,
          pdfUrl: p.pdfUrl ?? null,
        })),
        enrichedCitingPapers: result.data.enrichedCitingPapers?.map((e) => ({
          id: e.id,
          openalexWorkId: e.openalexWorkId ?? null,
          abstract: e.abstract ?? null,
          citationCount: e.citationCount ?? null,
          authors: e.authors.map((a) => ({
            displayName: a.displayName,
            openalexId: a.openalexId ?? null,
            orcid: a.orcid ?? null,
            hIndex: a.hIndex ?? null,
            citedByCount: a.citedByCount ?? null,
            worksCount: a.worksCount ?? null,
            institutions: a.institutions.map((i) => ({
              openalexId: i.openalexId ?? null,
              rorId: i.rorId ?? null,
              displayName: i.displayName,
              countryCode: i.countryCode ?? null,
              type: i.type ?? null,
            })),
          })),
        })),
      };
    } catch (e) {
      return c.json({ error: "bad_json", detail: String(e) }, 400);
    }

    const jobId = await startAnalysisJob(c.env, parsedBody);

    c.executionCtx.waitUntil(runAnalysisJob(c.env, jobId, parsedBody));

    return c.json({ jobId, status: "pending" }, 202);
  });

  app.get("/v1/jobs/:id", async (c: Context<{ Bindings: Env }>) => {
    const id = c.req.param("id");
    if (!id) return c.json({ error: "missing_id" }, 400);
    const job = await getJob(c.env.DB, id);
    if (!job) return c.json({ error: "not_found" }, 404);
    return c.json(job);
  });

  app.get("/v1/scholars/:id/analysis", async (c: Context<{ Bindings: Env }>) => {
    const id = c.req.param("id");
    if (!id) return c.json({ error: "missing_id" }, 400);
    const latest = await getLatestJobResult(c.env.DB, id);
    if (!latest) return c.json({ error: "not_found" }, 404);
    return new Response(latest.resultJson, {
      status: 200,
      headers: { "content-type": "application/json", "x-completed-at": String(latest.completedAt) },
    });
  });

  // Delete all analysis + score data for a scholar.
  app.delete("/v1/scholars/:id/analysis", async (c: Context<{ Bindings: Env }>) => {
    const id = c.req.param("id");
    if (!id) return c.json({ error: "missing_id" }, 400);
    await deleteScholarAnalysis(c.env.DB, id);
    return c.json({ ok: true, deleted: id });
  });

  // Cancel a running/pending job.
  app.post("/v1/jobs/:id/cancel", async (c: Context<{ Bindings: Env }>) => {
    const id = c.req.param("id");
    if (!id) return c.json({ error: "missing_id" }, 400);
    const cancelled = await cancelJob(c.env.DB, id);
    return c.json({ ok: true, cancelled });
  });

  // ---- 海优 simulated scoring ----

  const repPaperSchema = z.object({
    title: z.string().min(1).max(2048),
    year: z.number().int().nullable().optional(),
    authorRole: z.string().max(64).nullable().optional(),
    journal: z.string().max(256).nullable().optional(),
    impactFactor: z.number().nullable().optional(),
    citationCount: z.number().int().nullable().optional(),
    esiHighlyCited: z.boolean().nullable().optional(),
  });

  const haiyouBody = z.object({
    scholarName: z.string().max(256).nullable().optional(),
    cvText: z.string().max(20000).nullable().optional(),
    returnPlanText: z.string().max(20000).nullable().optional(),
    representativePapers: z.array(repPaperSchema).max(20).optional(),
  });

  app.post(
    "/v1/scholars/:id/haiyou-score",
    async (c: Context<{ Bindings: Env }>) => {
      const id = c.req.param("id");
      if (!id) return c.json({ error: "missing_id" }, 400);
      let body: z.infer<typeof haiyouBody> = {};
      try {
        const raw = await c.req.json().catch(() => ({}));
        const parsed = haiyouBody.safeParse(raw ?? {});
        if (!parsed.success) {
          return c.json(
            { error: "validation_error", issues: parsed.error.flatten() },
            400
          );
        }
        body = parsed.data;
      } catch (e) {
        return c.json({ error: "bad_json", detail: String(e) }, 400);
      }

      const req: HaiyouScoreRequest = {
        scholarId: id,
        scholarName: body.scholarName ?? null,
        cvText: body.cvText ?? null,
        returnPlanText: body.returnPlanText ?? null,
        representativePapers: (body.representativePapers ?? []).map((p) => ({
          title: p.title,
          year: p.year ?? null,
          authorRole: p.authorRole ?? null,
          journal: p.journal ?? null,
          impactFactor: p.impactFactor ?? null,
          citationCount: p.citationCount ?? null,
          esiHighlyCited: p.esiHighlyCited ?? null,
        })),
      };

      const jobId = await startHaiyouScoreJob(c.env, req);
      c.executionCtx.waitUntil(runHaiyouScoreJob(c.env, jobId, req));
      return c.json({ jobId, status: "pending" }, 202);
    }
  );

  app.get(
    "/v1/scholars/:id/haiyou-score",
    async (c: Context<{ Bindings: Env }>) => {
      const id = c.req.param("id");
      if (!id) return c.json({ error: "missing_id" }, 400);
      const latest = await getLatestHaiyouScore(c.env.DB, id);
      if (!latest) return c.json({ error: "not_found" }, 404);
      return new Response(latest.reportJson, {
        status: 200,
        headers: {
          "content-type": "application/json",
          "x-created-at": String(latest.createdAt),
        },
      });
    }
  );

  return app;
}

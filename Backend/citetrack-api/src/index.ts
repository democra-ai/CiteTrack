import { Hono } from "hono";
import type { Env } from "./types";
import { cfAccess } from "./auth";
import { makeAnalyzeRouter } from "./routes/analyze";

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.json({ service: "citetrack-api", version: "0.1.0" }));
app.get("/v1/health", (c) =>
  c.json({
    ok: true,
    ts: Date.now(),
    hasDB: Boolean(c.env.DB),
    hasAI: Boolean(c.env.AI),
    hasCache: Boolean(c.env.CACHE),
  })
);

app.use("/v1/analyze", cfAccess);
app.use("/v1/jobs/*", cfAccess);
app.use("/v1/scholars/*", cfAccess);

app.route("/", makeAnalyzeRouter());

app.onError((err, c) => {
  console.error("Worker error:", err);
  return c.json({ error: "internal", detail: err.message }, 500);
});

app.notFound((c) => c.json({ error: "not_found", path: c.req.path }, 404));

export default app;

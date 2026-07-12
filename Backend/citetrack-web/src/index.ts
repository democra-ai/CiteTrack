import { Hono } from "hono";
import { cors } from "hono/cors";
import { EmailMessage } from "cloudflare:email";
import { createMimeMessage } from "mimetext/browser";

interface Env {
  ASSETS: Fetcher;
  EMAIL?: SendEmail; // Cloudflare Email Routing send binding
  EMAIL_FROM: string;
  FEEDBACK_TO: string;
  RESEND_API_KEY?: string;
}

const app = new Hono<{ Bindings: Env }>();

// Feedback is posted from the website AND from inside the iOS/macOS app, so allow
// any origin (it carries no credentials — just a message).
app.use("/api/*", cors({ origin: "*", allowMethods: ["POST", "OPTIONS"], allowHeaders: ["Content-Type"] }));

const EMAIL_RE = /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/;
const clip = (s: unknown, n: number) => (typeof s === "string" ? s.trim().slice(0, n) : "");

app.get("/api/health", (c) =>
  c.json({ ok: true, service: "citetrack-web", email: Boolean(c.env.RESEND_API_KEY || c.env.EMAIL) }),
);

app.post("/api/feedback", async (c) => {
  try {
    return await handleFeedback(c);
  } catch (e) {
    return c.json({ error: `feedback failed: ${e instanceof Error ? e.message : String(e)}` }, 502);
  }
});

async function handleFeedback(c: Parameters<Parameters<typeof app.post>[1]>[0]) {
  const body = await c.req.json().catch(() => ({} as Record<string, unknown>));
  const message = clip(body.message, 5000);
  if (message.length < 2) return c.json({ error: "message is required" }, 400);

  const email = clip(body.email, 200); // optional — so the user can be replied to
  const from = clip(body.from, 40) || "unknown"; // "website" | "ios" | "macos"
  const appVersion = clip(body.appVersion, 40);
  const platform = clip(body.platform, 60);
  const category = clip(body.category, 40); // bug | idea | other

  const subject = `CiteTrack feedback${category ? ` · ${category}` : ""} (${from})`;
  const lines = [
    message,
    "",
    "———",
    `From: ${from}${platform ? ` · ${platform}` : ""}${appVersion ? ` · v${appVersion}` : ""}`,
    email ? `Reply-to: ${email}` : "Reply-to: (not provided)",
    `Received: ${new Date().toISOString()}`,
  ];
  const text = lines.join("\n");
  const replyTo = EMAIL_RE.test(email) ? email : undefined;

  const res = await sendFeedback(c.env, { subject, text, replyTo });
  if (!res.ok) return c.json({ error: res.error }, 502);
  return c.json({ ok: true });
}

app.notFound((c) =>
  c.req.path.startsWith("/api/") ? c.json({ error: "not found" }, 404) : c.env.ASSETS.fetch(c.req.raw),
);

type SendResult = { ok: true } | { ok: false; error: string };

async function sendFeedback(
  env: Env,
  args: { subject: string; text: string; replyTo?: string },
): Promise<SendResult> {
  const from = (env.EMAIL_FROM ?? "").trim();
  const to = (env.FEEDBACK_TO ?? "").trim();
  if (!EMAIL_RE.test(from) || !EMAIL_RE.test(to)) return { ok: false, error: "email not configured" };

  // Resend (any recipient) when a key is present; otherwise Cloudflare Email Routing.
  if (env.RESEND_API_KEY) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: `CiteTrack Feedback <${from}>`,
        to,
        subject: args.subject,
        text: args.text,
        ...(args.replyTo ? { reply_to: args.replyTo } : {}),
      }),
    });
    if (!r.ok) return { ok: false, error: `resend: ${r.status}` };
    return { ok: true };
  }

  if (!env.EMAIL) return { ok: false, error: "no email backend" };
  const msg = createMimeMessage();
  msg.setSender({ name: "CiteTrack Feedback", addr: from });
  msg.setRecipient(to);
  msg.setSubject(args.subject);
  // Reply-To as a raw string isn't accepted by the Email Routing MIME builder;
  // the submitter's email is already in the body (`Reply-to: …`). Resend uses
  // its own `reply_to` field above, so nothing is lost there.
  msg.addMessage({ contentType: "text/plain", data: args.text });
  try {
    await env.EMAIL.send(new EmailMessage(from, to, msg.asRaw()));
    return { ok: true };
  } catch (e) {
    return { ok: false, error: `email_routing: ${e instanceof Error ? e.message : String(e)}` };
  }
}

export default app;

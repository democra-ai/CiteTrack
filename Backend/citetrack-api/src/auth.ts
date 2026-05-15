import type { Context, Next } from "hono";
import type { Env } from "./types";

interface JwtHeader {
  kid: string;
  alg: string;
}

interface JwtPayload {
  iss: string;
  aud: string | string[];
  exp: number;
  email?: string;
  identity_nonce?: string;
  [k: string]: unknown;
}

interface CFAccessKey {
  kid: string;
  kty: string;
  alg: string;
  use: string;
  e: string;
  n: string;
}

const KEY_CACHE = new Map<string, { keys: CFAccessKey[]; fetchedAt: number }>();
const KEY_TTL_MS = 60 * 60 * 1000;

function b64urlToBuffer(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(padded);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}

async function fetchAccessKeys(teamDomain: string): Promise<CFAccessKey[]> {
  const cached = KEY_CACHE.get(teamDomain);
  if (cached && Date.now() - cached.fetchedAt < KEY_TTL_MS) return cached.keys;
  const resp = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`);
  if (!resp.ok) throw new Error(`Failed to fetch Access keys: ${resp.status}`);
  const data = (await resp.json()) as { keys: CFAccessKey[] };
  KEY_CACHE.set(teamDomain, { keys: data.keys, fetchedAt: Date.now() });
  return data.keys;
}

async function importRSAKey(jwk: CFAccessKey): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, e: jwk.e, n: jwk.n, alg: jwk.alg, ext: true } as JsonWebKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

async function verifyJWT(
  token: string,
  teamDomain: string,
  allowedAuds: string[]
): Promise<JwtPayload> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Malformed JWT");
  const headerStr = new TextDecoder().decode(b64urlToBuffer(parts[0]));
  const payloadStr = new TextDecoder().decode(b64urlToBuffer(parts[1]));
  const sig = b64urlToBuffer(parts[2]);
  const header = JSON.parse(headerStr) as JwtHeader;
  const payload = JSON.parse(payloadStr) as JwtPayload;
  if (header.alg !== "RS256") throw new Error("Unsupported JWT alg");
  if (payload.exp * 1000 < Date.now()) throw new Error("JWT expired");
  if (allowedAuds.length > 0) {
    const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
    if (!auds.some((a) => allowedAuds.includes(a))) {
      throw new Error("JWT aud mismatch");
    }
  }
  const keys = await fetchAccessKeys(teamDomain);
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("JWT kid not found in JWKS");
  const key = await importRSAKey(jwk);
  const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, sig, data);
  if (!ok) throw new Error("JWT signature invalid");
  return payload;
}

export async function cfAccess(c: Context<{ Bindings: Env; Variables: { user: JwtPayload } }>, next: Next) {
  const auds = c.env.ALLOWED_ACCESS_AUDS.split(",").map((s) => s.trim()).filter(Boolean);
  const domains = c.env.ALLOWED_ACCESS_DOMAINS.split(",").map((s) => s.trim()).filter(Boolean);

  if (auds.length === 0 || domains.length === 0) {
    return c.json(
      { error: "auth_not_configured", detail: "Set ALLOWED_ACCESS_AUDS and ALLOWED_ACCESS_DOMAINS" },
      503
    );
  }

  const jwt = c.req.header("cf-access-jwt-assertion") ?? c.req.header("Cf-Access-Jwt-Assertion");
  if (!jwt) return c.json({ error: "missing_access_jwt" }, 401);

  for (const domain of domains) {
    try {
      const payload = await verifyJWT(jwt, domain, auds);
      c.set("user", payload);
      return next();
    } catch {
      continue;
    }
  }
  return c.json({ error: "invalid_access_jwt" }, 401);
}

// OpenAlex client. Free, no auth required, but a "polite pool" mailto query param
// gives faster and more consistent service.
// Docs: https://docs.openalex.org/
import type { KVNamespace } from "@cloudflare/workers-types";

const BASE = "https://api.openalex.org";
const MAX_PER_PAGE = 200;
const FETCH_TIMEOUT_MS = 12000;
const CACHE_TTL_WORK_SEC = 60 * 60 * 24 * 30;
const CACHE_TTL_AUTHOR_SEC = 60 * 60 * 24 * 7;

interface OpenAlexInstitution {
  id: string;
  display_name: string;
  ror?: string;
  country_code?: string;
  type?: string;
}

interface OpenAlexAuthorship {
  author: {
    id?: string;
    display_name: string;
    orcid?: string;
  };
  institutions?: OpenAlexInstitution[];
}

export interface OpenAlexWork {
  id: string;
  title: string;
  publication_year: number | null;
  cited_by_count: number;
  authorships: OpenAlexAuthorship[];
  primary_location?: { source?: { display_name?: string } };
  abstract_inverted_index?: Record<string, number[]>;
}

export interface OpenAlexAuthor {
  id: string;
  display_name: string;
  orcid: string | null;
  works_count: number;
  cited_by_count: number;
  summary_stats: {
    h_index: number;
    i10_index: number;
  };
  last_known_institutions: OpenAlexInstitution[];
}

async function digestKey(prefix: string, parts: (string | number | null | undefined)[]): Promise<string> {
  const joined = parts.map((p) => String(p ?? "")).join("|").toLowerCase();
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(joined));
  const hex = Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `${prefix}:${hex.slice(0, 24)}`;
}

export class OpenAlexClient {
  constructor(
    private mailto: string,
    private cache: KVNamespace | null = null
  ) {}

  private buildUrl(path: string, params: Record<string, string | number> = {}): string {
    const url = new URL(`${BASE}${path}`);
    url.searchParams.set("mailto", this.mailto);
    for (const [k, v] of Object.entries(params)) {
      url.searchParams.set(k, String(v));
    }
    return url.toString();
  }

  async fetchJSON<T>(url: string, attempt = 0): Promise<T | null> {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
      const resp = await fetch(url, {
        headers: {
          "User-Agent": `Mozilla/5.0 CiteTrack/1.0 (mailto:${this.mailto})`,
          Accept: "application/json",
        },
        signal: controller.signal,
      });
      clearTimeout(timer);
      if ((resp.status === 429 || resp.status === 503) && attempt < 2) {
        const wait = 1500 * Math.pow(2, attempt);
        console.warn(`[openalex] ${resp.status}, waiting ${wait}ms then retry #${attempt + 1}`);
        await new Promise((r) => setTimeout(r, wait));
        return this.fetchJSON<T>(url, attempt + 1);
      }
      if (resp.status === 429) {
        console.warn(`[openalex] giving up after 429 retries on ${url.slice(0, 120)}`);
      }
      if (resp.status >= 500 && attempt < 2) {
        await new Promise((r) => setTimeout(r, 800));
        return this.fetchJSON<T>(url, attempt + 1);
      }
      if (!resp.ok) {
        console.error(`[openalex] HTTP ${resp.status} for ${url.slice(0, 200)}`);
        return null;
      }
      return (await resp.json()) as T;
    } catch (e) {
      console.error(`[openalex] fetch failed for ${url.slice(0, 200)}:`, e instanceof Error ? e.message : String(e));
      return null;
    }
  }

  async searchWorkByTitle(title: string, year: number | null): Promise<OpenAlexWork | null> {
    const trimmed = title.trim().slice(0, 200);
    if (!trimmed) return null;

    const cacheKey = this.cache ? await digestKey("oa:work", [trimmed, year]) : null;
    if (cacheKey && this.cache) {
      const cached = await this.cache.get(cacheKey, { type: "json" });
      if (cached && typeof cached === "object" && "id" in cached && "authorships" in cached) {
        return cached as OpenAlexWork;
      }
    }

    const params: Record<string, string | number> = {
      search: trimmed,
      per_page: 5,
      select:
        "id,title,publication_year,cited_by_count,authorships,primary_location,abstract_inverted_index",
    };
    const url = this.buildUrl("/works", params);
    const data = await this.fetchJSON<{ results: OpenAlexWork[] }>(url);
    if (!data?.results?.length) return null;
    const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    const target = norm(trimmed);
    const targetTokens = new Set(target.split(" ").filter((t) => t.length > 3));
    let best: OpenAlexWork | null = null;
    let bestScore = -1;
    for (const w of data.results) {
      const wt = norm(w.title || "");
      const wTokens = wt.split(" ").filter((t) => t.length > 3);
      let overlap = 0;
      for (const t of wTokens) if (targetTokens.has(t)) overlap++;
      const lengthPenalty = Math.abs(wt.length - target.length) / 100;
      let yearScore = 0;
      if (year && w.publication_year) {
        const diff = Math.abs(w.publication_year - year);
        yearScore = diff <= 1 ? 1.5 : diff <= 3 ? 0.5 : 0;
      }
      const score = overlap - lengthPenalty + yearScore;
      if (score > bestScore) {
        bestScore = score;
        best = w;
      }
    }
    const winner = best ?? data.results[0] ?? null;
    if (cacheKey && this.cache && winner) {
      await this.cache.put(cacheKey, JSON.stringify(winner), { expirationTtl: CACHE_TTL_WORK_SEC });
    }
    return winner;
  }

  async batchSearchWorks(
    inputs: Array<{ id: string; title: string; year: number | null }>,
    concurrency = 1
  ): Promise<Map<string, OpenAlexWork>> {
    const results = new Map<string, OpenAlexWork>();
    let cursor = 0;
    const workers = Array.from({ length: concurrency }, async () => {
      while (cursor < inputs.length) {
        const idx = cursor++;
        const inp = inputs[idx];
        const w = await this.searchWorkByTitle(inp.title, inp.year);
        if (w) results.set(inp.id, w);
        await new Promise((r) => setTimeout(r, 600));
      }
    });
    await Promise.all(workers);
    return results;
  }

  async fetchAuthorById(openalexId: string): Promise<OpenAlexAuthor | null> {
    const id = openalexId.replace(/^https?:\/\/openalex\.org\//, "");
    const cacheKey = this.cache ? await digestKey("oa:author:id", [id]) : null;
    if (cacheKey && this.cache) {
      const cached = await this.cache.get(cacheKey, { type: "json" });
      if (cached && typeof cached === "object" && "id" in cached) {
        return cached as OpenAlexAuthor;
      }
    }
    const url = this.buildUrl(`/authors/${id}`, {
      select:
        "id,display_name,orcid,works_count,cited_by_count,summary_stats,last_known_institutions",
    });
    const a = await this.fetchJSON<OpenAlexAuthor>(url);
    if (cacheKey && this.cache && a) {
      await this.cache.put(cacheKey, JSON.stringify(a), { expirationTtl: CACHE_TTL_AUTHOR_SEC });
    }
    return a;
  }

  async searchAuthorByName(name: string, affiliationHint?: string): Promise<OpenAlexAuthor | null> {
    const q = name.trim().slice(0, 100);
    if (!q) return null;
    const cacheKey = this.cache ? await digestKey("oa:author:name", [q, affiliationHint]) : null;
    if (cacheKey && this.cache) {
      const cached = await this.cache.get(cacheKey, { type: "json" });
      if (cached && typeof cached === "object" && "id" in cached) {
        return cached as OpenAlexAuthor;
      }
    }
    const params: Record<string, string | number> = {
      search: q,
      per_page: 5,
      select:
        "id,display_name,orcid,works_count,cited_by_count,summary_stats,last_known_institutions",
    };
    const url = this.buildUrl("/authors", params);
    const data = await this.fetchJSON<{ results: OpenAlexAuthor[] }>(url);
    let winner: OpenAlexAuthor | null = null;
    if (data?.results?.length) {
      if (affiliationHint) {
        const hint = affiliationHint.toLowerCase();
        winner =
          data.results.find((a) =>
            a.last_known_institutions?.some((i) =>
              (i.display_name || "").toLowerCase().includes(hint)
            )
          ) ?? null;
      }
      if (!winner) winner = data.results[0] ?? null;
    }
    if (cacheKey && this.cache && winner) {
      await this.cache.put(cacheKey, JSON.stringify(winner), { expirationTtl: CACHE_TTL_AUTHOR_SEC });
    }
    return winner;
  }

  async batchFetchAuthors(
    authorRefs: Array<{ key: string; openalexId?: string; name: string; affiliationHint?: string }>,
    concurrency = 1
  ): Promise<Map<string, OpenAlexAuthor>> {
    const results = new Map<string, OpenAlexAuthor>();
    let cursor = 0;
    const workers = Array.from({ length: concurrency }, async () => {
      while (cursor < authorRefs.length) {
        const idx = cursor++;
        const ref = authorRefs[idx];
        let a: OpenAlexAuthor | null = null;
        if (ref.openalexId) a = await this.fetchAuthorById(ref.openalexId);
        if (!a) a = await this.searchAuthorByName(ref.name, ref.affiliationHint);
        if (a) results.set(ref.key, a);
        await new Promise((r) => setTimeout(r, 600));
      }
    });
    await Promise.all(workers);
    return results;
  }
}

export function decodeAbstract(inverted: Record<string, number[]> | undefined): string | null {
  if (!inverted) return null;
  const positions: Array<[number, string]> = [];
  for (const [word, idxs] of Object.entries(inverted)) {
    for (const i of idxs) positions.push([i, word]);
  }
  positions.sort((a, b) => a[0] - b[0]);
  const text = positions.map(([, w]) => w).join(" ").trim();
  return text.length > 0 ? text : null;
}

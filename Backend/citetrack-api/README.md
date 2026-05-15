# citetrack-api

Cloudflare Worker that powers the **AI Analysis** section of the CiteTrack
iOS/Mac app's Insight page. Given a scholar and their citing papers, it runs a
LangChain agent with four tools and returns:

1. **Research directions** — embedding + k-means clustering, LLM-labelled
2. **Top-cited citers** — papers that cite this scholar ranked by their own
   citation count
3. **Citing institutions** — aggregated from OpenAlex author affiliations
4. **Notable citers** — citers whose own h-index ≥ 30

## Stack

| Layer | Choice |
|---|---|
| Runtime | Cloudflare Workers (TypeScript + Hono) |
| Storage | D1 (`citetrack-analysis`) + KV (`CITETRACK_CACHE`) |
| LLM | Workers AI — `@cf/meta/llama-3.3-70b-instruct-fp8-fast` |
| Embeddings | Workers AI — `@cf/baai/bge-base-en-v1.5` |
| Agent | LangChain.js `tool()` primitives, manual sequenced execution |
| Auth | Cloudflare Access (Service Auth / `non_identity` policy) |
| Custom domain | `https://citetrack-api.democra.ai` |

## Layout

```
src/
├── index.ts                   # Hono app, route mounting, error handling
├── auth.ts                    # CF Access JWT validation middleware
├── types.ts                   # Worker types (Env, AnalyzeRequest, AnalysisResult…)
├── routes/
│   └── analyze.ts             # POST /v1/analyze, GET /v1/jobs/:id, GET /v1/scholars/:id/analysis
├── agent/
│   ├── orchestrator.ts        # startAnalysisJob / runAnalysisJob — assembles the 4 tools
│   ├── enrichment_pipeline.ts # OpenAlex enrichment (server-side) + client-enriched fast path
│   └── tools/
│       ├── cluster_topics.ts      # embed → k-means → LLM label each cluster
│       ├── rank_top_cited.ts      # SQL aggregation on citing_papers
│       ├── extract_institutions.ts # SQL aggregation on author_institutions
│       └── find_notable_scholars.ts # SQL filter on h_index threshold
├── enrichment/
│   ├── openalex.ts            # OpenAlex client (with KV cache, retry/backoff)
│   └── embeddings.ts          # Workers AI embed wrapper
├── db/
│   └── queries.ts             # All D1 queries
└── lib/
    └── kmeans.ts              # Pure-JS k-means + heuristic K picker
migrations/
├── 0001_init.sql              # Initial schema (9 tables)
└── 0002_composite_keys.sql    # Per-scholar composite PK for citing_papers / paper_authors
```

## API

All endpoints require Cloudflare Access; send the service-token headers
`CF-Access-Client-Id` and `CF-Access-Client-Secret`.

### `POST /v1/analyze`
Submit a fresh analysis. Returns `{jobId, status:"pending"}` (HTTP 202).

Body:
```jsonc
{
  "scholarId": "...",
  "scholarName": "Yann LeCun",
  "scholarAffiliation": "New York University",   // optional
  "publications": [
    {"id": "p1", "title": "...", "year": 1998, "citationCount": 50000}
  ],
  "citingPapers": [
    {
      "id": "cp1",
      "title": "Attention is all you need",
      "authors": ["Ashish Vaswani", "Noam Shazeer"],
      "year": 2017,
      "venue": "NeurIPS",
      "citationCount": 80000,
      "abstract": "Transformer architecture…",
      "scholarUrl": null,
      "pdfUrl": null
    }
  ],
  // Optional. If the client already enriched these papers via OpenAlex
  // (e.g. iOS calls OpenAlex from the user's IP to bypass CF egress rate-limits),
  // pass the enriched data here and the worker skips its own OpenAlex calls.
  "enrichedCitingPapers": [
    {
      "id": "cp1",
      "openalexWorkId": "https://openalex.org/W2626778328",
      "abstract": "…",
      "citationCount": 95000,
      "authors": [
        {
          "displayName": "Ashish Vaswani",
          "openalexId": "https://openalex.org/A5066316077",
          "hIndex": 56,
          "citedByCount": 180000,
          "worksCount": 80,
          "institutions": [
            {"openalexId": "...", "displayName": "Google", "countryCode": "US", "type": "company"}
          ]
        }
      ]
    }
  ]
}
```

### `GET /v1/jobs/:id`
Poll for job status. Returns `{id, scholarId, status, progress, currentStep, error, citingPapersCount, createdAt, startedAt, completedAt}` where `status` is one of `pending|running|done|error`.

### `GET /v1/scholars/:id/analysis`
Returns the most recent completed `AnalysisResult` for a scholar:
```jsonc
{
  "result": {
    "scholarId": "...",
    "generatedAt": 1778864199459,
    "citingPapersCount": 4,
    "enrichedPapersCount": 4,
    "researchDirections": [
      { "clusterIndex": 0, "label": "Deep Learning", "keywords": [...], "paperCount": 2, "examplePapers": [...] }
    ],
    "topCitedPapers": [{"id": "...", "title": "...", "citationCount": 150000, ...}],
    "citingInstitutions": [{"id": "...", "name": "Google", "country": "US", "paperCount": 1, "uniqueAuthorCount": 2}],
    "notableCiters": [{"id": "...", "name": "Kaiming He", "hIndex": 95, ...}]
  },
  "trace": [...],
  "totalMs": 2581
}
```

### `GET /v1/health`
Public no-auth health check.

## Operations

### Deploy
```sh
cd Backend/citetrack-api
cfman wrangler --account claude-citetrack-deploy deploy
```

### Apply schema migrations
```sh
cfman wrangler --account claude-citetrack-deploy d1 execute citetrack-analysis --remote --file=./migrations/0001_init.sql
cfman wrangler --account claude-citetrack-deploy d1 execute citetrack-analysis --remote --file=./migrations/0002_composite_keys.sql
```

### Tail logs
```sh
cfman wrangler --account claude-citetrack-deploy tail --format=pretty
```

### Manual smoke test
```sh
CID="3b36fc5799f14e56ba31315c5d43bbfa.access"
CSEC="b8ce177a80ab4c2a4190d8b23655a92e8a008d1a8d9a5448ae4320b973290b73"
curl -s -H "CF-Access-Client-Id: $CID" -H "CF-Access-Client-Secret: $CSEC" \
  https://citetrack-api.democra.ai/v1/health
```

### Rotate the service token
1. CF Dash → Zero Trust → Access → Service Auth → create a fresh token.
2. Update the Access policy on the `CiteTrack API` app to include the new token id.
3. Replace defaults in [`Shared/Services/CiteTrackAPIConfig.swift`](../../Shared/Services/CiteTrackAPIConfig.swift) and ship a new iOS build.
4. Once verified, remove the old token from CF.

## Cloudflare resource inventory

| Resource | Identifier |
|---|---|
| Account | `41ebb4f61f901310c3acf958bbf08e4d` (tauon.sh@gmail.com) |
| Worker | `citetrack-api` |
| D1 | `citetrack-analysis` (`ba095c54-3b6e-4dd9-a5c1-1336e7280167`) |
| KV | `CITETRACK_CACHE` (`ab66d02ceda742bfbe92af5a86f612b4`) |
| Custom domain | `citetrack-api.democra.ai` |
| Access app | `1d233202-9cda-40c2-ad36-d18253626d80` |
| Access AUD | `e5007772fcf600453254359e85b66999e8b4d47bf0c086f99624d3c22b499d1d` |
| Team domain | `tauon.cloudflareaccess.com` |
| WAF skip rule | `27719236877e4823a90f17d0df75b9aa` (bypass SBFM for `citetrack-api.democra.ai`) |

## Known caveat — OpenAlex rate limiting on CF egress

Cloudflare Workers' egress IP pool is shared with thousands of other CF
customers. OpenAlex aggressively rate-limits this pool — we observed
`Retry-After: 24773s` (6.8 hours!) on the first call.

**The recommended workaround is now the default:** the iOS client enriches
citing papers via OpenAlex from the user's own IP (no shared throttling), then
passes the enriched data through to the worker via `enrichedCitingPapers`. The
worker takes a fast path and skips its own OpenAlex calls in that case.

If you ever need to run server-side enrichment for batch backfills, options:
- Add an OpenAlex Premium API key.
- Wait for KV cache to warm via legitimate usage.
- Front the calls with a small proxy on a dedicated IP.

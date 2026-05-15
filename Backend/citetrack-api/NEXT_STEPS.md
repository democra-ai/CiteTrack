# Next Steps — Install to iPhone

## What's done

- **Worker deployed** at `https://citetrack-api.democra.ai` (4/4 metrics
  verified end-to-end via curl with `enrichedCitingPapers` smoke test;
  2.58 s total time).
- **iOS code written** for `Shared/Services/{CiteTrackAPIConfig,
  CiteTrackAnalysisService, OpenAlexEnrichmentClient}.swift`,
  `Shared/Models/AnalysisResult.swift`, and
  `iOS/CiteTrack/Views/AnalysisInsightsSection.swift`.
- **CitationInsightsView** updated to embed the new section after the summary
  card.
- **Localization** added in `LocalizationManager.swift` for the 18 new
  strings (English + Simplified Chinese).
- All Swift files parse cleanly via `swiftc -parse`.

## What's blocked

`xcodebuild` can't build for either your iPhone 15 Pro Max (iOS 26.4.2) or any
iOS Simulator because **Xcode 26.5 needs the iOS 26.5 platform component
(~8.5 GB) and it isn't installed yet**. The error string is misleading: it
mentions iOS 26.5 even though your phone is on 26.4.2, because Xcode bundles
its own per-version platform package.

A background `xcodebuild -downloadPlatform iOS` is running, but the download
is silent and slow. The reliable path is the GUI.

## Finish the install (3 minutes once Xcode is open)

1. **Open Xcode** (`open /Applications/Xcode.app`).
2. **Xcode → Settings → Components**.
3. Find **iOS 26.5** in the list — click the download arrow next to it. Wait
   for it to finish (8.5 GB).
4. Open `iOS/CiteTrack_iOS.xcodeproj`.
5. Top bar → select destination: **沈弢的iPhone (15 Pro Max)**.
6. Hit **▶ Run** (or `Cmd+R`).

Xcode will sign with your Apple Developer account, install the .app on the
phone, and launch it. The new analysis section appears at the bottom of the
Insight tab once you run an Insights batch fetch.

## If you'd rather drive from the CLI

Once the platform component is installed (check with
`xcodebuild -showdestinations -project iOS/CiteTrack_iOS.xcodeproj -scheme CiteTrack`
— you should see no "iOS 26.5 not installed" errors):

```sh
cd /Users/tao.shen/google_scholar_plugin/iOS
xcodebuild -project CiteTrack_iOS.xcodeproj \
  -scheme CiteTrack \
  -destination 'id=61708F30-C617-5D49-8454-B2C96DEE1404' \
  -configuration Debug \
  -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates \
  -derivedDataPath build/ \
  build

# Install
xcrun devicectl device install app \
  --device 61708F30-C617-5D49-8454-B2C96DEE1404 \
  build/Build/Products/Debug-iphoneos/CiteTrack.app
```

## Manual smoke test of the worker (already verified, just FYI)

```sh
CID="3b36fc5799f14e56ba31315c5d43bbfa.access"
CSEC="b8ce177a80ab4c2a4190d8b23655a92e8a008d1a8d9a5448ae4320b973290b73"
curl -s -H "CF-Access-Client-Id: $CID" -H "CF-Access-Client-Secret: $CSEC" \
  https://citetrack-api.democra.ai/v1/health
# => {"ok":true,"ts":...,"hasDB":true,"hasAI":true,"hasCache":true}
```

## Architecture quick reminder

1. iOS Insight page (`CitationInsightsView`) finishes its existing batch SS
   context fetch → renders `AnalysisInsightsSection` below the summary card.
2. User taps "Run analysis" → `OpenAlexEnrichmentClient` queries OpenAlex
   **from the user's own IP** (bypasses the Cloudflare egress rate-limit
   that crippled server-side OpenAlex calls).
3. `CiteTrackAnalysisService.runAnalysis` POSTs the citing papers +
   `enrichedCitingPapers` to the worker, polls `/v1/jobs/:id` until done,
   fetches `/v1/scholars/:id/analysis`.
4. Worker stores enriched data → runs 4 LangChain tools sequentially
   (cluster_topics, rank_top_cited, extract_institutions,
   find_notable_scholars) → assembles `AnalysisResult` JSON.
5. iOS renders 4 cards: Research Directions / Top-cited Citers /
   Citing Institutions / Notable Citers.

## Leftover

- `iOS/CiteTrack/Views/WhoCiteMeView.swift` has the pre-existing
  cache-first-with-background-refresh refactor that's been in your working
  tree. It's **not** part of this commit; review and commit separately when
  ready.

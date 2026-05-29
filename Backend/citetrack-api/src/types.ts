import type { Ai, D1Database, KVNamespace } from "@cloudflare/workers-types";

export interface Env {
  DB: D1Database;
  CACHE: KVNamespace;
  AI: Ai;
  OPENALEX_MAILTO: string;
  ALLOWED_ACCESS_AUDS: string;
  ALLOWED_ACCESS_DOMAINS: string;
}

export interface CitingPaperInput {
  id: string;
  title: string;
  authors: string[];
  year: number | null;
  venue: string | null;
  citationCount: number | null;
  abstract: string | null;
  scholarUrl: string | null;
  pdfUrl: string | null;
}

export interface EnrichedInstitutionInput {
  openalexId?: string | null;
  rorId?: string | null;
  displayName: string;
  countryCode?: string | null;
  type?: string | null;
}

export interface EnrichedAuthorInput {
  displayName: string;
  openalexId?: string | null;
  orcid?: string | null;
  hIndex?: number | null;
  citedByCount?: number | null;
  worksCount?: number | null;
  institutions: EnrichedInstitutionInput[];
}

export interface EnrichedCitingPaperInput {
  id: string;
  openalexWorkId?: string | null;
  abstract?: string | null;
  citationCount?: number | null;
  authors: EnrichedAuthorInput[];
  /// Venue (journal / conference / repository) from OpenAlex primary_location.source.
  venueName?: string | null;
  venueType?: string | null;
}

export interface AnalyzeRequest {
  scholarId: string;
  scholarName: string;
  scholarAffiliation?: string | null;
  publications: Array<{
    id: string;
    title: string;
    year: number | null;
    citationCount: number | null;
  }>;
  citingPapers: CitingPaperInput[];
  /// Optional: iOS can pre-fetch OpenAlex from the user's own IP (which is not
  /// shared with thousands of CF customers) and pass the enriched data through.
  /// When provided, the worker skips its own OpenAlex calls for these papers.
  enrichedCitingPapers?: EnrichedCitingPaperInput[];
  /// UI language ("en" | "zh"). Research-direction labels/summaries/keywords are
  /// generated in this language so the analysis matches the app's locale.
  lang?: string | null;
}

export type JobStatus = "pending" | "running" | "done" | "error" | "cancelled";

export interface JobRecord {
  id: string;
  scholarId: string;
  status: JobStatus;
  progress: number;
  currentStep: string | null;
  error: string | null;
  citingPapersCount: number;
  createdAt: number;
  startedAt: number | null;
  completedAt: number | null;
}

export interface ResearchDirection {
  clusterIndex: number;
  label: string;
  summary: string;
  keywords: string[];
  paperCount: number;
  examplePapers: Array<{ id: string; title: string }>;
}

export interface TopCitedPaper {
  id: string;
  title: string;
  authors: string[];
  year: number | null;
  venue: string | null;
  citationCount: number;
  scholarUrl: string | null;
}

export interface CitingInstitution {
  id: string;
  name: string;
  country: string | null;
  type: string | null;
  paperCount: number;
  uniqueAuthorCount: number;
}

export interface NotableCiter {
  id: string;
  name: string;
  openalexId: string | null;
  affiliation: string | null;
  hIndex: number | null;
  citedByCount: number | null;
  worksCount: number | null;
  paperCount: number;
  examplePapers: Array<{ id: string; title: string }>;
}

export interface VenueCitingPaper {
  id: string;
  title: string;
  authors: string[];
  year: number | null;
  scholarUrl: string | null;
}

export interface TopVenue {
  name: string;
  type: string | null; // journal | conference | repository | ...
  paperCount: number;
  totalCitations: number;
  papers: VenueCitingPaper[]; // the citing papers from this venue (for drill-down)
}

export interface AnalysisResult {
  scholarId: string;
  generatedAt: number;
  citingPapersCount: number;
  enrichedPapersCount: number;
  researchDirections: ResearchDirection[];
  topCitedPapers: TopCitedPaper[];
  citingInstitutions: CitingInstitution[];
  notableCiters: NotableCiter[];
  topVenues: TopVenue[];
}

// ---- 海优 (Overseas Excellent Young Scientists) simulated scoring ----

export interface RepresentativePaperInput {
  title: string;
  year: number | null;
  authorRole?: string | null; // 唯一一作 / 共同一作 / 唯一通讯 / 同通讯 / 其他
  journal?: string | null;
  impactFactor?: number | null;
  citationCount?: number | null;
  esiHighlyCited?: boolean | null;
}

export interface HaiyouScoreRequest {
  scholarId: string;
  scholarName?: string | null;
  cvText?: string | null; // deprecated — kept for back-compat; ignored by scoring
  returnPlanText?: string | null; // deprecated — kept for back-compat; ignored
  representativePapers?: RepresentativePaperInput[]; // deprecated — ignored
  lang?: string | null; // "en" | "zh" — output language for the impact report
}

export type FundingPrediction = "priority" | "approved" | "rejected";

export interface DimensionScore {
  key: string;
  label: string; // 中文维度名
  maxScore: number;
  score: number;
  confidence: "high" | "medium" | "low";
  reasoning: string;
  evidence: string[];
  suggestions: string[];
}

export interface HaiyouScoreReport {
  scholarId: string;
  generatedAt: number;
  dimensions: DimensionScore[];
  totalScore: number;
  maxTotal: number; // 100
  fundingPrediction: FundingPrediction; // >=85 priority, 70-84 approved, <70 rejected
  overallAssessment: string;
  topSuggestions: string[];
  dataCompleteness: {
    hasAnalysis: boolean;
    hasCvText: boolean;
    hasReturnPlan: boolean;
    representativePaperCount: number;
  };
}

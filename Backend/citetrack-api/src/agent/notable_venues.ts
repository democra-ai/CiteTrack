// Curated library of "notable" venues — prestigious journals and top conferences
// across fields. The top-venues metric keeps only citing papers whose venue
// matches this library, so the card reads "which well-known venues cited you"
// rather than "whichever venue cited you most".
//
// Venue names from OpenAlex (primary_location.source.display_name) vary a lot
// (editions/years/abbreviations), so matching normalizes the name and checks:
//   - EXACT: generic single-ish names that would over-match as substrings
//   - PREFIXES: family prefixes (Nature *, Lancet *)
//   - KEYWORDS: distinctive substrings of full names
//   - ACRONYMS: whole-word abbreviations

function normVenue(s: string): string {
  return s
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

// Generic names that must match (near-)exactly to avoid false positives.
const EXACT = new Set<string>([
  "nature",
  "science",
  "cell",
  "neuron",
  "immunity",
  "joule",
  "matter",
  "chem",
  "pnas",
  "jama",
  "lancet",
  "the lancet",
  "bmj",
  "science advances",
  "science robotics",
  "science translational medicine",
  "science immunology",
  "science signaling",
  "molecular cell",
  "cancer cell",
  "developmental cell",
  "cell metabolism",
  "cell stem cell",
  "cell host and microbe",
  "communications of the acm",
]);

// Family prefixes (normalized startsWith).
const PREFIXES = [
  "nature ", // Nature Communications, Nature Medicine, Nature Methods, Nature Reviews …
  "lancet ", // Lancet Oncology, Lancet Neurology …
  "the lancet ",
];

// Distinctive substrings of full venue names.
const KEYWORDS = [
  // Top general-science / medicine
  "national academy of sciences", // PNAS
  "new england journal of medicine",
  "annual review of",
  "reviews of modern physics",
  // Journal families
  "ieee transactions on",
  "acm transactions on",
  "ieee journal on",
  "ieee journal of",
  "proceedings of the ieee",
  "ieee/cvf", // CVPR/ICCV/WACV proceedings
  "ieee/acm transactions",
  // Top AI / ML / CS conferences (full names)
  "neural information processing systems", // NeurIPS
  "international conference on machine learning", // ICML
  "international conference on learning representations", // ICLR
  "computer vision and pattern recognition", // CVPR
  "international conference on computer vision", // ICCV
  "european conference on computer vision", // ECCV
  "association for computational linguistics", // ACL / NAACL
  "empirical methods in natural language processing", // EMNLP
  "north american chapter of the association", // NAACL
  "knowledge discovery and data mining", // KDD
  "research and development in information retrieval", // SIGIR
  "aaai conference on artificial intelligence", // AAAI
  "international joint conference on artificial intelligence", // IJCAI
  "international world wide web conference", // WWW
  "the web conference",
  "uncertainty in artificial intelligence", // UAI
  "international conference on robotics and automation", // ICRA
  "intelligent robots and systems", // IROS
  "operating systems design and implementation", // OSDI
  "symposium on operating systems principles", // SOSP
  "symposium on theory of computing", // STOC
  "foundations of computer science", // FOCS
  "computer and communications security", // CCS
  "usenix security",
  "ieee symposium on security and privacy",
  "special interest group on computer graphics", // SIGGRAPH
  // Top CS / AI journals
  "journal of machine learning research", // JMLR
  "international journal of computer vision", // IJCV
  "pattern analysis and machine intelligence", // TPAMI (also caught by IEEE Transactions on)
  "artificial intelligence", // AIJ — broad but acceptable for "notable"
  // Physics / chemistry
  "physical review letters", // PRL
  "physical review x",
  "journal of the american chemical society", // JACS
  "angewandte chemie",
  "nature chemistry",
];

// Whole-word acronyms.
const ACRONYMS = new Set<string>([
  "neurips", "nips", "icml", "iclr", "cvpr", "iccv", "eccv", "wacv",
  "acl", "emnlp", "naacl", "coling", "aaai", "ijcai", "kdd", "sigir",
  "sigkdd", "www", "siggraph", "uai", "aistats", "colt", "icra", "iros",
  "osdi", "sosp", "stoc", "focs", "soda", "pldi", "popl", "oopsla",
  "ccs", "ndss", "usenix", "infocom", "sigcomm", "nsdi", "mobicom",
  "tpami", "jmlr", "ijcv", "tip", "tnnls", "pnas", "jacs", "prl",
  "nejm", "jama", "bmj", "chi", "vldb", "sigmod", "icde",
]);

/** True when the venue name matches the curated notable-venue library. */
export function isNotableVenue(raw: string | null | undefined): boolean {
  if (!raw) return false;
  const n = normVenue(raw);
  if (!n) return false;
  if (EXACT.has(n)) return true;
  for (const p of PREFIXES) if (n.startsWith(p)) return true;
  for (const k of KEYWORDS) if (n.includes(k)) return true;
  const tokens = new Set(n.split(" "));
  for (const a of ACRONYMS) if (tokens.has(a)) return true;
  return false;
}

/** Normalized key so venue spelling variants group together. */
export function venueKey(raw: string): string {
  return normVenue(raw);
}

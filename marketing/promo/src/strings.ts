// All on-screen copy, keyed by language. zh renders with Noto Sans SC.
// `headline` / `sub` drive the narration; `labels` are the in-mock UI strings.

export const strings = {
  en: {
    hook: { headline: ["Know your", "impact."], sub: "CiteTrack — citations, made clear." },
    problem: { headline: ["Your impact", "is scattered."], sub: "Tabs, refreshes, guesswork — never the full picture." },
    dashboard: { headline: ["Track every", "citation."], sub: "Yours, and the scholars you follow." },
    charts: { headline: ["Watch it", "grow."], sub: "Citation history, charted over time." },
    insights: { headline: ["See who", "cites you."], sub: "Notable scholars, top venues — every citation, decoded." },
    analysis: { headline: ["AI reads every", "citing paper."], sub: "Research directions, top venues — and the notable scholars who cite you." },
    widget: { headline: ["On your Home", "Screen."], sub: "Citations at a glance — refresh or switch scholars in a tap." },
    whoCited: { headline: ["Every paper,", "tracked."], sub: "Your whole body of work, citation by citation." },
    devices: { headline: "On all your devices." },
    poster: { line1: "Your impact,", line2: "in focus.", sub: "Track, analyze, and own every citation." },
    logo: {
      headline: "iPhone. Mac. In sync.",
      sub: "iCloud-synced · always in your menu bar",
      cta: "Available on the App Store",
      beta: "Now in Beta",
    },
    labels: {
      totalCitations: "total citations · tracked live",
      myCitations: "My citations",
      scholarsTracked: "Scholars tracked",
      ranking: "Citation Ranking",
      rankingSub: "Total citations",
      you: "You",
      growth: "Growth — last 90 days",
      ranges: ["7d", "30d", "90d"],
      citingPapers: "Citing papers (47)",
      quoteBody:
        "…building on the framework of Zhou et al. (2024), we extend the citation analysis to multi-modal scholarly graphs…",
      quoteSrc: "— Nature Communications, 2026",
      impactScore: "Impact Score",
      notableCiters: "Notable citers",
      topVenues: "Top venues",
      metrics: [
        { title: "Influence Score", sub: "Cited across 12 fields" },
        { title: "Field Reach", sub: "CS · Bio · Econ · Physics" },
        { title: "Velocity", sub: "Month-over-month" },
        { title: "Co-citation", sub: "Linked to seminal works" },
      ],
      citerRows: [
        { title: "Scholarly Graph Attention Networks", meta: "ICML 2026 · 3 quotes" },
        { title: "Citation Forecasting with LLMs", meta: "NeurIPS 2025 · 5 quotes" },
        { title: "Open Citations Dataset v3", meta: "JCDL 2026 · 2 quotes" },
      ],
    },
  },
  zh: {
    hook: { headline: ["看见你的", "影响力。"], sub: "CiteTrack，让引用一目了然。" },
    problem: { headline: ["影响力，", "太零散。"], sub: "反复刷新、四处查找，始终看不全。" },
    dashboard: { headline: ["追踪每一次", "引用。"], sub: "你的，和你关注的学者。" },
    charts: { headline: ["见证它的", "增长。"], sub: "引用历史，随时间清晰呈现。" },
    insights: { headline: ["看清是谁", "在引用你。"], sub: "知名学者、顶级刊物——读懂每一次引用。" },
    analysis: { headline: ["AI 读懂每篇", "引用你的论文。"], sub: "研究方向、顶级刊物——以及引用你的那些大佬。" },
    widget: { headline: ["就在你的", "主屏幕。"], sub: "引用量一眼看见——一键刷新或切换学者。" },
    whoCited: { headline: ["每一篇", "都被追踪。"], sub: "你的全部成果，逐次引用尽收眼底。" },
    devices: { headline: "在你的所有设备上。" },
    poster: { line1: "你的影响力，", line2: "一目了然。", sub: "追踪、分析，掌握每一次引用。" },
    logo: {
      headline: "iPhone 与 Mac，实时同步。",
      sub: "iCloud 同步 · 常驻菜单栏",
      cta: "现已上架 App Store",
      beta: "公测进行中",
    },
    labels: {
      totalCitations: "总引用 · 实时追踪",
      myCitations: "我的引用",
      scholarsTracked: "追踪学者",
      ranking: "引用排行",
      rankingSub: "总引用数",
      you: "你",
      growth: "增长 — 近 90 天",
      ranges: ["7天", "30天", "90天"],
      citingPapers: "引用论文（47）",
      quoteBody:
        "……在 Zhou 等人（2024）框架的基础上，我们将引用分析扩展到多模态学术图谱……",
      quoteSrc: "—《自然·通讯》，2026",
      impactScore: "影响力评分",
      notableCiters: "知名引用者",
      topVenues: "顶级刊物",
      metrics: [
        { title: "影响力指数", sub: "被 12 个领域引用" },
        { title: "领域覆盖", sub: "计算机 · 生物 · 经济 · 物理" },
        { title: "增长速度", sub: "环比月增长" },
        { title: "共被引", sub: "与奠基性工作关联" },
      ],
      citerRows: [
        { title: "学术图注意力网络", meta: "ICML 2026 · 3 处引用" },
        { title: "基于大模型的引用预测", meta: "NeurIPS 2025 · 5 处引用" },
        { title: "开放引用数据集 v3", meta: "JCDL 2026 · 2 处引用" },
      ],
    },
  },
} as const;

export type Lang = keyof typeof strings;

<div align="center">

  <img src="macOS/assets/banner.svg" alt="CiteTrack — Track your academic impact across Apple devices" width="100%">
  <br>
  <a href="https://github.com/tao-shen/CiteTrack/releases/latest"><img src="https://img.shields.io/github/v/release/tao-shen/CiteTrack?style=flat-square&color=blue&label=latest%20release" alt="Latest Release"></a>
  <a href="https://apps.apple.com/app/citetrack/id6752281652"><img src="https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS-blue?style=flat-square" alt="Platforms"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/tao-shen/CiteTrack?style=flat-square" alt="MIT License"></a>
  <a href="https://github.com/tao-shen/CiteTrack/stargazers"><img src="https://img.shields.io/github/stars/tao-shen/CiteTrack?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/tao-shen/CiteTrack/issues"><img src="https://img.shields.io/github/issues/tao-shen/CiteTrack?style=flat-square" alt="Issues"></a>
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Xcode-15+-1575F9?style=flat-square&logo=xcode&logoColor=white" alt="Xcode 15+">

</div>

<br>

---

## <img src="macOS/assets/logo.png" alt="" width="28" height="28"> Why CiteTrack?

Google Scholar has no native app and no push notifications. **CiteTrack** is a native Apple app that tracks your citations, shows trends, and notifies you when numbers change — so you can focus on research.

### Get the app

<a href="https://apps.apple.com/app/citetrack/id6752281652">
  <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
</a>

Available for **iPhone**, **iPad**, and **Mac** (universal purchase). Or [download the macOS .dmg](https://github.com/tao-shen/CiteTrack/releases/latest) from GitHub.

---

## Features

- **Dashboard** — Citations, h-index, i10-index at a glance; one tap to refresh.
- **Multi-scholar tracking** — Add any researcher by Google Scholar URL; track colleagues or collaborators in one place.
- **Charts** — Line, bar, area, heatmap; export and compare time ranges.
- **Who Cites You** — Browse citing papers; filter by year/keyword/author; export CSV/JSON.
- **Citation context** — Semantic Scholar snippets show *how* others cite you.
- **Push notifications** — Alerts when your citation count changes.
- **iCloud sync** — Scholars and history sync across iPhone, iPad, Mac (opt-in).
- **Widgets** — Citation stats on the iOS home screen.
- **macOS menu bar** — Quick check without opening the app.
- **7 languages** — English, 中文, 日本語, 한국어, Español, Français, Deutsch.

---

## Installation

### Direct Download (macOS)

Download the latest `.dmg` from [GitHub Releases](https://github.com/tao-shen/CiteTrack/releases/latest). Open, drag to Applications, done.

### Build from Source

```bash
git clone https://github.com/tao-shen/CiteTrack.git
cd CiteTrack

# iOS / iPadOS
xcodebuild -project iOS/CiteTrack_iOS.xcodeproj \
  -scheme CiteTrack -configuration Release \
  -destination 'generic/platform=iOS' build

# macOS
xcodebuild -project macOS/CiteTrack_macOS.xcodeproj \
  -scheme CiteTrack -configuration Release build
```

> **Requirements:** Xcode 15+, Swift 5.9+, macOS 12+ / iOS 15+. iOS device deployment requires an Apple Developer account.

---

## Architecture

```
CiteTrack/
├── iOS/                          # SwiftUI app + WidgetKit extension
│   ├── CiteTrack/
│   │   ├── Views/                # Tab views, charts, citation context
│   │   ├── Services/             # Google Auth, platform-specific services
│   │   └── CiteTrackApp.swift    # App entry, sidebar (iPad) + tab bar (iPhone)
│   └── CiteTrackWidget/          # Home screen widgets
│
├── macOS/                        # AppKit app + menu bar
│   ├── Sources/                  # Window controllers, chart engine
│   └── assets/                   # App icons, screenshots
│
├── Shared/                       # Cross-platform core (80%+ of logic)
│   ├── Services/                 # CitationFetch, GoogleScholar, CloudKit,
│   │                             # SemanticScholar, Analytics, Notifications
│   ├── Managers/                 # CitationManager, AppConfig, iCloudSync
│   ├── Models/                   # Scholar, CitingPaper, CitationHistory,
│   │                             # CitationContext
│   ├── CoreData/                 # Persistence stack + migrations
│   └── Localization/             # 7 languages, LocalizationManager
│
└── scripts/                      # Build & deployment automation
```

---

## Privacy & Security

CiteTrack is designed with privacy as a core principle:

- **100% on-device processing** — no server, no account, no tracking
- **iCloud sync is opt-in** — your data stays on your device unless you choose otherwise
- **No personal data collected** — the app only accesses publicly available Google Scholar pages
- **Open source** — inspect every line of code yourself

---

## Contributing

Contributions are welcome! Whether it's a bug fix, new feature, or translation improvement:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

For bugs and feature requests, please [open an issue](https://github.com/tao-shen/CiteTrack/issues).

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## Example

<div align="center">
  <img src="macOS/assets/hinton_citations_example.png" alt="CiteTrack — tracking Geoffrey Hinton's citations on macOS" width="720">
  <br>
  <sub>Tracking Geoffrey Hinton's citation metrics with CiteTrack on macOS</sub>
</div>

---

<div align="center">

  **Built for the research community**

  <a href="https://github.com/tao-shen">Tao Shen</a> · <a href="https://apps.apple.com/app/citetrack/id6752281652">App Store</a> · <a href="https://github.com/tao-shen/CiteTrack/releases">Releases</a>

  <br>

  If CiteTrack helps your research workflow, consider giving it a star

</div>

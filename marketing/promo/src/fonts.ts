import { loadFont as loadDisplay } from "@remotion/google-fonts/Nunito";
import { loadFont as loadUI } from "@remotion/google-fonts/Inter";
import { loadFont as loadCJK } from "@remotion/google-fonts/NotoSansSC";
import type { Lang } from "./types";

// Nunito = rounded, Apple-SF-Rounded-like display face (Latin)
export const display = loadDisplay("normal", {
  weights: ["700", "800", "900"],
  subsets: ["latin"],
}).fontFamily;

// Inter = clean UI / supporting text (Latin)
export const ui = loadUI("normal", {
  weights: ["400", "500", "600", "700"],
  subsets: ["latin"],
}).fontFamily;

// Noto Sans SC = Simplified-Chinese display + UI (also covers ASCII/brand words).
// Omit `subsets` — Noto Sans SC splits CJK into numbered unicode-range subsets,
// so the loader pulls the needed ranges automatically (passing a named subset throws).
export const cjk = loadCJK("normal", {
  weights: ["400", "700", "900"],
}).fontFamily;

export type Fonts = { display: string; ui: string };

// Pick the right type families for the active language.
export const fontFor = (lang: Lang): Fonts =>
  lang === "zh" ? { display: cjk, ui: cjk } : { display, ui };

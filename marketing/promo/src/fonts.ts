import { loadFont as loadDisplay } from "@remotion/google-fonts/Sora";
import { loadFont as loadUI } from "@remotion/google-fonts/Geist";
import { loadFont as loadCJK } from "@remotion/google-fonts/NotoSansSC";
import type { Lang } from "./types";

// Sora = premium geometric display (headlines, big numbers)
export const display = loadDisplay("normal", {
  weights: ["600", "700", "800"],
  subsets: ["latin"],
}).fontFamily;

// Geist = clean modern UI / supporting text (Vercel-core)
export const ui = loadUI("normal", {
  weights: ["400", "500", "600"],
  subsets: ["latin"],
}).fontFamily;

// Noto Sans SC = Simplified-Chinese (omit subsets — CJK is split into numbered ranges)
export const cjk = loadCJK("normal", {
  weights: ["500", "700", "900"],
}).fontFamily;

export type Fonts = { display: string; ui: string };

export const fontFor = (lang: Lang): Fonts =>
  lang === "zh" ? { display: cjk, ui: cjk } : { display, ui };

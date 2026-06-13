// CiteTrack promo — refined dark palette.
// Charcoal base (no navy/purple "AI lila"), a single desaturated blue accent,
// off-white text. Real app screenshots provide the color; the chrome stays calm.

export const palette = {
  bg0: "#090A0E", // deepest
  bg1: "#0C0D12", // base canvas
  bg2: "#101218",
  bg3: "#15171F", // panel / surface
  brand: "#5B8CFF", // single accent (electric blue, desaturated)
  brandSoft: "#8AA8FF",
  accent: "#5B8CFF",
  accentSoft: "#8AA8FF",
  success: "#3DD68C",
  gold: "#E8B84B",
  silver: "#C7D1DE",
  bronze: "#D08A52",
  surface: "#15171F",
  white: "#F3F4F7", // off-white, never pure
  muted: "#9CA2AE",
} as const;

export const gradients = {
  brand: `linear-gradient(135deg, ${palette.brand} 0%, ${palette.brandSoft} 100%)`,
  warmth: `linear-gradient(135deg, ${palette.brand} 0%, ${palette.brandSoft} 100%)`,
  gold: `linear-gradient(180deg, ${palette.gold} 0%, #C99A2E 100%)`,
  silver: `linear-gradient(180deg, ${palette.silver} 0%, #8A95A5 100%)`,
  bronze: `linear-gradient(180deg, ${palette.bronze} 0%, #A05E2C 100%)`,
  bgVertical: `linear-gradient(180deg, ${palette.bg0} 0%, ${palette.bg1} 60%, ${palette.bg2} 100%)`,
} as const;

export const radius = {
  sm: 14,
  md: 24,
  lg: 36,
  xl: 56,
} as const;

export const space = (n: number) => n * 8;

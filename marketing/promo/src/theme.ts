// CiteTrack promo — "Bright Airy" studio palette (Apple product-page direction).
// Warm off-white canvas, soft directional light, ONE desaturated sage accent.
// Depth (device shadows) separates the real light-UI screenshots, not a dark bg.

export const palette = {
  canvas: "#F4F2EE", // warm paper off-white base
  ink: "#1E2329", // headline text (~13:1 on canvas)
  sub: "#5A6068", // sub-labels
  sage: "#5E8C7B", // the single accent
  sageSoft: "#7BA593",
  sageTint: "#DCE6E0", // chips / tint pad
  bezel: "#26272B", // device bezel
  macBody: "#C9CBCE",
  white: "#FFFFFF",
  shadow: "58,66,78", // cool slate — never pure black
  // legacy aliases used by older components
  brand: "#5E8C7B",
  brandSoft: "#7BA593",
  muted: "#5A6068",
  bg1: "#F4F2EE",
} as const;

export const gradients = {
  // studio light pools (desaturated tinted daylight, fade to transparent — no edges)
  cool: "rgba(214,224,232,0.55)",
  warm: "rgba(238,228,214,0.50)",
  verticalWash: "linear-gradient(180deg, #F8F7F3 0%, #F2F0EB 52%, #ECEAE3 100%)",
} as const;

export const radius = {
  sm: 14,
  md: 24,
  lg: 36,
  xl: 56,
} as const;

export const space = (n: number) => n * 8;

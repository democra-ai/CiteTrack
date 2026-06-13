// CiteTrack brand system — mirrors the in-app DS enum (CiteTrackApp.swift)

export const palette = {
  bg0: "#14172E",
  bg1: "#1B1F3B",
  bg2: "#2A2F66",
  bg3: "#4B3F7A",
  brand: "#4D6CF2",
  brandSoft: "#75A0FF",
  accent: "#FD9E45",
  accentSoft: "#FFC773",
  success: "#28D190",
  gold: "#FFCF47",
  silver: "#C7D1DE",
  bronze: "#DE8C52",
  surface: "#181B36",
  white: "#FFFFFF",
} as const;

export const gradients = {
  brand: `linear-gradient(135deg, ${palette.brand} 0%, ${palette.brandSoft} 100%)`,
  warmth: `linear-gradient(135deg, ${palette.accent} 0%, ${palette.accentSoft} 100%)`,
  gold: `linear-gradient(180deg, ${palette.gold} 0%, ${palette.accent} 100%)`,
  silver: `linear-gradient(180deg, ${palette.silver} 0%, #8A95A5 100%)`,
  bronze: `linear-gradient(180deg, ${palette.bronze} 0%, #A05E2C 100%)`,
  bgVertical: `linear-gradient(180deg, ${palette.bg1} 0%, ${palette.bg2} 55%, ${palette.bg3} 100%)`,
} as const;

export const radius = {
  sm: 14,
  md: 24,
  lg: 36,
  xl: 56,
} as const;

export const space = (n: number) => n * 8;

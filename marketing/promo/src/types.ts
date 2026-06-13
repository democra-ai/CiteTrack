import { z } from "zod";

// Parameterized promo: one component renders the whole matrix.
export const PromoSchema = z.object({
  lang: z.enum(["en", "zh"]).default("en"),
  aspect: z.enum(["9:16", "16:9"]).default("9:16"),
  platform: z.enum(["ios", "macos"]).default("ios"),
  withAudio: z.boolean().default(true),
});

export type PromoProps = z.infer<typeof PromoSchema>;
export type Lang = "en" | "zh";
export type Platform = "ios" | "macos";
export type Aspect = "9:16" | "16:9";

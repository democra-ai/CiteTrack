import React, { createContext, useContext } from "react";
import { fontFor, type Fonts } from "./fonts";
import type { Lang, Platform } from "./types";
import { strings } from "./strings";

type Ctx = {
  lang: Lang;
  platform: Platform;
  f: Fonts;
  t: (typeof strings)["en"];
};

const PromoContext = createContext<Ctx>({
  lang: "en",
  platform: "ios",
  f: fontFor("en"),
  t: strings.en,
});

export const usePromo = () => useContext(PromoContext);

export const PromoProvider: React.FC<{
  lang: Lang;
  platform: Platform;
  children: React.ReactNode;
}> = ({ lang, platform, children }) => (
  <PromoContext.Provider
    value={{ lang, platform, f: fontFor(lang), t: strings[lang] }}
  >
    {children}
  </PromoContext.Provider>
);

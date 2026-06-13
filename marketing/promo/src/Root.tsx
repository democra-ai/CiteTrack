import React from "react";
import { Composition, Folder } from "remotion";
import { Promo, PROMO_DURATION, PROMO_FPS } from "./Promo";
import { PromoSchema, type Aspect, type Lang, type Platform } from "./types";

const dims = (aspect: Aspect) =>
  aspect === "16:9" ? { width: 1920, height: 1080 } : { width: 1080, height: 1920 };

const PLATFORMS: Platform[] = ["ios", "macos"];
const ASPECTS: [Aspect, string][] = [
  ["9:16", "9x16"],
  ["16:9", "16x9"],
];
const LANGS: Lang[] = ["en", "zh"];

export const RemotionRoot: React.FC = () => {
  return (
    <Folder name="CiteTrack">
      {PLATFORMS.flatMap((platform) =>
        ASPECTS.flatMap(([aspect, aid]) =>
          LANGS.map((lang) => (
            <Composition
              key={`${platform}-${aid}-${lang}`}
              id={`Promo-${platform}-${aid}-${lang}`}
              component={Promo}
              schema={PromoSchema}
              durationInFrames={PROMO_DURATION}
              fps={PROMO_FPS}
              {...dims(aspect)}
              defaultProps={{ lang, aspect, platform, withAudio: true }}
              calculateMetadata={({ props }) => ({
                ...dims(props.aspect),
                fps: PROMO_FPS,
                durationInFrames: PROMO_DURATION,
              })}
            />
          )),
        ),
      )}
    </Folder>
  );
};

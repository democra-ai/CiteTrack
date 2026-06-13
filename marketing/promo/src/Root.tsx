import React from "react";
import { Composition, Folder } from "remotion";
import { Promo, PROMO_DURATION, PROMO_FPS } from "./Promo";
import { PromoSchema, type Aspect, type Lang } from "./types";

const dims = (aspect: Aspect) =>
  aspect === "16:9" ? { width: 1920, height: 1080 } : { width: 1080, height: 1920 };

const ASPECTS: [Aspect, string][] = [
  ["9:16", "9x16"],
  ["16:9", "16x9"],
];
const LANGS: Lang[] = ["en", "zh"];

// One cross-platform video per aspect × language (iPhone + iPad + Mac all in one).
export const RemotionRoot: React.FC = () => {
  return (
    <Folder name="CiteTrack">
      {ASPECTS.flatMap(([aspect, aid]) =>
        LANGS.map((lang) => (
          <Composition
            key={`${aid}-${lang}`}
            id={`Promo-${aid}-${lang}`}
            component={Promo}
            schema={PromoSchema}
            durationInFrames={PROMO_DURATION}
            fps={PROMO_FPS}
            {...dims(aspect)}
            defaultProps={{ lang, aspect, platform: "ios" as const, withAudio: true }}
            calculateMetadata={({ props }) => ({
              ...dims(props.aspect),
              fps: PROMO_FPS,
              durationInFrames: PROMO_DURATION,
            })}
          />
        )),
      )}
    </Folder>
  );
};

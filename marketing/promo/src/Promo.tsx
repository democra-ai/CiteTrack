import React from "react";
import { AbsoluteFill, Audio, staticFile, useVideoConfig } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { clockWipe } from "@remotion/transitions/clock-wipe";
import { PromoProvider } from "./context";
import type { PromoProps } from "./types";
import {
  SceneHook,
  SceneDashboard,
  SceneCharts,
  ScenePubs,
  SceneInsights,
  SceneLogo,
} from "./scenes";

export const PROMO_FPS = 30;
// Sequence durations; TransitionSeries total = Σ(seq) − Σ(transitions).
const D = [90, 130, 120, 130, 150, 180];
export const PROMO_DURATION = D.reduce((a, b) => a + b, 0) - 5 * 15; // 720f = 24.0s

const T = (
  presentation: Parameters<typeof TransitionSeries.Transition>[0]["presentation"],
) => (
  <TransitionSeries.Transition
    presentation={presentation}
    timing={linearTiming({ durationInFrames: 15 })}
  />
);

export const Promo: React.FC<PromoProps> = ({ lang, platform, withAudio = true }) => {
  const { width, height } = useVideoConfig();
  return (
    <PromoProvider lang={lang} platform={platform}>
      <AbsoluteFill style={{ backgroundColor: "#14172E" }}>
        {withAudio && <Audio src={staticFile("audio.mp3")} loop volume={0.5} />}
        <TransitionSeries>
          <TransitionSeries.Sequence durationInFrames={D[0]}>
            <SceneHook />
          </TransitionSeries.Sequence>
          {T(clockWipe({ width, height }))}
          <TransitionSeries.Sequence durationInFrames={D[1]}>
            <SceneDashboard />
          </TransitionSeries.Sequence>
          {T(slide({ direction: "from-right" }))}
          <TransitionSeries.Sequence durationInFrames={D[2]}>
            <SceneCharts />
          </TransitionSeries.Sequence>
          {T(slide({ direction: "from-bottom" }))}
          <TransitionSeries.Sequence durationInFrames={D[3]}>
            <ScenePubs />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[4]}>
            <SceneInsights />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[5]}>
            <SceneLogo />
          </TransitionSeries.Sequence>
        </TransitionSeries>
      </AbsoluteFill>
    </PromoProvider>
  );
};

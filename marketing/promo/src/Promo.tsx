import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { PromoProvider } from "./context";
import type { PromoProps } from "./types";
import {
  SceneHook,
  SceneDashboard,
  SceneInsights,
  SceneDevices,
  SceneLogo,
} from "./scenes";

export const PROMO_FPS = 30;
const D = [90, 120, 130, 160, 160];
export const PROMO_DURATION = D.reduce((a, b) => a + b, 0) - 4 * 15; // 600f = 20s

const T = (
  presentation: Parameters<typeof TransitionSeries.Transition>[0]["presentation"],
) => (
  <TransitionSeries.Transition presentation={presentation} timing={linearTiming({ durationInFrames: 15 })} />
);

export const Promo: React.FC<PromoProps> = ({ lang, platform, withAudio = true }) => {
  return (
    <PromoProvider lang={lang} platform={platform}>
      <AbsoluteFill style={{ backgroundColor: "#F4F2EE" }}>
        {withAudio && <Audio src={staticFile("audio_upbeat.mp3")} loop volume={0.45} />}
        <TransitionSeries>
          <TransitionSeries.Sequence durationInFrames={D[0]}>
            <SceneHook />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[1]}>
            <SceneDashboard />
          </TransitionSeries.Sequence>
          {T(slide({ direction: "from-right" }))}
          <TransitionSeries.Sequence durationInFrames={D[2]}>
            <SceneInsights />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[3]}>
            <SceneDevices />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[4]}>
            <SceneLogo />
          </TransitionSeries.Sequence>
        </TransitionSeries>
      </AbsoluteFill>
    </PromoProvider>
  );
};

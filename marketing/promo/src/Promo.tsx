import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { TransitionSeries, linearTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { slide } from "@remotion/transitions/slide";
import { PromoProvider } from "./context";
import type { PromoProps } from "./types";
import {
  ScenePoster,
  SceneHook,
  SceneDashboard,
  SceneWidget,
  SceneAnalysis,
  SceneDevices,
  SceneLogo,
} from "./scenes";

export const PROMO_FPS = 30;
//          Poster Hook Dash Widget Analysis Devices Logo
const D = [60, 90, 120, 120, 150, 160, 160];
export const PROMO_DURATION = D.reduce((a, b) => a + b, 0) - 6 * 15; // 770f ≈ 25.7s

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
            <ScenePoster />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[1]}>
            <SceneHook />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[2]}>
            <SceneDashboard />
          </TransitionSeries.Sequence>
          {T(slide({ direction: "from-right" }))}
          <TransitionSeries.Sequence durationInFrames={D[3]}>
            <SceneWidget />
          </TransitionSeries.Sequence>
          {T(slide({ direction: "from-right" }))}
          <TransitionSeries.Sequence durationInFrames={D[4]}>
            <SceneAnalysis />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[5]}>
            <SceneDevices />
          </TransitionSeries.Sequence>
          {T(fade())}
          <TransitionSeries.Sequence durationInFrames={D[6]}>
            <SceneLogo />
          </TransitionSeries.Sequence>
        </TransitionSeries>
      </AbsoluteFill>
    </PromoProvider>
  );
};

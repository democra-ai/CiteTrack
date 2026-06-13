import React from "react";
import {
  AbsoluteFill,
  Img,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { palette } from "./theme";
import {
  Bg,
  Stage,
  Title,
  Subline,
  SoloDevice,
  DeviceCluster,
  useCountUp,
  useLandscape,
} from "./components";
import { usePromo } from "./context";

const sh = (a: number) => `rgba(${palette.shadow},${a})`;

/* S1 — Hook: count-up on the bright canvas */
export const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f, t } = usePromo();
  const landscape = useLandscape();
  const n = useCountUp(963124, 6, 1.5);
  const head = spring({ frame: frame - 42, fps, config: { damping: 200 } });
  const sub = spring({ frame: frame - 28, fps, config: { damping: 200 } });
  return (
    <Bg>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", padding: 80 }}>
        <div style={{ textAlign: "center" }}>
          <div
            style={{
              fontFamily: f.display,
              fontWeight: 700,
              fontSize: landscape ? 244 : 216,
              lineHeight: 1,
              letterSpacing: "-0.035em",
              color: palette.ink,
            }}
          >
            {n.toLocaleString()}
          </div>
          <div
            style={{
              marginTop: 14,
              fontFamily: f.ui,
              fontWeight: 600,
              fontSize: 30,
              letterSpacing: "0.06em",
              textTransform: "uppercase",
              color: palette.sub,
              opacity: sub,
            }}
          >
            {t.labels.totalCitations}
          </div>
          <div
            style={{
              marginTop: 50,
              fontFamily: f.display,
              fontWeight: 700,
              fontSize: landscape ? 80 : 88,
              lineHeight: 1.05,
              letterSpacing: "-0.025em",
              color: palette.ink,
              opacity: head,
              transform: `translateY(${interpolate(head, [0, 1], [28, 0])}px)`,
            }}
          >
            {t.hook.headline.join(" ")}
          </div>
          <div style={{ marginTop: 12, fontFamily: f.ui, fontWeight: 500, fontSize: 30, color: palette.sage, opacity: head }}>
            {t.hook.sub}
          </div>
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* Feature beat: a single real device + headline */
const Feature: React.FC<{ headline: readonly string[]; sub: string; screen: string; device: "ios" | "ipad" }> = ({
  headline,
  sub,
  screen,
  device,
}) => (
  <Bg>
    <Stage
      headline={
        <>
          <Title lines={headline} />
          <Subline text={sub} />
        </>
      }
      body={<SoloDevice screen={screen} device={device} />}
    />
  </Bg>
);

export const SceneDashboard: React.FC = () => {
  const { t } = usePromo();
  return <Feature headline={t.dashboard.headline} sub={t.dashboard.sub} screen="dashboard" device="ios" />;
};
export const SceneInsights: React.FC = () => {
  const { t } = usePromo();
  return <Feature headline={t.insights.headline} sub={t.insights.sub} screen="insights" device="ipad" />;
};

/* S4 — hero: iPhone + iPad + Mac */
export const SceneDevices: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f, t } = usePromo();
  const head = spring({ frame: frame - 4, fps, config: { damping: 200 } });
  return (
    <Bg>
      <AbsoluteFill style={{ alignItems: "center", paddingTop: "7%" }}>
        <div style={{ textAlign: "center", opacity: head, transform: `translateY(${interpolate(head, [0, 1], [24, 0])}px)`, zIndex: 6 }}>
          <div style={{ fontFamily: f.display, fontWeight: 700, fontSize: 80, letterSpacing: "-0.025em", color: palette.ink }}>
            {t.devices.headline}
          </div>
          <div style={{ display: "flex", gap: 10, justifyContent: "center", marginTop: 18 }}>
            {["iPhone", "iPad", "Mac"].map((p) => (
              <span
                key={p}
                style={{ padding: "8px 18px", borderRadius: 999, background: palette.sageTint, color: palette.sage, fontFamily: f.ui, fontWeight: 600, fontSize: 24 }}
              >
                {p}
              </span>
            ))}
          </div>
        </div>
        <DeviceCluster />
      </AbsoluteFill>
    </Bg>
  );
};

/* S5 — Logo / CTA (real app icon) */
export const SceneLogo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f, t } = usePromo();
  const icon = spring({ frame, fps, config: { damping: 14, stiffness: 110 } });
  const word = spring({ frame: frame - 14, fps, config: { damping: 200 } });
  const cta = spring({ frame: frame - 42, fps, config: { damping: 200 } });
  return (
    <Bg>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", padding: 80 }}>
        <Img
          src={staticFile("icon.png")}
          style={{
            width: 210,
            height: 210,
            borderRadius: 48,
            boxShadow: `0 30px 70px ${sh(0.22)}, 0 8px 18px ${sh(0.12)}`,
            transform: `scale(${icon})`,
          }}
        />
        <div style={{ display: "flex", alignItems: "center", gap: 16, marginTop: 40, opacity: word, transform: `translateY(${interpolate(word, [0, 1], [26, 0])}px)` }}>
          <div style={{ fontFamily: f.display, fontWeight: 700, fontSize: 88, letterSpacing: "-0.02em", color: palette.ink }}>CiteTrack</div>
          <div style={{ padding: "8px 18px", borderRadius: 999, background: palette.sageTint, color: palette.sage, fontFamily: f.ui, fontWeight: 600, fontSize: 26 }}>
            {t.logo.beta}
          </div>
        </div>
        <div style={{ fontFamily: f.ui, fontWeight: 500, fontSize: 34, color: palette.sub, marginTop: 14, opacity: word }}>{t.logo.headline}</div>
        <div style={{ fontFamily: f.ui, fontWeight: 500, fontSize: 26, color: palette.sage, marginTop: 6, opacity: word, letterSpacing: "0.02em" }}>iPhone · iPad · Mac</div>
        <div
          style={{
            marginTop: 46,
            padding: "22px 52px",
            borderRadius: 999,
            background: palette.ink,
            fontFamily: f.ui,
            fontWeight: 600,
            fontSize: 30,
            color: palette.canvas,
            opacity: cta,
            transform: `scale(${interpolate(cta, [0, 1], [0.92, 1])})`,
            boxShadow: `0 16px 40px ${sh(0.18)}`,
          }}
        >
          {t.logo.cta}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

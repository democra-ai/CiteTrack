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
  PhoneFrame,
  useCountUp,
  useLandscape,
} from "./components";
import { usePromo } from "./context";

const sh = (a: number) => `rgba(${palette.shadow},${a})`;

/* S0 — Poster: a complete static key-art held for the opening (frame 0 = poster) */
export const ScenePoster: React.FC = () => {
  const { f, t } = usePromo();
  const { height } = useVideoConfig();
  const landscape = useLandscape();
  const phoneW = (landscape ? height * 0.72 : height * 0.42) * (1320 / 2868);
  return (
    <Bg>
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          padding: landscape ? 120 : 80,
          flexDirection: landscape ? "row" : "column",
          gap: landscape ? 96 : 50,
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", alignItems: landscape ? "flex-start" : "center", textAlign: landscape ? "left" : "center", maxWidth: landscape ? 940 : 1000 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            <Img src={staticFile("icon.png")} style={{ width: 92, height: 92, borderRadius: 21, boxShadow: `0 14px 36px ${sh(0.2)}` }} />
            <div style={{ fontFamily: f.display, fontWeight: 700, fontSize: 60, letterSpacing: "-0.02em", color: palette.ink }}>CiteTrack</div>
          </div>
          <div style={{ marginTop: 38, fontFamily: f.display, fontWeight: 700, fontSize: landscape ? 100 : 90, lineHeight: 1.02, letterSpacing: "-0.035em", color: palette.ink }}>
            {t.poster.line1}
            <br />
            <span style={{ color: palette.sage }}>{t.poster.line2}</span>
          </div>
          <div style={{ marginTop: 24, fontFamily: f.ui, fontWeight: 500, fontSize: 32, color: palette.sub, maxWidth: 620 }}>{t.poster.sub}</div>
          <div style={{ display: "flex", gap: 10, marginTop: 32, flexWrap: "wrap", justifyContent: landscape ? "flex-start" : "center" }}>
            {["iPhone", "iPad", "Mac", t.logo.beta].map((p) => (
              <span key={p} style={{ padding: "9px 20px", borderRadius: 999, background: palette.sageTint, color: palette.sage, fontFamily: f.ui, fontWeight: 600, fontSize: 22 }}>
                {p}
              </span>
            ))}
          </div>
        </div>
        <PhoneFrame screen="insights" width={phoneW} />
      </AbsoluteFill>
    </Bg>
  );
};

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

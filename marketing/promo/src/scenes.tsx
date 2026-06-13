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
import { palette, gradients } from "./theme";
import { Bg, Stage, Title, Subline, useLandscape } from "./components";
import { usePromo } from "./context";

// Screenshot native aspect (iPhone 16 Pro Max: 1320×2868)
const SHOT_AR = 1320 / 2868;

/* Real captured app screen inside a device shell, with a slow Ken-Burns. */
const RealScreen: React.FC<{ screen: string }> = ({ screen }) => {
  const { platform, lang } = usePromo();
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const landscape = width > height;

  const enter = spring({ frame, fps, config: { damping: 24, stiffness: 110 } });
  const kb = interpolate(frame, [0, 150], [1.02, 1.09], { extrapolateRight: "clamp" });
  const drift = interpolate(frame, [0, 150], [0, -2.5], { extrapolateRight: "clamp" });

  // Size the phone by height (landscape) or width (portrait) so it always fits.
  const phoneH = landscape ? height * 0.82 : height * 0.6;
  const phoneW = phoneH * SHOT_AR;

  const img = (
    <Img
      src={staticFile(`shots/${screen}-ios-${lang}.png`)}
      style={{
        width: "100%",
        display: "block",
        transform: `scale(${kb}) translateY(${drift}%)`,
        transformOrigin: "center top",
      }}
    />
  );

  const reveal = {
    opacity: enter,
    transform: `translateY(${interpolate(enter, [0, 1], [50, 0])}px) scale(${interpolate(
      enter,
      [0, 1],
      [0.95, 1],
    )})`,
  } as const;

  if (platform === "macos") {
    // macOS window chrome around the app screen (portrait window).
    return (
      <div style={{ ...reveal, alignSelf: "center" }}>
        <div
          style={{
            width: phoneW + 36,
            borderRadius: 22,
            overflow: "hidden",
            background: palette.surface,
            border: "1px solid rgba(255,255,255,0.12)",
            boxShadow: "0 60px 130px rgba(0,0,0,0.55)",
          }}
        >
          <div
            style={{
              height: 46,
              display: "flex",
              alignItems: "center",
              gap: 10,
              padding: "0 18px",
              background: "rgba(255,255,255,0.05)",
              borderBottom: "1px solid rgba(255,255,255,0.06)",
            }}
          >
            {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
              <div key={c} style={{ width: 13, height: 13, borderRadius: "50%", background: c }} />
            ))}
          </div>
          <div style={{ width: phoneW + 36, height: phoneH, overflow: "hidden", background: "#000" }}>
            <div style={{ width: phoneW, margin: "0 auto" }}>{img}</div>
          </div>
        </div>
      </div>
    );
  }

  // iPhone shell (the screenshot already includes the iOS status bar / island).
  return (
    <div style={{ ...reveal, alignSelf: "center" }}>
      <div
        style={{
          width: phoneW + 26,
          padding: 13,
          borderRadius: 62,
          background: "linear-gradient(160deg,#2b2e48,#0c0e1b)",
          border: "2px solid rgba(255,255,255,0.10)",
          boxShadow: "0 60px 130px rgba(0,0,0,0.55), inset 0 2px 3px rgba(255,255,255,0.16)",
        }}
      >
        <div style={{ width: phoneW, height: phoneH, borderRadius: 50, overflow: "hidden", background: "#000" }}>
          {img}
        </div>
      </div>
    </div>
  );
};

/* ---------- S1 — Hook (branded count-up) ---------- */
export const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f, t } = usePromo();
  const landscape = useLandscape();
  const n = Math.round(
    interpolate(spring({ frame: frame - 6, fps, durationInFrames: 45, config: { damping: 200 } }), [0, 1], [0, 963124]),
  );
  const sub = spring({ frame: frame - 30, fps, config: { damping: 200 } });
  const head = spring({ frame: frame - 44, fps, config: { damping: 200 } });
  const pulse = 1 + Math.sin(frame / 8) * 0.012;
  return (
    <Bg>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", padding: 80 }}>
        <div style={{ textAlign: "center" }}>
          <div
            style={{
              fontFamily: f.display,
              fontWeight: 800,
              fontSize: landscape ? 256 : 226,
              lineHeight: 1,
              letterSpacing: "-0.03em",
              color: palette.white,
              transform: `scale(${pulse})`,
              textShadow: "0 10px 50px rgba(0,0,0,0.45)",
            }}
          >
            {n.toLocaleString()}
          </div>
          <div
            style={{
              marginTop: 18,
              fontFamily: f.ui,
              fontWeight: 600,
              fontSize: 36,
              letterSpacing: 1,
              color: "rgba(255,255,255,0.66)",
              opacity: sub,
              transform: `translateY(${interpolate(sub, [0, 1], [18, 0])}px)`,
            }}
          >
            {t.labels.totalCitations}
          </div>
          <div
            style={{
              marginTop: 52,
              fontFamily: f.display,
              fontWeight: 900,
              fontSize: landscape ? 84 : 92,
              lineHeight: 1.08,
              color: palette.white,
              opacity: head,
              transform: `translateY(${interpolate(head, [0, 1], [30, 0])}px)`,
            }}
          >
            {t.hook.headline.join(" ")}
          </div>
          <div
            style={{
              marginTop: 12,
              fontFamily: f.ui,
              fontWeight: 600,
              fontSize: 32,
              color: palette.brandSoft,
              opacity: head,
            }}
          >
            {t.hook.sub}
          </div>
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

/* ---------- Real-screen content scenes ---------- */
const ScreenScene: React.FC<{ shot: string; headline: readonly string[]; sub: string }> = ({
  shot,
  headline,
  sub,
}) => (
  <Bg>
    <Stage
      headline={
        <>
          <Title lines={headline} />
          <Subline text={sub} />
        </>
      }
      body={<RealScreen screen={shot} />}
    />
  </Bg>
);

export const SceneDashboard: React.FC = () => {
  const { t } = usePromo();
  return <ScreenScene shot="dashboard" headline={t.dashboard.headline} sub={t.dashboard.sub} />;
};
export const SceneCharts: React.FC = () => {
  const { t } = usePromo();
  return <ScreenScene shot="charts" headline={t.charts.headline} sub={t.charts.sub} />;
};
export const ScenePubs: React.FC = () => {
  const { t } = usePromo();
  return <ScreenScene shot="whocited" headline={t.whoCited.headline} sub={t.whoCited.sub} />;
};
export const SceneInsights: React.FC = () => {
  const { t } = usePromo();
  return <ScreenScene shot="insights" headline={t.insights.headline} sub={t.insights.sub} />;
};

/* ---------- S6 — Logo / CTA ---------- */
export const SceneLogo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f, t } = usePromo();
  const icon = spring({ frame, fps, config: { damping: 12, stiffness: 120 } });
  const word = spring({ frame: frame - 14, fps, config: { damping: 200 } });
  const cta = spring({ frame: frame - 44, fps, config: { damping: 200 } });
  const ring = interpolate(frame, [0, 60], [0.6, 1.4]);
  return (
    <Bg>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", padding: 80 }}>
        <div style={{ position: "relative", marginBottom: 56 }}>
          <div
            style={{
              position: "absolute",
              left: -180,
              top: -180,
              width: 560,
              height: 560,
              borderRadius: "50%",
              background: `radial-gradient(closest-side, ${palette.brand}33, transparent)`,
              transform: `scale(${ring})`,
            }}
          />
          <div
            style={{
              width: 220,
              height: 220,
              borderRadius: 58,
              background: gradients.brand,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              transform: `scale(${icon})`,
              boxShadow: "0 40px 90px rgba(77,108,242,0.45)",
            }}
          >
            <span style={{ fontFamily: f.display, fontWeight: 900, fontSize: 170, color: palette.white, marginTop: 46 }}>&ldquo;</span>
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 18, opacity: word, transform: `translateY(${interpolate(word, [0, 1], [30, 0])}px)` }}>
          <div style={{ fontFamily: f.display, fontWeight: 900, fontSize: 96, color: palette.white }}>CiteTrack</div>
          <div
            style={{
              padding: "8px 20px",
              borderRadius: 999,
              background: "rgba(91,140,255,0.14)",
              border: "1px solid rgba(91,140,255,0.45)",
              fontFamily: f.ui,
              fontWeight: 700,
              fontSize: 26,
              color: palette.brandSoft,
            }}
          >
            {t.logo.beta}
          </div>
        </div>
        <div style={{ fontFamily: f.ui, fontWeight: 500, fontSize: 36, color: "rgba(255,255,255,0.7)", marginTop: 14, opacity: word, textAlign: "center" }}>
          {t.logo.headline}
        </div>
        <div style={{ fontFamily: f.ui, fontWeight: 500, fontSize: 28, color: "rgba(255,255,255,0.45)", marginTop: 6, opacity: word }}>
          {t.logo.sub}
        </div>
        <div
          style={{
            marginTop: 48,
            padding: "22px 52px",
            borderRadius: 999,
            background: palette.white,
            fontFamily: f.ui,
            fontWeight: 700,
            fontSize: 30,
            color: palette.bg1,
            opacity: cta,
            transform: `scale(${interpolate(cta, [0, 1], [0.9, 1])})`,
          }}
        >
          {t.logo.cta}
        </div>
      </AbsoluteFill>
    </Bg>
  );
};

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
import { usePromo } from "./context";

export const useLandscape = () => {
  const { width, height } = useVideoConfig();
  return width > height;
};

const sh = (a: number) => `rgba(${palette.shadow},${a})`;

/* ---------- Bright airy studio background ---------- */
const Grain: React.FC = () => (
  <AbsoluteFill style={{ opacity: 0.04, mixBlendMode: "overlay", pointerEvents: "none" }}>
    <svg width="100%" height="100%" preserveAspectRatio="none">
      <filter id="g">
        <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves={2} stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      <rect width="100%" height="100%" filter="url(#g)" />
    </svg>
  </AbsoluteFill>
);

export const Bg: React.FC<{ children?: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  // slow sine drift of the two light pools (periods > clip length → never repeats)
  const t = frame / fps;
  const coolX = 22 + Math.sin(t / 18 * Math.PI * 2) * 3;
  const coolY = 18 + Math.cos(t / 18 * Math.PI * 2) * 2.5;
  const warmX = 82 - Math.sin(t / 22 * Math.PI * 2) * 3;
  const warmY = 88 + Math.cos(t / 22 * Math.PI * 2) * 2;
  return (
    <AbsoluteFill style={{ background: palette.canvas, overflow: "hidden" }}>
      <AbsoluteFill style={{ backgroundImage: gradients.verticalWash }} />
      <AbsoluteFill
        style={{
          background: `radial-gradient(60% 55% at ${coolX}% ${coolY}%, ${gradients.cool} 0%, rgba(214,224,232,0) 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(55% 50% at ${warmX}% ${warmY}%, ${gradients.warm} 0%, rgba(238,228,214,0) 72%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(70% 26% at 50% 62%, rgba(214,228,250,0.5) 0%, rgba(214,228,250,0) 65%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(120% 40% at 50% 92%, rgba(255,255,255,0.6) 0%, rgba(255,255,255,0) 60%)`,
        }}
      />
      <Grain />
      {children}
    </AbsoluteFill>
  );
};

/* ---------- Responsive headline / body layout ---------- */
export const Stage: React.FC<{ headline: React.ReactNode; body: React.ReactNode }> = ({
  headline,
  body,
}) => {
  const landscape = useLandscape();
  if (landscape) {
    return (
      <AbsoluteFill style={{ flexDirection: "row", alignItems: "center", padding: "0 120px", gap: 80 }}>
        <div style={{ flex: "0 0 40%", display: "flex", flexDirection: "column", justifyContent: "center" }}>
          {headline}
        </div>
        <div style={{ flex: 1, display: "flex", justifyContent: "center", alignItems: "center" }}>{body}</div>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{ padding: "0 96px", justifyContent: "center", gap: 60 }}>
      <div>{headline}</div>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>{body}</div>
    </AbsoluteFill>
  );
};

export const Title: React.FC<{ lines: readonly string[]; delay?: number }> = ({ lines, delay = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const landscape = useLandscape();
  const size = landscape ? 90 : 104;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      {lines.map((text, i) => {
        const s = spring({ frame: frame - delay - i * 6, fps, config: { damping: 200 } });
        const last = i === lines.length - 1;
        return (
          <div
            key={i}
            style={{
              fontFamily: f.display,
              fontWeight: 700,
              fontSize: size,
              lineHeight: 1.04,
              letterSpacing: "-0.025em",
              color: last ? palette.sage : palette.ink,
              opacity: s,
              transform: `translateY(${interpolate(s, [0, 1], [34, 0])}px)`,
            }}
          >
            {text}
          </div>
        );
      })}
    </div>
  );
};

export const Subline: React.FC<{ text: string; delay?: number }> = ({ text, delay = 18 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return (
    <div
      style={{
        marginTop: 24,
        fontFamily: f.ui,
        fontWeight: 500,
        fontSize: 30,
        lineHeight: 1.45,
        color: palette.sub,
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [14, 0])}px)`,
        maxWidth: 640,
      }}
    >
      {text}
    </div>
  );
};

export const PlatformPills: React.FC<{ items: string[]; delay?: number }> = ({ items, delay = 26 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return (
    <div style={{ display: "flex", gap: 10, marginTop: 26, opacity: s, flexWrap: "wrap" }}>
      {items.map((it) => (
        <span
          key={it}
          style={{
            padding: "8px 18px",
            borderRadius: 999,
            background: palette.sageTint,
            color: palette.sage,
            fontFamily: f.ui,
            fontWeight: 600,
            fontSize: 22,
            letterSpacing: "0.01em",
          }}
        >
          {it}
        </span>
      ))}
    </div>
  );
};

/* ---------- Device frames (real screenshots, depth shadows) ---------- */
const screenSrc = (screen: string, device: "ios" | "ipad", lang: string) =>
  staticFile(`shots/${screen}-${device}-${lang}.png`);

const kenBurns = (frame: number) => ({
  scale: interpolate(frame, [0, 150], [1.02, 1.07], { extrapolateRight: "clamp" }),
});

// iPhone bezel (portrait shot 1320×2868)
export const PhoneFrame: React.FC<{ screen: string; width: number; lang?: string }> = ({
  screen,
  width,
  lang,
}) => {
  const frame = useCurrentFrame();
  const { lang: cl } = usePromo();
  const L = lang ?? cl;
  const w = width;
  const h = w * (2868 / 1320);
  const { scale } = kenBurns(frame);
  return (
    <div
      style={{
        width: w + 24,
        padding: 12,
        borderRadius: w * 0.13,
        background: palette.bezel,
        filter: `drop-shadow(0 22px 44px ${sh(0.22)}) drop-shadow(0 4px 9px ${sh(0.16)})`,
      }}
    >
      <div style={{ width: w, height: h, borderRadius: w * 0.1, overflow: "hidden", background: "#000", boxShadow: `inset 0 0 0 1px ${sh(0.08)}` }}>
        <Img src={screenSrc(screen, "ios", L)} style={{ width: "100%", display: "block", transform: `scale(${scale})`, transformOrigin: "top center" }} />
      </div>
    </div>
  );
};

// iPad bezel (portrait shot ~1668×2388)
export const PadFrame: React.FC<{ screen: string; width: number; lang?: string }> = ({ screen, width, lang }) => {
  const frame = useCurrentFrame();
  const { lang: cl } = usePromo();
  const L = lang ?? cl;
  const w = width;
  const h = w * (2388 / 1668);
  const { scale } = kenBurns(frame);
  return (
    <div
      style={{
        width: w + 28,
        padding: 14,
        borderRadius: 44,
        background: palette.bezel,
        filter: `drop-shadow(0 30px 60px ${sh(0.2)}) drop-shadow(0 6px 12px ${sh(0.12)})`,
      }}
    >
      <div style={{ width: w, height: h, borderRadius: 28, overflow: "hidden", background: "#000", boxShadow: `inset 0 0 0 1px ${sh(0.08)}` }}>
        <Img src={screenSrc(screen, "ipad", L)} style={{ width: "100%", display: "block", transform: `scale(${scale})`, transformOrigin: "top center" }} />
      </div>
    </div>
  );
};

// MacBook clamshell — the app window centered on a Mac screen (no native Mac capture possible headlessly).
export const MacFrame: React.FC<{ screen: string; device?: "ios" | "ipad"; width: number; lang?: string }> = ({
  screen,
  device = "ipad",
  width,
  lang,
}) => {
  const frame = useCurrentFrame();
  const { lang: cl, f } = usePromo();
  const L = lang ?? cl;
  const screenW = width;
  const screenH = screenW * (10 / 16); // 16:10 display
  const { scale } = kenBurns(frame);
  const u = screenW / 1000; // scale unit
  const sidebarW = screenW * 0.23;
  // the real Insights content column, full-height (mirrors the macOS unified window)
  const colH = screenH * 0.92;
  const ar = device === "ipad" ? 1668 / 2420 : 1320 / 2868;
  const colW = colH * ar;
  const nav = L === "zh" ? ["学者", "图表", "引用分析", "设置"] : ["Scholars", "Charts", "Insights", "Settings"];
  return (
    <div style={{ filter: `drop-shadow(0 44px 90px ${sh(0.18)}) drop-shadow(0 10px 18px ${sh(0.1)})` }}>
      <div style={{ width: screenW, height: screenH, borderRadius: 18, padding: 12, background: "#1C1C1E", boxShadow: `inset 0 0 0 1px ${sh(0.22)}` }}>
        <div style={{ width: "100%", height: "100%", borderRadius: 9, overflow: "hidden", background: palette.canvas, display: "flex" }}>
          {/* sidebar — matches the real macOS unified window */}
          <div style={{ width: sidebarW, background: "rgba(255,255,255,0.5)", borderRight: `1px solid ${sh(0.07)}`, padding: 22 * u, display: "flex", flexDirection: "column", gap: 8 * u }}>
            <div style={{ fontFamily: f.display, fontWeight: 700, fontSize: 30 * u, color: palette.ink, marginBottom: 14 * u }}>CiteTrack</div>
            {nav.map((it, i) => {
              const active = i === 2;
              return (
                <div key={it} style={{ display: "flex", alignItems: "center", gap: 12 * u, padding: `${10 * u}px ${14 * u}px`, borderRadius: 10 * u, background: active ? palette.sageTint : "transparent", color: active ? palette.sage : palette.sub, fontFamily: f.ui, fontWeight: active ? 600 : 500, fontSize: 22 * u }}>
                  <div style={{ width: 17 * u, height: 17 * u, borderRadius: 5 * u, background: active ? palette.sage : palette.sub, opacity: active ? 1 : 0.5 }} />
                  {it}
                </div>
              );
            })}
            <div style={{ marginTop: "auto", display: "flex", alignItems: "center", gap: 10 * u, paddingTop: 14 * u, borderTop: `1px solid ${sh(0.07)}` }}>
              <div style={{ width: 34 * u, height: 34 * u, borderRadius: "50%", background: palette.sage, color: "#fff", fontFamily: f.ui, fontWeight: 700, fontSize: 15 * u, display: "flex", alignItems: "center", justifyContent: "center" }}>YB</div>
              <div style={{ fontFamily: f.ui, fontWeight: 500, fontSize: 15 * u, color: palette.sub }}>Yoshua Bengio</div>
            </div>
          </div>
          {/* content area — the real Insights screen as the content column */}
          <div style={{ flex: 1, display: "flex", alignItems: "flex-start", justifyContent: "center" }}>
            <div style={{ width: colW, height: colH, overflow: "hidden", background: "#000", boxShadow: `inset 0 0 0 1px ${sh(0.06)}` }}>
              <Img src={screenSrc(screen, device, L)} style={{ width: "100%", display: "block", transform: `scale(${scale})`, transformOrigin: "top center" }} />
            </div>
          </div>
        </div>
      </div>
      {/* base / hinge */}
      <div style={{ width: screenW * 1.12, height: 22, marginLeft: -screenW * 0.06, marginTop: -2, borderRadius: "0 0 16px 16px", background: `linear-gradient(180deg, ${palette.macBody}, #A9ABAF)` }} />
      <div style={{ width: screenW * 0.16, height: 8, margin: "0 auto", borderRadius: "0 0 8px 8px", background: "#9A9CA0" }} />
    </div>
  );
};

/* Single real device for a feature beat (responsive size). */
export const SoloDevice: React.FC<{ screen: string; device: "ios" | "ipad" }> = ({ screen, device }) => {
  const { width, height } = useVideoConfig();
  const landscape = width > height;
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: { damping: 200, stiffness: 70 } });
  const float = Math.sin(frame / fps * 2) * (device === "ios" ? 8 : 6);
  const h = landscape ? height * 0.82 : height * 0.6;
  const w = device === "ios" ? h * (1320 / 2868) : h * (1668 / 2388);
  return (
    <div style={{ opacity: enter, transform: `translateY(${interpolate(enter, [0, 1], [60, 0])}px) translateY(${float}px)` }}>
      {device === "ios" ? <PhoneFrame screen={screen} width={w} /> : <PadFrame screen={screen} width={w} />}
    </div>
  );
};

/* The "all your devices" hero cluster: Mac (back) + iPad (front-left) + iPhone (front-right). */
export const DeviceCluster: React.FC = () => {
  const { width, height } = useVideoConfig();
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const landscape = width > height;
  const base = landscape ? height : height * 0.62;
  const macW = base * (landscape ? 0.84 : 0.92);
  const padW = macW * 0.34;
  const phoneW = macW * 0.2;

  const mac = spring({ frame: frame - 0, fps, config: { damping: 200, stiffness: 70 } });
  const pad = spring({ frame: frame - 8, fps, config: { damping: 200, stiffness: 70 } });
  const phone = spring({ frame: frame - 16, fps, config: { damping: 200, stiffness: 70 } });
  const fMac = Math.sin(frame / fps * (2 * Math.PI) / 6) * 4;
  const fPad = Math.sin(frame / fps * (2 * Math.PI) / 5 + 1) * 7;
  const fPhone = Math.sin(frame / fps * (2 * Math.PI) / 4.5 + 2) * 10;

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ position: "relative", width: macW * 1.2, height: base }}>
        {/* Mac — back/center */}
        <div style={{ position: "absolute", left: "50%", top: "53%", transform: `translate(-50%,-50%) translateY(${interpolate(mac, [0, 1], [40, 0]) + fMac}px) scale(${interpolate(mac, [0, 1], [0.96, 1])})`, opacity: mac, zIndex: 1 }}>
          <MacFrame screen="insights" device="ipad" width={macW} />
        </div>
        {/* iPad — front-left */}
        <div style={{ position: "absolute", left: "30%", top: "71%", transform: `translate(-50%,-50%) translateY(${interpolate(pad, [0, 1], [54, 0]) + fPad}px) scale(${interpolate(pad, [0, 1], [0.94, 1])})`, opacity: pad, zIndex: 2 }}>
          <PadFrame screen="charts" width={padW} />
        </div>
        {/* iPhone — front-right, closest */}
        <div style={{ position: "absolute", left: "70%", top: "75%", transform: `translate(-50%,-50%) translateY(${interpolate(phone, [0, 1], [64, 0]) + fPhone}px) scale(${interpolate(phone, [0, 1], [0.92, 1])})`, opacity: phone, zIndex: 3 }}>
          <PhoneFrame screen="dashboard" width={phoneW} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

// Animated count-up integer
export const useCountUp = (target: number, delay = 0, durationSec = 1.2) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - delay, fps, durationInFrames: Math.round(durationSec * fps), config: { damping: 200 } });
  return Math.round(interpolate(p, [0, 1], [0, target]));
};

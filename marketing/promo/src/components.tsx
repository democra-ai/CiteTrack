import React from "react";
import {
  AbsoluteFill,
  interpolate,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { palette, gradients, radius } from "./theme";
import { usePromo } from "./context";

export const useLandscape = () => {
  const { width, height } = useVideoConfig();
  return width > height;
};

/* Fine film grain overlay — the premium texture that kills the flat/cheap look. */
const Grain: React.FC = () => (
  <AbsoluteFill style={{ opacity: 0.05, mixBlendMode: "overlay", pointerEvents: "none" }}>
    <svg width="100%" height="100%" preserveAspectRatio="none">
      <filter id="grainNoise">
        <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      <rect width="100%" height="100%" filter="url(#grainNoise)" />
    </svg>
  </AbsoluteFill>
);

/* Refined dark canvas: charcoal base + soft desaturated blue mesh + grain + vignette. */
export const Bg: React.FC<{ children?: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const d1 = interpolate(frame, [0, 300], [0, 50]);
  const d2 = interpolate(frame, [0, 300], [0, -40]);
  const blob = (x: number, y: number, s: number, color: string, blur: number): React.CSSProperties => ({
    position: "absolute",
    left: x,
    top: y,
    width: s,
    height: s,
    borderRadius: "50%",
    background: `radial-gradient(closest-side, ${color}, transparent 72%)`,
    filter: `blur(${blur}px)`,
  });
  return (
    <AbsoluteFill style={{ background: palette.bg1, overflow: "hidden" }}>
      <div style={blob(width * 0.12, height * 0.08 + d1, width * 0.95, "rgba(91,140,255,0.20)", 70)} />
      <div style={blob(width * 0.5, height * 0.52 + d2, width * 0.8, "rgba(58,108,196,0.14)", 80)} />
      <div style={blob(-width * 0.12, height * 0.66, width * 0.7, "rgba(40,70,150,0.12)", 90)} />
      <Grain />
      <AbsoluteFill
        style={{
          background: "radial-gradient(125% 85% at 50% 38%, transparent 42%, rgba(0,0,0,0.55) 100%)",
        }}
      />
      {children}
    </AbsoluteFill>
  );
};

/* Responsive headline/body layout: stacked in portrait, side-by-side in landscape. */
export const Stage: React.FC<{
  headline: React.ReactNode;
  body: React.ReactNode;
  bodyAlign?: "center" | "flex-start";
}> = ({ headline, body, bodyAlign = "center" }) => {
  const landscape = useLandscape();
  if (landscape) {
    return (
      <AbsoluteFill
        style={{
          flexDirection: "row",
          alignItems: "center",
          padding: "0 120px",
          gap: 90,
        }}
      >
        <div
          style={{
            flex: "0 0 40%",
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
          }}
        >
          {headline}
        </div>
        <div
          style={{
            flex: 1,
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            alignItems: bodyAlign,
            maxWidth: 1080,
          }}
        >
          {body}
        </div>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill style={{ padding: "0 96px", justifyContent: "center", gap: 52 }}>
      <div>{headline}</div>
      <div style={{ display: "flex", flexDirection: "column" }}>{body}</div>
    </AbsoluteFill>
  );
};

export const Title: React.FC<{
  lines: readonly string[];
  accentLast?: boolean;
  delay?: number;
}> = ({ lines, accentLast = true, delay = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const landscape = useLandscape();
  const size = landscape ? 92 : 108;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 2 }}>
      {lines.map((text, i) => {
        const s = spring({ frame: frame - delay - i * 6, fps, config: { damping: 200 } });
        const accent = accentLast && i === lines.length - 1;
        return (
          <div
            key={i}
            style={{
              fontFamily: f.display,
              fontWeight: 800,
              fontSize: size,
              lineHeight: 1.04,
              letterSpacing: "-0.025em",
              color: accent ? palette.brand : palette.white,
              opacity: s,
              transform: `translateY(${interpolate(s, [0, 1], [40, 0])}px)`,
            }}
          >
            {text}
          </div>
        );
      })}
    </div>
  );
};

export const Subline: React.FC<{ text: string; delay?: number }> = ({
  text,
  delay = 20,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return (
    <div
      style={{
        marginTop: 22,
        fontFamily: f.ui,
        fontWeight: 600,
        fontSize: 34,
        lineHeight: 1.4,
        color: "rgba(255,255,255,0.66)",
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [16, 0])}px)`,
        maxWidth: 720,
      }}
    >
      {text}
    </div>
  );
};

export const Eyebrow: React.FC<{ text: string; delay?: number }> = ({
  text,
  delay = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const s = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return (
    <div
      style={{
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [20, 0])}px)`,
        display: "inline-flex",
        alignItems: "center",
        gap: 12,
        padding: "14px 26px",
        borderRadius: 999,
        background: "rgba(255,255,255,0.08)",
        border: "1px solid rgba(255,255,255,0.18)",
        fontFamily: f.ui,
        fontWeight: 700,
        fontSize: 26,
        letterSpacing: 1,
        color: palette.gold,
      }}
    >
      ★ {text}
    </div>
  );
};

export const Card: React.FC<{
  children: React.ReactNode;
  style?: React.CSSProperties;
  delay?: number;
}> = ({ children, style, delay = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: frame - delay, fps, config: { damping: 22, stiffness: 180 } });
  return (
    <div
      style={{
        background: palette.surface,
        border: "1px solid rgba(255,255,255,0.07)",
        borderRadius: radius.lg,
        boxShadow: "0 30px 80px rgba(0,0,0,0.35)",
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [60, 0])}px) scale(${interpolate(
          s,
          [0, 1],
          [0.96, 1],
        )})`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

export const StatTile: React.FC<{
  value: string;
  label: string;
  badge?: string;
  grad: string;
  delay?: number;
}> = ({ value, label, badge, grad, delay = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { f } = usePromo();
  const s = spring({ frame: frame - delay, fps, config: { damping: 18, stiffness: 160 } });
  return (
    <div
      style={{
        flex: 1,
        background: grad,
        borderRadius: radius.md,
        padding: 36,
        boxShadow: "0 24px 60px rgba(0,0,0,0.25)",
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [50, 0])}px) scale(${interpolate(
          s,
          [0, 1],
          [0.92, 1],
        )})`,
      }}
    >
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div
          style={{
            width: 56,
            height: 56,
            borderRadius: "50%",
            background: "rgba(255,255,255,0.22)",
          }}
        />
        {badge && (
          <div
            style={{
              padding: "8px 18px",
              borderRadius: 999,
              background: "rgba(255,255,255,0.22)",
              fontFamily: f.ui,
              fontWeight: 700,
              fontSize: 22,
              color: palette.white,
            }}
          >
            {badge}
          </div>
        )}
      </div>
      <div
        style={{
          marginTop: 32,
          fontFamily: f.display,
          fontWeight: 900,
          fontSize: 72,
          color: palette.white,
        }}
      >
        {value}
      </div>
      <div style={{ fontFamily: f.ui, fontWeight: 600, fontSize: 26, color: "rgba(255,255,255,0.92)" }}>
        {label}
      </div>
    </div>
  );
};

// Animated count-up integer
export const useCountUp = (target: number, delay = 0, durationSec = 1.2) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({
    frame: frame - delay,
    fps,
    durationInFrames: Math.round(durationSec * fps),
    config: { damping: 200 },
  });
  return Math.round(interpolate(p, [0, 1], [0, target]));
};

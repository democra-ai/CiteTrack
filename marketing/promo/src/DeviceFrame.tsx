import React from "react";
import { palette, radius } from "./theme";
import type { Platform } from "./types";

// Pure-CSS iPhone bezel with a dynamic-island pill.
export const IPhoneBezel: React.FC<{
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ children, style }) => (
  <div
    style={{
      position: "relative",
      padding: 16,
      borderRadius: 74,
      background: "linear-gradient(160deg,#2b2e48,#0c0e1b)",
      border: "2px solid rgba(255,255,255,0.10)",
      boxShadow:
        "0 60px 130px rgba(0,0,0,0.55), inset 0 2px 3px rgba(255,255,255,0.16)",
      ...style,
    }}
  >
    <div
      style={{
        position: "relative",
        borderRadius: 60,
        overflow: "hidden",
        background: palette.bg0,
        width: "100%",
        height: "100%",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: 22,
          left: "50%",
          transform: "translateX(-50%)",
          width: 128,
          height: 36,
          borderRadius: 22,
          background: "#05060c",
          zIndex: 5,
        }}
      />
      {children}
    </div>
  </div>
);

// macOS window chrome with traffic-light dots.
export const MacWindow: React.FC<{
  children: React.ReactNode;
  title?: string;
  style?: React.CSSProperties;
}> = ({ children, title, style }) => (
  <div
    style={{
      borderRadius: radius.md,
      overflow: "hidden",
      background: palette.surface,
      border: "1px solid rgba(255,255,255,0.10)",
      boxShadow: "0 60px 130px rgba(0,0,0,0.5)",
      ...style,
    }}
  >
    <div
      style={{
        height: 58,
        display: "flex",
        alignItems: "center",
        gap: 13,
        padding: "0 26px",
        background: "rgba(255,255,255,0.045)",
        borderBottom: "1px solid rgba(255,255,255,0.06)",
      }}
    >
      {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
        <div
          key={c}
          style={{ width: 17, height: 17, borderRadius: "50%", background: c }}
        />
      ))}
      {title && (
        <div
          style={{
            marginLeft: 14,
            fontSize: 22,
            color: "rgba(255,255,255,0.5)",
          }}
        >
          {title}
        </div>
      )}
    </div>
    <div style={{ position: "relative" }}>{children}</div>
  </div>
);

export const DeviceFrame: React.FC<{
  platform: Platform;
  children: React.ReactNode;
  title?: string;
  style?: React.CSSProperties;
}> = ({ platform, children, title, style }) =>
  platform === "ios" ? (
    <IPhoneBezel style={style}>{children}</IPhoneBezel>
  ) : (
    <MacWindow title={title} style={style}>
      {children}
    </MacWindow>
  );

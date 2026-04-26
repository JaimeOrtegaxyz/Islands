import React from "react";
import { interpolate } from "remotion";
import type { ActionKey } from "../timeline";
import {
  KEYCAP_FADE_IN,
  KEYCAP_FADE_OUT,
  KEYCAP_HOLD,
} from "../timeline";

const ACTION_GLYPHS: Record<ActionKey, string> = {
  left: "←",
  right: "→",
  up: "↑",
  down: "↓",
  tab: "⇥",
};

const CAP_HEIGHT = 96;
const CAP_RADIUS = 18;
const CAP_BG = "rgba(28, 32, 36, 0.92)";
const CAP_SHADOW =
  "0 12px 26px rgba(0,0,0,0.34), inset 0 -3px 0 rgba(0,0,0,0.32), inset 0 1px 0 rgba(255,255,255,0.18)";

export const Keycaps: React.FC<{
  active: { chord: ActionKey; startFrame: number } | null;
  frame: number;
  desktopWidth: number;
  desktopHeight: number;
}> = ({ active, frame, desktopWidth, desktopHeight }) => {
  if (!active) return null;
  const elapsed = frame - active.startFrame;
  const total = KEYCAP_FADE_IN + KEYCAP_HOLD + KEYCAP_FADE_OUT;
  if (elapsed < 0 || elapsed > total) return null;

  const opacity = interpolate(
    elapsed,
    [0, KEYCAP_FADE_IN, KEYCAP_FADE_IN + KEYCAP_HOLD, total],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const scale = interpolate(
    elapsed,
    [0, KEYCAP_FADE_IN],
    [0.9, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 0,
        width: desktopWidth,
        height: desktopHeight,
        display: "flex",
        justifyContent: "center",
        alignItems: "flex-end",
        paddingBottom: 80,
        pointerEvents: "none",
        opacity,
        transform: `scale(${scale})`,
        transformOrigin: "center 90%",
      }}
    >
      <div style={{ display: "flex", gap: 16, alignItems: "center" }}>
        <ModifierPill />
        <Plus />
        <ActionCap glyph={ACTION_GLYPHS[active.chord]} wide={active.chord === "tab"} />
      </div>
    </div>
  );
};

const ModifierPill: React.FC = () => (
  <div
    style={{
      height: CAP_HEIGHT,
      padding: "0 26px",
      borderRadius: CAP_RADIUS,
      background: CAP_BG,
      color: "#FFFFFF",
      display: "flex",
      alignItems: "center",
      gap: 18,
      fontSize: 50,
      fontWeight: 500,
      fontFamily:
        '-apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
      letterSpacing: 1,
      boxShadow: CAP_SHADOW,
    }}
  >
    <span>⌃</span>
    <span style={{ opacity: 0.45, fontSize: 38, fontWeight: 300 }}>+</span>
    <span>⌥</span>
  </div>
);

const ActionCap: React.FC<{ glyph: string; wide?: boolean }> = ({
  glyph,
  wide,
}) => (
  <div
    style={{
      minWidth: wide ? 130 : 100,
      height: CAP_HEIGHT,
      padding: "0 26px",
      borderRadius: CAP_RADIUS,
      background: CAP_BG,
      color: "#FFFFFF",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      fontSize: 56,
      fontWeight: 500,
      fontFamily:
        '-apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif',
      letterSpacing: 1,
      boxShadow: CAP_SHADOW,
    }}
  >
    {glyph}
  </div>
);

const Plus: React.FC = () => (
  <div
    style={{
      color: "rgba(255,255,255,0.85)",
      fontSize: 38,
      fontWeight: 300,
      textShadow: "0 2px 6px rgba(0,0,0,0.4)",
    }}
  >
    +
  </div>
);

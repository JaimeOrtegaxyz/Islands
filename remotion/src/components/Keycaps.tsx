import React from "react";
import { interpolate } from "remotion";
import {
  TIMELINE,
  KEY_PRESURFACE,
  KEY_POSTRELEASE,
  KEY_TAP_DURATION,
  KEY_PRESS_FRAME,
  type ActionKey,
  type Beat,
} from "../timeline";
import {
  ControlGlyph,
  OptionGlyph,
  actionGlyph,
} from "./icons/KeyGlyph";

export type Burst = {
  key: ActionKey;
  surfaceAt: number;
  releaseAt: number;
  pressFrames: number[];
};

const CAP_HEIGHT = 96;
const CAP_RADIUS = 18;
const CAP_DEPTH = 8; // how far the top face sits above the shadow face
const TOP_FACE_BG = "#1A1F26";
const SHADOW_BG = "#0A0D12";
const TAP_FALL_PX = CAP_DEPTH; // pressed: top face sinks by full depth

export function deriveBursts(timeline: Beat[]): Burst[] {
  const bursts: Burst[] = [];
  let current: { key: ActionKey; presses: number[] } | null = null;
  for (const beat of timeline) {
    if (!beat.chord) {
      if (current) {
        bursts.push(closeBurst(current));
        current = null;
      }
      continue;
    }
    if (current && current.key === beat.chord) {
      current.presses.push(beat.at);
    } else {
      if (current) bursts.push(closeBurst(current));
      current = { key: beat.chord, presses: [beat.at] };
    }
  }
  if (current) bursts.push(closeBurst(current));
  return bursts;

  function closeBurst(c: { key: ActionKey; presses: number[] }): Burst {
    return {
      key: c.key,
      pressFrames: c.presses,
      surfaceAt: c.presses[0] - KEY_PRESURFACE,
      releaseAt: c.presses[c.presses.length - 1] + KEY_POSTRELEASE,
    };
  }
}

const BURSTS = deriveBursts(TIMELINE);

export const Keycaps: React.FC<{
  frame: number;
  layoutLeft: number;
  layoutTop: number;
  layoutWidth: number;
  layoutHeight: number;
}> = ({ frame, layoutLeft, layoutTop, layoutWidth, layoutHeight }) => {
  const burst = BURSTS.find(
    (b) => frame >= b.surfaceAt && frame <= b.releaseAt
  );
  if (!burst) return null;

  const surfaceT = clamp((frame - burst.surfaceAt) / 8, 0, 1);
  const releaseT = clamp((burst.releaseAt - frame) / 8, 0, 1);
  const groupOpacity = Math.min(surfaceT, releaseT);
  const groupTranslateY = (1 - Math.min(surfaceT, releaseT)) * -16;

  // Modifier is visually held for the full life of the burst.
  const modifierHeld = frame >= burst.surfaceAt + 4 && frame <= burst.releaseAt - 4;

  // Action key tap state: how depressed is it right now?
  const actionDepth = computeActionTapDepth(frame, burst);

  return (
    <div
      style={{
        position: "absolute",
        left: layoutLeft,
        top: layoutTop,
        width: layoutWidth,
        height: layoutHeight,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        opacity: groupOpacity,
        transform: `translateY(${groupTranslateY}px)`,
        pointerEvents: "none",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
        <ModifierPill held={modifierHeld} />
        <PlusSign />
        <ActionCap actionKey={burst.key} depth={actionDepth} />
      </div>
    </div>
  );
};

// Returns pressed offset 0..1 for the action key based on the current frame.
function computeActionTapDepth(frame: number, burst: Burst): number {
  for (const press of burst.pressFrames) {
    const start = press - KEY_PRESS_FRAME;
    const end = start + KEY_TAP_DURATION;
    if (frame >= start && frame <= end) {
      const half = KEY_TAP_DURATION / 2;
      const t = frame - start;
      return t <= half ? t / half : (KEY_TAP_DURATION - t) / half;
    }
  }
  return 0;
}

const ModifierPill: React.FC<{ held: boolean }> = ({ held }) => {
  // Held (most of the burst): ⌃⌥ visibly depressed (top face flush with shadow).
  // Not held (during surface/release windows): top face is up, depth visible.
  const sunk = held ? TAP_FALL_PX : 0;
  return (
    <DepthCap width={196} sunk={sunk}>
      <ControlGlyph size={48} />
      <OptionGlyph size={48} />
    </DepthCap>
  );
};

const ActionCap: React.FC<{ actionKey: ActionKey; depth: number }> = ({
  actionKey,
  depth,
}) => {
  const Glyph = actionGlyph(actionKey);
  const isWide = actionKey === "tab";
  return (
    <DepthCap width={isWide ? 130 : 110} sunk={depth * TAP_FALL_PX}>
      <Glyph size={56} />
    </DepthCap>
  );
};

const DepthCap: React.FC<{
  width: number;
  sunk: number;
  children: React.ReactNode;
}> = ({ width, sunk, children }) => {
  // Two stacked layers: a shadow base (always at bottom) and a top face that
  // can sink into the base. When fully sunk, the cap looks pressed.
  return (
    <div
      style={{
        position: "relative",
        width,
        height: CAP_HEIGHT + CAP_DEPTH,
      }}
    >
      <div
        style={{
          position: "absolute",
          left: 0,
          top: CAP_DEPTH,
          width,
          height: CAP_HEIGHT,
          borderRadius: CAP_RADIUS,
          background: SHADOW_BG,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 0,
          top: sunk,
          width,
          height: CAP_HEIGHT,
          borderRadius: CAP_RADIUS,
          background: TOP_FACE_BG,
          boxShadow:
            "inset 0 1px 0 rgba(255,255,255,0.18), inset 0 -1px 0 rgba(0,0,0,0.40)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          gap: 18,
        }}
      >
        {children}
      </div>
    </div>
  );
};

const PlusSign: React.FC = () => (
  <div
    style={{
      color: "rgba(20, 24, 32, 0.7)",
      fontSize: 38,
      fontWeight: 400,
    }}
  >
    +
  </div>
);

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

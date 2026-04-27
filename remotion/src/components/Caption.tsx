import React from "react";
import { interpolate } from "remotion";
import { QUICKSAND_FAMILY, ensureQuicksand } from "../fonts";
import { CAPTIONS, INTRO, OUTRO, type Panel, type Caption } from "../timeline";

// Quick crossfade — text fades in and out in place. No motion.
const ENTER_FRAMES = 6;
const EXIT_FRAMES = 6;

export const CaptionLine: React.FC<{
  frame: number;
  left: number;
  top: number;
  width: number;
  height: number;
}> = ({ frame, left, top, width, height }) => {
  ensureQuicksand();
  const active = pickActive<Caption>(CAPTIONS, frame);
  if (!active) return null;
  const opacity = fadeOpacity(frame, active.from, active.to);
  return (
    <div
      style={{
        position: "absolute",
        left,
        top,
        width,
        height,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        opacity,
        fontFamily: `${QUICKSAND_FAMILY}, -apple-system, sans-serif`,
        fontSize: 56,
        fontWeight: 500,
        color: "#1B2230",
        letterSpacing: 0.2,
        textAlign: "center",
        padding: "0 60px",
      }}
    >
      {active.text}
    </div>
  );
};

export const IntroOutroPanel: React.FC<{
  frame: number;
  canvasWidth: number;
  canvasHeight: number;
  desktopWidth: number;
  desktopX: number;
}> = ({ frame, canvasWidth, canvasHeight, desktopWidth, desktopX }) => {
  ensureQuicksand();
  const intro = pickActive<Panel>(INTRO, frame);
  const outro = pickActive<Panel>(OUTRO, frame);
  const active = intro ?? outro;
  if (!active) return null;
  const opacity = fadeOpacity(frame, active.from, active.to);
  return (
    <div
      style={{
        position: "absolute",
        // Span the desktop's width but full canvas height so flex centers
        // text on the canvas's vertical midpoint, not the desktop's.
        left: desktopX,
        top: 0,
        width: desktopWidth,
        height: canvasHeight,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 18,
        opacity,
        fontFamily: `${QUICKSAND_FAMILY}, -apple-system, sans-serif`,
        color: "#1B2230",
        textAlign: "center",
      }}
    >
      {active.lines.map((line, i) => (
        <div
          key={i}
          style={{
            fontSize: i === 0 ? 110 : 72,
            fontWeight: i === 0 ? 700 : 500,
            letterSpacing: 0.2,
            lineHeight: 1.1,
          }}
        >
          {line}
        </div>
      ))}
    </div>
  );
};

function pickActive<T extends { from: number; to: number }>(
  list: T[],
  frame: number
): T | null {
  let chosen: T | null = null;
  for (const item of list) {
    if (frame >= item.from && frame <= item.to) {
      if (!chosen || item.from > chosen.from) chosen = item;
    }
  }
  return chosen;
}

function fadeOpacity(frame: number, from: number, to: number): number {
  return interpolate(
    frame,
    [from, from + ENTER_FRAMES, to - EXIT_FRAMES, to],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
}

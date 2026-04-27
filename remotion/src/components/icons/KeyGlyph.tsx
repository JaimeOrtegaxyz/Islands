import React from "react";
import type { ActionKey } from "../../timeline";

// Rounded SVG glyphs sized to look optically centered inside ~96px keycaps.
// All paths use stroke-linecap/linejoin "round" to match Quicksand's vibe.

const COLOR = "#FFFFFF";
const STROKE = 7.5;

const wrap = (children: React.ReactNode, size = 56) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 64 64"
    fill="none"
    stroke={COLOR}
    strokeWidth={STROKE}
    strokeLinecap="round"
    strokeLinejoin="round"
    xmlns="http://www.w3.org/2000/svg"
  >
    {children}
  </svg>
);

export const ArrowLeft: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M50 32 H16" />
      <path d="M28 20 L16 32 L28 44" />
    </>,
    size
  );

export const ArrowRight: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M14 32 H48" />
      <path d="M36 20 L48 32 L36 44" />
    </>,
    size
  );

export const ArrowUp: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M32 50 V16" />
      <path d="M20 28 L32 16 L44 28" />
    </>,
    size
  );

export const ArrowDown: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M32 14 V48" />
      <path d="M20 36 L32 48 L44 36" />
    </>,
    size
  );

// Tab: rightward arrow with a vertical bar at the right edge.
export const TabGlyph: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M10 32 H42" />
      <path d="M30 20 L42 32 L30 44" />
      <path d="M50 18 V46" />
    </>,
    size
  );

// Control: short downward chevron, aligned on the lower half of the cap.
export const ControlGlyph: React.FC<{ size?: number }> = ({ size }) =>
  wrap(<path d="M14 38 L32 22 L50 38" />, size);

// Option: top-left short bar + bottom horizontal line that ends in a hook.
export const OptionGlyph: React.FC<{ size?: number }> = ({ size }) =>
  wrap(
    <>
      <path d="M10 22 H22 L42 42 H54" />
      <path d="M36 22 H54" />
    </>,
    size
  );

export function actionGlyph(key: ActionKey): React.FC<{ size?: number }> {
  switch (key) {
    case "left":
      return ArrowLeft;
    case "right":
      return ArrowRight;
    case "up":
      return ArrowUp;
    case "down":
      return ArrowDown;
    case "tab":
      return TabGlyph;
  }
}

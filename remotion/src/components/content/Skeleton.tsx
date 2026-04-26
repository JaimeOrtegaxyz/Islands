import React from "react";

const LINE_COUNT = 11;
const LINE_HEIGHT = 14;
const LINE_GAP = 22;
const LINE_WIDTH_PCT = 92;
const LAST_LINE_WIDTH_PCT = 54;

// Semi-transparent white reads as soft, desaturated "content" regardless of
// the window's identity color underneath.
const LINE_COLOR = "rgba(255, 255, 255, 0.55)";

export const Skeleton: React.FC = () => {
  return (
    <div
      style={{
        height: "100%",
        padding: "30px 40px 40px 40px",
        display: "flex",
        flexDirection: "column",
        gap: LINE_GAP,
      }}
    >
      {Array.from({ length: LINE_COUNT }).map((_, i) => {
        const isLast = i === LINE_COUNT - 1;
        return (
          <div
            key={i}
            style={{
              height: LINE_HEIGHT,
              width: `${isLast ? LAST_LINE_WIDTH_PCT : LINE_WIDTH_PCT}%`,
              borderRadius: LINE_HEIGHT / 2,
              background: LINE_COLOR,
            }}
          />
        );
      })}
    </div>
  );
};

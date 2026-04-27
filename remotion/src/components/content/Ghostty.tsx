import React from "react";
import { useCurrentFrame } from "remotion";

const LINE_COLOR = "rgba(255, 255, 255, 0.62)";
const PROMPT_COLOR = "rgba(255, 255, 255, 0.85)";

export const Ghostty: React.FC = () => {
  const frame = useCurrentFrame();
  // 14-frame blink cycle for the cursor.
  const cursorOn = Math.floor(frame / 14) % 2 === 0;

  const lines: { prompt: boolean; widthPct: number }[] = [
    { prompt: true, widthPct: 24 },
    { prompt: false, widthPct: 78 },
    { prompt: false, widthPct: 56 },
    { prompt: true, widthPct: 38 },
    { prompt: false, widthPct: 92 },
    { prompt: false, widthPct: 64 },
    { prompt: true, widthPct: 30 },
    { prompt: false, widthPct: 84 },
    { prompt: false, widthPct: 70 },
  ];

  return (
    <div
      style={{
        height: "100%",
        padding: "32px 36px 40px 36px",
        display: "flex",
        flexDirection: "column",
        gap: 18,
      }}
    >
      {lines.map((l, i) => (
        <div key={i} style={{ display: "flex", alignItems: "center", gap: 10 }}>
          {l.prompt && (
            <div
              style={{
                width: 14,
                height: 14,
                borderRadius: 3,
                background: PROMPT_COLOR,
              }}
            />
          )}
          <div
            style={{
              height: 12,
              width: `${l.widthPct}%`,
              borderRadius: 3,
              background: LINE_COLOR,
            }}
          />
        </div>
      ))}
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <div
          style={{
            width: 14,
            height: 14,
            borderRadius: 3,
            background: PROMPT_COLOR,
          }}
        />
        <div
          style={{
            width: 16,
            height: 22,
            background: cursorOn ? PROMPT_COLOR : "transparent",
          }}
        />
      </div>
    </div>
  );
};

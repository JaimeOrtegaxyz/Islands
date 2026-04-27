import React from "react";

const LINE_COLOR = "rgba(255, 255, 255, 0.55)";
const PILL_COLOR = "rgba(255, 255, 255, 0.85)";
const BLOCK_COLOR = "rgba(255, 255, 255, 0.45)";

export const Chrome: React.FC = () => {
  return (
    <div
      style={{
        height: "100%",
        padding: "26px 40px 40px 40px",
        display: "flex",
        flexDirection: "column",
        gap: 24,
      }}
    >
      <div
        style={{
          height: 32,
          borderRadius: 16,
          background: PILL_COLOR,
        }}
      />
      <div style={{ display: "flex", flexDirection: "column", gap: 18 }}>
        <Bar widthPct={88} />
        <Bar widthPct={62} />
      </div>
      <div
        style={{
          flex: 1,
          display: "grid",
          gridTemplateColumns: "1fr 1fr",
          gap: 18,
        }}
      >
        <Block />
        <Block />
        <Block />
        <Block />
      </div>
    </div>
  );
};

const Bar: React.FC<{ widthPct: number }> = ({ widthPct }) => (
  <div
    style={{
      height: 14,
      width: `${widthPct}%`,
      borderRadius: 7,
      background: LINE_COLOR,
    }}
  />
);

const Block: React.FC = () => (
  <div
    style={{
      borderRadius: 12,
      background: BLOCK_COLOR,
    }}
  />
);

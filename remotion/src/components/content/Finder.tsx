import React from "react";

const LINE_COLOR = "rgba(255, 255, 255, 0.5)";
const ICON_COLOR = "rgba(255, 255, 255, 0.55)";

// Fixed pixel sizes — icons stay this size regardless of window dimensions
// (real Finder behavior). The flex container wraps as space allows.
const ICON_SIZE = 88;
const ICON_GAP = 32;
const LABEL_WIDTH = 56;
const LABEL_HEIGHT = 10;
const ICON_CELL_WIDTH = 110; // icon + label width budget
const ICON_COUNT = 14;

export const Finder: React.FC = () => {
  return (
    <div
      style={{
        height: "100%",
        display: "flex",
        padding: 28,
        gap: 28,
        alignItems: "stretch",
      }}
    >
      <Sidebar />
      <Main />
    </div>
  );
};

const Sidebar: React.FC = () => (
  <div
    style={{
      width: "22%",
      display: "flex",
      flexDirection: "column",
      gap: 18,
      paddingTop: 8,
    }}
  >
    {[78, 88, 64, 82, 70, 60, 86, 72].map((w, i) => (
      <div
        key={i}
        style={{
          height: 12,
          width: `${w}%`,
          borderRadius: 6,
          background: LINE_COLOR,
        }}
      />
    ))}
  </div>
);

const Main: React.FC = () => (
  <div
    style={{
      flex: 1,
      display: "flex",
      flexWrap: "wrap",
      alignContent: "flex-start",
      justifyContent: "flex-start",
      gap: ICON_GAP,
      paddingTop: 8,
    }}
  >
    {Array.from({ length: ICON_COUNT }).map((_, i) => (
      <Icon key={i} />
    ))}
  </div>
);

const Icon: React.FC = () => (
  <div
    style={{
      width: ICON_CELL_WIDTH,
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      gap: 12,
    }}
  >
    <div
      style={{
        width: ICON_SIZE,
        height: ICON_SIZE,
        borderRadius: 14,
        background: ICON_COLOR,
      }}
    />
    <div
      style={{
        height: LABEL_HEIGHT,
        width: LABEL_WIDTH,
        borderRadius: LABEL_HEIGHT / 2,
        background: LINE_COLOR,
      }}
    />
  </div>
);

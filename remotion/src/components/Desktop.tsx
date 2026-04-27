import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { QUICKSAND_FAMILY, ensureQuicksand } from "../fonts";

// Canvas: 2940 × 1260 white. Desktop sits in the upper portion; the lower
// 220px is reserved for caption text + keycap row, so they never crowd the
// simulated screen.
export const CANVAS_W = 2940;
export const CANVAS_H = 1260;
export const DESKTOP_W = 1742; // 16:9 of 980
export const DESKTOP_H = 980;
export const DESKTOP_X = Math.round((CANVAS_W - DESKTOP_W) / 2); // 599
export const DESKTOP_Y = 60;

export const MENUBAR_H = 50;
export const TILE_X = 0;
export const TILE_Y = MENUBAR_H;
export const TILE_W = DESKTOP_W;
export const TILE_H = DESKTOP_H - TILE_Y;

// Lower band reserved for captions + keycaps.
export const BAND_TOP = DESKTOP_Y + DESKTOP_H; // 1040
export const BAND_H = CANVAS_H - BAND_TOP; // 220
export const CAPTION_BAND_H = 88; // top portion of band
export const KEYS_BAND_H = BAND_H - CAPTION_BAND_H; // 132

export const Desktop: React.FC<{
  appName: string;
  opacity: number;
  children: React.ReactNode;
}> = ({ appName, opacity, children }) => {
  ensureQuicksand();
  if (opacity <= 0.001) return <AbsoluteFill style={{ background: "#FFFFFF" }} />;
  return (
    <AbsoluteFill style={{ background: "#FFFFFF" }}>
      <div
        style={{
          position: "absolute",
          left: DESKTOP_X,
          top: DESKTOP_Y,
          width: DESKTOP_W,
          height: DESKTOP_H,
          overflow: "hidden",
          borderRadius: 10,
          boxShadow: "0 1px 0 rgba(0,0,0,0.06)",
          opacity,
        }}
      >
          <Img
            src={staticFile("wallpaper.png")}
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              width: "100%",
              height: "100%",
              objectFit: "cover",
            }}
          />
        {children}
        <Menubar appName={appName} />
      </div>
    </AbsoluteFill>
  );
};

const Menubar: React.FC<{ appName: string }> = ({ appName }) => {
  return (
    <div
      style={{
        position: "absolute",
        top: 0,
        left: 0,
        right: 0,
        height: MENUBAR_H,
        background: "rgba(245, 246, 248, 0.78)",
        backdropFilter: "blur(20px)",
        WebkitBackdropFilter: "blur(20px)",
        borderBottom: "1px solid rgba(0,0,0,0.06)",
        display: "flex",
        alignItems: "center",
        padding: "0 22px",
        color: "#0B0B0F",
        fontFamily: `${QUICKSAND_FAMILY}, -apple-system, "SF Pro Text", sans-serif`,
        fontSize: 18,
        fontWeight: 500,
        letterSpacing: 0.2,
        gap: 22,
      }}
    >
      <AppleLogo />
      <span style={{ fontWeight: 700 }}>{appName}</span>
      <span style={{ opacity: 0.85 }}>File</span>
      <span style={{ opacity: 0.85 }}>Edit</span>
      <span style={{ opacity: 0.85 }}>View</span>
      <span style={{ opacity: 0.85 }}>Window</span>
      <span style={{ opacity: 0.85 }}>Help</span>
      <div style={{ flex: 1 }} />
      <span style={{ opacity: 0.85, fontVariantNumeric: "tabular-nums" }}>
        Sat 25 Apr 11:42 PM
      </span>
    </div>
  );
};

const AppleLogo: React.FC = () => (
  <svg
    width="20"
    height="24"
    viewBox="0 0 170 200"
    fill="#0B0B0F"
    xmlns="http://www.w3.org/2000/svg"
  >
    <path d="M150.37 154.96c-2.71 6.27-5.92 12.04-9.66 17.34-5.09 7.22-9.26 12.21-12.47 14.97-4.97 4.57-10.31 6.91-16.03 7.04-4.11 0-9.06-1.17-14.84-3.55-5.79-2.36-11.11-3.53-15.97-3.53-5.1 0-10.57 1.17-16.41 3.53-5.85 2.38-10.56 3.62-14.18 3.74-5.49.23-10.95-2.18-16.44-7.23-3.49-2.99-7.85-8.18-13.07-15.55-5.6-7.86-10.2-16.97-13.81-27.36-3.86-11.22-5.79-22.09-5.79-32.61 0-12.05 2.6-22.45 7.81-31.18 4.09-7.01 9.55-12.55 16.36-16.61 6.81-4.07 14.17-6.14 22.07-6.27 4.36 0 10.07 1.35 17.16 4 7.07 2.66 11.61 4.01 13.6 4.01 1.49 0 6.53-1.58 15.11-4.74 8.11-2.93 14.96-4.14 20.57-3.66 15.21 1.23 26.63 7.23 34.21 18.03-13.6 8.24-20.33 19.78-20.2 34.59.12 11.53 4.3 21.13 12.51 28.76 3.72 3.53 7.88 6.26 12.51 8.21-1 2.91-2.06 5.7-3.18 8.38zM119.11 7.24c0 9-3.29 17.4-9.84 25.18-7.91 9.25-17.47 14.59-27.84 13.75a27.95 27.95 0 0 1-.21-3.41c0-8.64 3.76-17.89 10.43-25.45 3.33-3.83 7.57-7.01 12.71-9.55 5.13-2.5 9.98-3.88 14.54-4.13.13 1.21.21 2.41.21 3.61z" />
  </svg>
);

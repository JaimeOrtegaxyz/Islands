import React from "react";
import { Skeleton } from "./content/Skeleton";

type Props = {
  color: string;
  x: number;
  y: number;
  w: number;
  h: number;
  opacity: number;
  stackOffsetY: number;
};

// Per Window.svg reference: subtle 0.4-of-365 stroke ≈ rgba(0,0,0,0.06) at 1.5px,
// 5.8/365 corner radius ≈ 12px on a typical sized window.
const BORDER_RADIUS = 14;
const BORDER = "1.5px solid rgba(0,0,0,0.10)";

// Traffic lights stay a fixed pixel size regardless of window dimensions.
const LIGHT_DIAMETER = 22;
const LIGHTS_TOP = 18;
const LIGHTS_LEFT = 22;
const LIGHTS_GAP = 10;
const LIGHTS_AREA_HEIGHT = LIGHTS_TOP + LIGHT_DIAMETER + 14; // ~54px

export const Window: React.FC<Props> = ({
  color,
  x,
  y,
  w,
  h,
  opacity,
  stackOffsetY,
}) => {
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y - stackOffsetY,
        width: w,
        height: h,
        opacity,
        borderRadius: BORDER_RADIUS,
        overflow: "hidden",
        background: color,
        border: BORDER,
        boxShadow:
          "0 24px 50px rgba(0,0,0,0.18), 0 6px 14px rgba(0,0,0,0.10)",
      }}
    >
      <TrafficLights />
      <div
        style={{
          position: "absolute",
          left: 0,
          top: LIGHTS_AREA_HEIGHT,
          right: 0,
          bottom: 0,
        }}
      >
        <Skeleton />
      </div>
    </div>
  );
};

const TrafficLights: React.FC = () => (
  <div
    style={{
      position: "absolute",
      top: LIGHTS_TOP,
      left: LIGHTS_LEFT,
      display: "flex",
      gap: LIGHTS_GAP,
    }}
  >
    <Light color="#EC6B5F" />
    <Light color="#F5BF4E" />
    <Light color="#61C554" />
  </div>
);

const Light: React.FC<{ color: string }> = ({ color }) => (
  <div
    style={{
      width: LIGHT_DIAMETER,
      height: LIGHT_DIAMETER,
      borderRadius: LIGHT_DIAMETER / 2,
      background: color,
      boxShadow: "inset 0 0 0 0.6px rgba(0,0,0,0.20)",
    }}
  />
);

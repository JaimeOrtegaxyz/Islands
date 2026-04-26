import React from "react";
import { Composition, registerRoot } from "remotion";
import { IslandsDemo } from "./IslandsDemo";
import { FPS, TOTAL_FRAMES } from "./timeline";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="IslandsDemo"
      component={IslandsDemo}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={2940}
      height={1260}
    />
  );
};

registerRoot(RemotionRoot);

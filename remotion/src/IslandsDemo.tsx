import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import {
  Desktop,
  CANVAS_W,
  CANVAS_H,
  DESKTOP_X,
  DESKTOP_W,
  TILE_X,
  TILE_Y,
  TILE_W,
  TILE_H,
  CAPTION_BAND_H,
  KEYS_BAND_H,
  BAND_TOP,
} from "./components/Desktop";
import { Window } from "./components/Window";
import { Keycaps } from "./components/Keycaps";
import { CaptionLine, IntroOutroPanel } from "./components/Caption";
import { Soundtrack } from "./components/Audio";
import {
  TIMELINE,
  WINDOWS,
  APP_NAMES,
  MOTION_DURATION,
  SPAWN_DURATION,
  DEMO_START,
  DESKTOP_FADE_FROM,
  DESKTOP_FADE_TO,
  DESKTOP_REVEAL_FROM,
  DESKTOP_REVEAL_TO,
  type Geo,
} from "./timeline";

const STACK_OFFSET_Y_PX = 38;

export const IslandsDemo: React.FC = () => {
  const frame = useCurrentFrame();

  const renderOrder = computeRenderOrder(frame);
  const visible = renderOrder
    .map((id) => buildWindowState(id, frame, renderOrder))
    .filter((s): s is WindowState => s !== null);

  // Frontmost window's app drives the menubar text.
  const frontId = renderOrder[renderOrder.length - 1];
  const frontApp = frontId ? WINDOWS[frontId].app : "finder";
  const appName = APP_NAMES[frontApp];

  // Outro: the entire desktop (windows + wallpaper + menubar) fades together.
  const desktopOpacity = interpolate(
    frame,
    [DESKTOP_FADE_FROM, DESKTOP_FADE_TO],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  // Smooth reveal of the desktop so the wallpaper doesn't pop on under the
  // intro text — fades in just before Chrome spawns.
  const desktopReveal = interpolate(
    frame,
    [DESKTOP_REVEAL_FROM, DESKTOP_REVEAL_TO],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const finalDesktopOpacity = desktopOpacity * desktopReveal;

  return (
    <>
      <Soundtrack />

      <Desktop appName={appName} opacity={finalDesktopOpacity}>
        {visible.map((s) => {
          const meta = WINDOWS[s.id];
          const px = geoToPx(s.geo);
          return (
            <Window
              key={s.id}
              color={meta.color}
              app={meta.app}
              x={px.x}
              y={px.y}
              w={px.w}
              h={px.h - s.stackHReductionPx}
              opacity={s.opacity}
              stackOffsetY={s.stackOffsetY}
            />
          );
        })}
      </Desktop>

      {/* Lower band: caption above keys, both below the desktop. */}
      <CaptionLine
        frame={frame}
        left={DESKTOP_X}
        top={BAND_TOP}
        width={DESKTOP_W}
        height={CAPTION_BAND_H}
      />
      <Keycaps
        frame={frame}
        layoutLeft={DESKTOP_X}
        layoutTop={BAND_TOP + CAPTION_BAND_H}
        layoutWidth={DESKTOP_W}
        layoutHeight={KEYS_BAND_H}
      />

      {/* Intro/outro text — centered on the canvas vertical midpoint. */}
      <IntroOutroPanel
        frame={frame}
        canvasWidth={CANVAS_W}
        canvasHeight={CANVAS_H}
        desktopWidth={DESKTOP_W}
        desktopX={DESKTOP_X}
      />
    </>
  );
};

type WindowState = {
  id: string;
  geo: Geo;
  opacity: number;
  stackOffsetY: number;
  stackHReductionPx: number;
};

function buildWindowState(
  id: string,
  frame: number,
  renderOrder: string[]
): WindowState | null {
  const events = collectEvents(id);
  const spawn = events.find((e) => e.isSpawn);
  if (!spawn || frame < spawn.at) return null;

  const geo = computeGeoAt(events, frame);

  const sinceSpawn = frame - spawn.at;
  const spawnT = clamp(sinceSpawn / SPAWN_DURATION, 0, 1);
  // Smooth S-curve so the window doesn't pop in.
  const opacity = easeInOutQuad(spawnT);

  const depth = animatedDepth(id, frame, renderOrder);
  const stackSize = countWindowsInZone(geo, frame, renderOrder);
  const maxDepth = Math.max(0, stackSize - 1);
  const stackOffsetY = (depth - maxDepth) * STACK_OFFSET_Y_PX;
  const stackHReductionPx = maxDepth * STACK_OFFSET_Y_PX;

  return { id, geo, opacity, stackOffsetY, stackHReductionPx };
}

function countWindowsInZone(
  geo: Geo,
  frame: number,
  order: string[]
): number {
  let count = 0;
  for (const otherId of order) {
    if (geoEqual(targetGeoAtBeat(otherId, frame), geo)) count++;
  }
  return count;
}

type Event = { at: number; geo: Geo; isSpawn: boolean };

function collectEvents(id: string): Event[] {
  const out: Event[] = [];
  for (const beat of TIMELINE) {
    for (const a of beat.actions) {
      if (a.kind === "spawn" && a.id === id) {
        out.push({ at: beat.at, geo: a.geo, isSpawn: true });
      } else if (a.kind === "move" && a.id === id) {
        out.push({ at: beat.at, geo: a.geo, isSpawn: false });
      }
    }
  }
  return out;
}

function computeGeoAt(events: Event[], frame: number): Geo {
  let current = events[0].geo;
  for (let i = 1; i < events.length; i++) {
    const ev = events[i];
    if (ev.at > frame) break;
    if (frame < ev.at + MOTION_DURATION) {
      const t = (frame - ev.at) / MOTION_DURATION;
      return lerpGeo(events[i - 1].geo, ev.geo, easeOutCubic(t));
    }
    current = ev.geo;
  }
  return current;
}

function targetGeoAtBeat(id: string, beatFrame: number): Geo {
  const events = collectEvents(id);
  let geo = events[0]?.geo ?? { x: 0, y: 0, w: 0, h: 0 };
  for (const ev of events) {
    if (ev.at <= beatFrame) geo = ev.geo;
    else break;
  }
  return geo;
}

function computeRenderOrder(frame: number): string[] {
  let order: string[] = [];
  for (const beat of TIMELINE) {
    if (beat.at > frame) break;
    for (const action of beat.actions) {
      if (action.kind === "spawn") {
        order = [...order, action.id];
      } else if (action.kind === "tab") {
        order = rotateStack(order, beat.at);
      }
    }
  }
  return order;
}

function rotateStack(order: string[], beatFrame: number): string[] {
  if (order.length === 0) return order;
  const front = order[order.length - 1];
  const frontGeo = targetGeoAtBeat(front, beatFrame);
  const positions: number[] = [];
  for (let i = 0; i < order.length; i++) {
    if (geoEqual(targetGeoAtBeat(order[i], beatFrame), frontGeo)) {
      positions.push(i);
    }
  }
  if (positions.length < 2) return order;
  const stack = positions.map((p) => order[p]);
  const rotated = [stack[stack.length - 1], ...stack.slice(0, -1)];
  const next = [...order];
  positions.forEach((p, i) => {
    next[p] = rotated[i];
  });
  return next;
}

function depthOf(id: string, order: string[], frame: number): number {
  const idx = order.indexOf(id);
  if (idx < 0) return 0;
  const myGeo = targetGeoAtBeat(id, frame);
  let d = 0;
  for (let i = idx + 1; i < order.length; i++) {
    if (geoEqual(targetGeoAtBeat(order[i], frame), myGeo)) d++;
  }
  return d;
}

function animatedDepth(
  id: string,
  frame: number,
  currentOrder: string[]
): number {
  let activeTabAt = -Infinity;
  for (const beat of TIMELINE) {
    if (beat.at > frame) break;
    if (beat.actions.some((a) => a.kind === "tab")) {
      activeTabAt = beat.at;
    }
  }
  if (frame >= activeTabAt + MOTION_DURATION || activeTabAt === -Infinity) {
    return depthOf(id, currentOrder, frame);
  }
  const orderBefore = computeRenderOrder(activeTabAt - 1);
  const orderAfter = currentOrder;
  const before = depthOf(id, orderBefore, frame);
  const after = depthOf(id, orderAfter, frame);
  const t = (frame - activeTabAt) / MOTION_DURATION;
  return before + (after - before) * easeOutCubic(t);
}

function geoToPx(g: Geo): { x: number; y: number; w: number; h: number } {
  return {
    x: Math.round(TILE_X + g.x * TILE_W),
    y: Math.round(TILE_Y + g.y * TILE_H),
    w: Math.round(g.w * TILE_W),
    h: Math.round(g.h * TILE_H),
  };
}

function lerpGeo(a: Geo, b: Geo, t: number): Geo {
  return {
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    w: a.w + (b.w - a.w) * t,
    h: a.h + (b.h - a.h) * t,
  };
}

function geoEqual(a: Geo, b: Geo): boolean {
  const eps = 0.001;
  return (
    Math.abs(a.x - b.x) < eps &&
    Math.abs(a.y - b.y) < eps &&
    Math.abs(a.w - b.w) < eps &&
    Math.abs(a.h - b.h) < eps
  );
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

function easeInOutQuad(t: number): number {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

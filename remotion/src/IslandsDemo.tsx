import React from "react";
import { useCurrentFrame } from "remotion";
import {
  Desktop,
  DESKTOP_W,
  DESKTOP_H,
  TILE_X,
  TILE_Y,
  TILE_W,
  TILE_H,
} from "./components/Desktop";
import { Window } from "./components/Window";
import { Keycaps } from "./components/Keycaps";
import {
  TIMELINE,
  WINDOWS,
  MOTION_DURATION,
  SPAWN_DURATION,
  KEYCAP_FADE_IN,
  KEYCAP_HOLD,
  KEYCAP_FADE_OUT,
  type Geo,
  type ActionKey,
} from "./timeline";

const STACK_OFFSET_Y_PX = 38;

export const IslandsDemo: React.FC = () => {
  const frame = useCurrentFrame();

  const renderOrder = computeRenderOrder(frame);
  const visible = renderOrder
    .map((id) => buildWindowState(id, frame, renderOrder))
    .filter((s): s is WindowState => s !== null);

  const activeChord = findActiveChord(frame);

  return (
    <Desktop>
      {visible.map((s) => {
        const meta = WINDOWS[s.id];
        const px = geoToPx(s.geo);
        return (
          <Window
            key={s.id}
            color={meta.color}
            x={px.x}
            y={px.y}
            w={px.w}
            h={px.h - s.stackHReductionPx}
            opacity={s.opacity}
            stackOffsetY={s.stackOffsetY}
          />
        );
      })}
      <Keycaps
        active={activeChord}
        frame={frame}
        desktopWidth={DESKTOP_W}
        desktopHeight={DESKTOP_H}
      />
    </Desktop>
  );
};

type WindowState = {
  id: string;
  geo: Geo;
  opacity: number;
  stackOffsetY: number; // px subtracted from y at render time
  stackHReductionPx: number; // px subtracted from h so the stack fits in its zone
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
  const opacity = easeOutCubic(spawnT);

  // Stack: front window pushes itself DOWN by (stackSize-1)*peek so back
  // windows fit above it within the same zone. Each window's net y offset
  // from natural top = (maxDepth - depth) * peek (positive = downward).
  // Window renders at `top: y - stackOffsetY`, so stackOffsetY = (depth - maxDepth) * peek.
  // All windows in the stack also lose maxDepth*peek of height so the
  // front's bottom still meets the zone's bottom edge.
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

function findActiveChord(
  frame: number
): { chord: ActionKey; startFrame: number } | null {
  const total = KEYCAP_FADE_IN + KEYCAP_HOLD + KEYCAP_FADE_OUT;
  let last: { chord: ActionKey; startFrame: number } | null = null;
  for (const beat of TIMELINE) {
    if (beat.chord && beat.at <= frame && frame <= beat.at + total) {
      last = { chord: beat.chord, startFrame: beat.at };
    }
  }
  return last;
}

// Tile fractions → desktop pixels. Edge-to-edge: no inter-window margin.
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

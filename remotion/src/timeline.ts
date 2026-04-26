export type Geo = { x: number; y: number; w: number; h: number };

export const PALETTE = {
  teal: "#3CA9A0",
  blue: "#5C7CFA",
  amber: "#F0A648",
  lavender: "#B57BD9",
} as const;

export const WINDOWS: Record<string, { color: string }> = {
  A: { color: PALETTE.teal },
  B: { color: PALETTE.blue },
  C: { color: PALETTE.amber },
  D: { color: PALETTE.lavender },
  E: { color: PALETTE.teal },
};

export type ActionKey = "left" | "right" | "up" | "down" | "tab";

export type SpawnAction = { kind: "spawn"; id: string; geo: Geo };
export type MoveAction = { kind: "move"; id: string; geo: Geo };
export type TabAction = { kind: "tab" };
export type Action = SpawnAction | MoveAction | TabAction;

export type Beat = {
  at: number;
  chord?: ActionKey;
  actions: Action[];
};

const FULL: Geo = { x: 0, y: 0, w: 1, h: 1 };
const RIGHT_3_4: Geo = { x: 0.25, y: 0, w: 0.75, h: 1 };
const RIGHT_1_2: Geo = { x: 0.5, y: 0, w: 0.5, h: 1 };
const RIGHT_1_4: Geo = { x: 0.75, y: 0, w: 0.25, h: 1 };
const LEFT_3_4: Geo = { x: 0, y: 0, w: 0.75, h: 1 };
const LEFT_1_2: Geo = { x: 0, y: 0, w: 0.5, h: 1 };

const TR_QUARTER: Geo = { x: 0.5, y: 0, w: 0.5, h: 0.5 };
const RIGHT_HALF_TOP_3_4: Geo = { x: 0.5, y: 0, w: 0.5, h: 0.75 };
const RIGHT_HALF_FULL_H: Geo = { x: 0.5, y: 0, w: 0.5, h: 1 };
const RIGHT_HALF_BOT_3_4: Geo = { x: 0.5, y: 0.25, w: 0.5, h: 0.75 };
const BR_QUARTER: Geo = { x: 0.5, y: 0.5, w: 0.5, h: 0.5 };

export const FPS = 30;

export const TIMELINE: Beat[] = [
  { at: 0, actions: [{ kind: "spawn", id: "A", geo: FULL }] },

  { at: 24, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_3_4 }] },
  { at: 40, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_1_2 }] },
  { at: 54, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_1_4 }] },

  { at: 86, chord: "left", actions: [{ kind: "move", id: "A", geo: RIGHT_1_2 }] },

  { at: 112, chord: "down", actions: [{ kind: "move", id: "A", geo: { x: 0.5, y: 0.25, w: 0.5, h: 0.75 } }] },
  { at: 126, chord: "down", actions: [{ kind: "move", id: "A", geo: BR_QUARTER }] },

  { at: 158, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_BOT_3_4 }] },
  { at: 172, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_FULL_H }] },
  { at: 186, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_TOP_3_4 }] },
  { at: 200, chord: "up", actions: [{ kind: "move", id: "A", geo: TR_QUARTER }] },

  { at: 238, actions: [{ kind: "spawn", id: "B", geo: FULL }] },

  { at: 273, chord: "right", actions: [{ kind: "move", id: "B", geo: RIGHT_3_4 }] },
  { at: 287, chord: "right", actions: [{ kind: "move", id: "B", geo: RIGHT_1_2 }] },
  { at: 301, chord: "down", actions: [{ kind: "move", id: "B", geo: RIGHT_HALF_BOT_3_4 }] },
  { at: 315, chord: "down", actions: [{ kind: "move", id: "B", geo: BR_QUARTER }] },

  { at: 356, actions: [{ kind: "spawn", id: "C", geo: FULL }] },

  { at: 385, chord: "left", actions: [{ kind: "move", id: "C", geo: LEFT_3_4 }] },
  { at: 399, chord: "left", actions: [{ kind: "move", id: "C", geo: LEFT_1_2 }] },

  { at: 440, actions: [{ kind: "spawn", id: "D", geo: LEFT_1_2 }] },
  { at: 478, actions: [{ kind: "spawn", id: "E", geo: LEFT_1_2 }] },

  { at: 525, chord: "tab", actions: [{ kind: "tab" }] },
  { at: 548, chord: "tab", actions: [{ kind: "tab" }] },
  { at: 571, chord: "tab", actions: [{ kind: "tab" }] },
];

export const TOTAL_FRAMES = 660;

export const MOTION_DURATION = 8;
export const SPAWN_DURATION = 10;
export const KEYCAP_HOLD = 18;
export const KEYCAP_FADE_IN = 4;
export const KEYCAP_FADE_OUT = 8;

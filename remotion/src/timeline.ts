export type Geo = { x: number; y: number; w: number; h: number };

export const PALETTE = {
  teal: "#3CA9A0",
  blue: "#5C7CFA",
  amber: "#F0A648",
  lavender: "#B57BD9",
} as const;

export type AppType = "chrome" | "textedit" | "finder" | "ghostty";

export const APP_NAMES: Record<AppType, string> = {
  chrome: "Chrome",
  textedit: "TextEdit",
  finder: "Finder",
  ghostty: "Ghostty",
};

export const WINDOWS: Record<string, { color: string; app: AppType }> = {
  A: { color: PALETTE.teal, app: "chrome" },
  B: { color: PALETTE.blue, app: "textedit" },
  C: { color: PALETTE.amber, app: "finder" },
  D: { color: PALETTE.lavender, app: "ghostty" },
  E: { color: PALETTE.teal, app: "textedit" },
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
const RIGHT_HALF_BOT_1_2: Geo = { x: 0.5, y: 0.5, w: 0.5, h: 0.5 };
const BR_QUARTER: Geo = { x: 0.5, y: 0.5, w: 0.5, h: 0.5 };

export const FPS = 30;

// ---- Intro ----
// Single intro panel only — the workspace line moved into the caption band.
// DEMO_START sits well after the intro panel ends so they never overlap, and
// the workspace caption appears before Chrome spawns so the window arrives
// onto a screen that already has narration.
export const INTRO_END = 80;
export const DEMO_START = 130;
// Smooth desktop reveal so the wallpaper doesn't pop on with empty space.
export const DESKTOP_REVEAL_FROM = DEMO_START - 30; // 100
export const DESKTOP_REVEAL_TO = DEMO_START - 8; // 122

// ---- Demo timing knobs ----
export const MOTION_DURATION = 8;
export const SPAWN_DURATION = 18;

// Keycap burst lifecycle
export const KEY_PRESURFACE = 12;
export const KEY_POSTRELEASE = 12;
export const KEY_TAP_DURATION = 8;
export const KEY_PRESS_FRAME = 4;

// Demo beats — frames relative to DEMO_START. Action block tightened by 30
// frames overall so the wait between the workspace caption and "Push it"
// matches the rest of the inter-caption pacing.
const RAW_TIMELINE: Beat[] = [
  // Spawn A (Chrome) and let it sit while the workspace caption reads.
  { at: 0, actions: [{ kind: "spawn", id: "A", geo: FULL }] },

  // Right burst x3
  { at: 90, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_3_4 }] },
  { at: 100, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_1_2 }] },
  { at: 110, chord: "right", actions: [{ kind: "move", id: "A", geo: RIGHT_1_4 }] },

  // Direction change
  { at: 145, chord: "left", actions: [{ kind: "move", id: "A", geo: RIGHT_1_2 }] },

  // Down x2
  { at: 185, chord: "down", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_BOT_3_4 }] },
  { at: 195, chord: "down", actions: [{ kind: "move", id: "A", geo: BR_QUARTER }] },

  // Up x4 back to top-right quarter
  { at: 250, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_BOT_3_4 }] },
  { at: 260, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_FULL_H }] },
  { at: 270, chord: "up", actions: [{ kind: "move", id: "A", geo: RIGHT_HALF_TOP_3_4 }] },
  { at: 280, chord: "up", actions: [{ kind: "move", id: "A", geo: TR_QUARTER }] },

  // Spawn B (TextEdit)
  { at: 330, actions: [{ kind: "spawn", id: "B", geo: FULL }] },

  { at: 380, chord: "right", actions: [{ kind: "move", id: "B", geo: RIGHT_3_4 }] },
  { at: 390, chord: "right", actions: [{ kind: "move", id: "B", geo: RIGHT_1_2 }] },

  { at: 415, chord: "down", actions: [{ kind: "move", id: "B", geo: RIGHT_HALF_BOT_3_4 }] },
  { at: 425, chord: "down", actions: [{ kind: "move", id: "B", geo: RIGHT_HALF_BOT_1_2 }] },

  // Spawn C (Finder)
  { at: 480, actions: [{ kind: "spawn", id: "C", geo: FULL }] },

  { at: 525, chord: "left", actions: [{ kind: "move", id: "C", geo: LEFT_3_4 }] },
  { at: 535, chord: "left", actions: [{ kind: "move", id: "C", geo: LEFT_1_2 }] },

  // (Pretty cool / But wait — copy-only beats, no motion here)

  // Stack: D, E into left half
  { at: 740, actions: [{ kind: "spawn", id: "D", geo: LEFT_1_2 }] },
  { at: 780, actions: [{ kind: "spawn", id: "E", geo: LEFT_1_2 }] },

  // Tab burst
  { at: 995, chord: "tab", actions: [{ kind: "tab" }] },
  { at: 1010, chord: "tab", actions: [{ kind: "tab" }] },
  { at: 1025, chord: "tab", actions: [{ kind: "tab" }] },
];

export const TIMELINE: Beat[] = RAW_TIMELINE.map((b) => ({
  ...b,
  at: b.at + DEMO_START,
}));

export const DEMO_END = DEMO_START + 1070; // 1200

// ---- Outro ----
export const OUTRO_HOLD = 20;
export const DESKTOP_FADE_FROM = DEMO_END + OUTRO_HOLD; // 1220
export const DESKTOP_FADE_TO = DESKTOP_FADE_FROM + 30; // 1250
export const BLANK_HOLD = 18;
export const OUTRO_TEXT_FROM = DESKTOP_FADE_TO + BLANK_HOLD; // 1268
export const OUTRO_TEXT_TO = OUTRO_TEXT_FROM + 72; // 1340

export const TOTAL_FRAMES = 1350; // 45.0s — matches background_song.wav

// ---- Captions (lower-third) ----
export type Caption = { from: number; to: number; text: string };

export const CAPTIONS: Caption[] = [
  // Setup line — appears before Chrome spawns so the window arrives into an
  // already-narrated frame; carries through the early dwell.
  { from: DEMO_START - 35, to: DEMO_START + 55, text: "Say you want to arrange your workspace." },

  // Snap demo (Window A)
  { from: DEMO_START + 83, to: DEMO_START + 170, text: "Push it where you want it." },
  { from: DEMO_START + 180, to: DEMO_START + 235, text: "Pull it down." },
  { from: DEMO_START + 245, to: DEMO_START + 310, text: "Or back up." },

  // B spawn + moves
  { from: DEMO_START + 342, to: DEMO_START + 440, text: "Bring in another. It tucks right in." },

  // C spawn + moves
  { from: DEMO_START + 492, to: DEMO_START + 570, text: "Build any layout in seconds." },

  // Pre-stack transition
  { from: DEMO_START + 585, to: DEMO_START + 650, text: "Pretty cool, right?" },
  { from: DEMO_START + 660, to: DEMO_START + 730, text: "But wait. There is more!" },

  // Stack reveal — long enough to read.
  { from: DEMO_START + 785, to: DEMO_START + 880, text: "If you snap windows to the same area…" },
  { from: DEMO_START + 890, to: DEMO_START + 980, text: "they stack into an island. Get it?" },

  // Tab cycle
  { from: DEMO_START + 985, to: DEMO_START + 1065, text: "Then press Tab to flip through them." },
];

// ---- Intro / Outro panels ----
export type Panel = { from: number; to: number; lines: string[] };

export const INTRO: Panel[] = [
  { from: 8, to: INTRO_END, lines: ["Islands snaps your windows."] },
];

export const OUTRO: Panel[] = [
  { from: OUTRO_TEXT_FROM, to: OUTRO_TEXT_TO, lines: ["Islands.", "Free for macOS."] },
];

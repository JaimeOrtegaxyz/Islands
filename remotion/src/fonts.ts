import { continueRender, delayRender, staticFile } from "remotion";

export const QUICKSAND_FAMILY = "Quicksand";

let loaded = false;
let waitForFont: number | null = null;

export function ensureQuicksand(): void {
  if (loaded || typeof document === "undefined") return;
  loaded = true;
  waitForFont = delayRender("Loading Quicksand");
  const face = new FontFace(
    QUICKSAND_FAMILY,
    `url(${staticFile("Quicksand-Regular.ttf")}) format('truetype-variations')`,
    { weight: "300 700" }
  );
  face
    .load()
    .then((f) => {
      (document.fonts as unknown as { add: (f: FontFace) => void }).add(f);
      if (waitForFont !== null) continueRender(waitForFont);
    })
    .catch(() => {
      if (waitForFont !== null) continueRender(waitForFont);
    });
}

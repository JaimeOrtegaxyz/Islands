import React from "react";
import { Audio, Sequence, staticFile } from "remotion";
import { TIMELINE, TOTAL_FRAMES } from "../timeline";

// Mix levels — tuned to sit under the music without poking out.
const MUSIC_VOLUME = 0.5;
const SNAP_VOLUME = 0.65;
const SPAWN_VOLUME = 0.55;
const FLIP_VOLUME = 0.48;

export const Soundtrack: React.FC = () => {
  return (
    <>
      {/* Background music for the whole composition. */}
      <Audio src={staticFile("background_song.wav")} volume={MUSIC_VOLUME} />

      {TIMELINE.flatMap((beat) =>
        beat.actions.map((action, i) => {
          const key = `${beat.at}-${i}`;
          if (action.kind === "spawn") {
            return (
              <Sequence key={key} from={beat.at}>
                <Audio src={staticFile("spawn.mp3")} volume={SPAWN_VOLUME} />
              </Sequence>
            );
          }
          if (action.kind === "move") {
            return (
              <Sequence key={key} from={beat.at}>
                <Audio src={staticFile("snap.mp3")} volume={SNAP_VOLUME} />
              </Sequence>
            );
          }
          if (action.kind === "tab") {
            return (
              <Sequence key={key} from={beat.at}>
                <Audio src={staticFile("flip.mp3")} volume={FLIP_VOLUME} />
              </Sequence>
            );
          }
          return null;
        })
      )}
    </>
  );
};

// Re-exported so callers don't need to know the music length.
export const SOUNDTRACK_END_FRAME = TOTAL_FRAMES;

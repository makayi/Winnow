import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { AMBER, FONT, INK } from "../config";

// Opening: a wall of photos from the card. Most fall away; the keepers light up and gather.
const COLS = 8;
const ROWS = 14;
const TILE_W = 120;
const TILE_H = 80;
const GAP = 10;
const WALL_W = COLS * TILE_W + (COLS - 1) * GAP;
const WALL_X = (1080 - WALL_W) / 2;
const WALL_Y = 420;

// Wall index → keeper photo. Spread across the wall so the survivors feel scattered.
const KEEPERS: Record<number, string> = { 13: "k1", 27: "k2", 44: "hero", 58: "k3", 74: "k4", 93: "k5" };
const KEEPER_ORDER = ["k1", "hero", "k2", "k3", "k4", "k5"];

// Deterministic pseudo-random per tile.
const rand = (i: number, salt: number) => {
  const x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
  return x - Math.floor(x);
};

export const PhotoWall: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

  return (
    <AbsoluteFill style={{ fontFamily: FONT, color: INK }}>
      <AbsoluteFill
        style={{
          // Camera: a slow pull back while the wall builds, then the keepers recede as the title arrives.
          scale: interpolate(t, [0, 1.2, 2.25, 2.6], [1.1, 1, 1, 0.82], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) }),
          opacity: interpolate(t, [2.25, 2.55], [1, 0], clamp),
        }}
      >
        {Array.from({ length: COLS * ROWS }).map((_, i) => {
          const col = i % COLS;
          const row = Math.floor(i / COLS);
          const keeper = KEEPERS[i];
          const x = WALL_X + col * (TILE_W + GAP);
          const y = WALL_Y + row * (TILE_H + GAP);
          const appear = interpolate(t, [0.02 * (col + row), 0.02 * (col + row) + 0.3], [0, 1], clamp);

          if (!keeper) {
            // Fall with gravity, a little spin, staggered.
            const start = 1.05 + rand(i, 1) * 0.45;
            const fall = interpolate(t, [start, start + 0.75], [0, 1], { ...clamp, easing: Easing.in(Easing.quad) });
            return (
              <Img
                key={i}
                src={staticFile(`wall/w${String(i % 100).padStart(3, "0")}.jpg`)}
                style={{
                  position: "absolute", left: x, top: y, width: TILE_W, height: TILE_H, objectFit: "cover", borderRadius: 6,
                  opacity: appear * (1 - fall * 0.9),
                  translate: `${(rand(i, 2) - 0.5) * 160 * fall}px ${fall * 1500}px`,
                  rotate: `${(rand(i, 3) - 0.5) * 60 * fall}deg`,
                  scale: 0.92 + 0.08 * appear,
                }}
              />
            );
          }

          // Keepers: amber ring pops, then they glide into a 2 × 3 collage at the centre.
          const k = KEEPER_ORDER.indexOf(keeper);
          const tx = 90 + (k % 2) * 460;
          const ty = 560 + Math.floor(k / 2) * 330;
          const gather = interpolate(t, [1.75, 2.3], [0, 1], { ...clamp, easing: Easing.bezier(0.65, 0, 0.35, 1) });
          const ring = interpolate(t, [1.0, 1.25], [0, 1], { ...clamp, easing: Easing.bezier(0.34, 1.56, 0.64, 1) });
          return (
            <Img
              key={i}
              src={staticFile(`photos/${keeper}.jpg`)}
              style={{
                position: "absolute", objectFit: "cover",
                left: x + (tx - x) * gather, top: y + (ty - y) * gather,
                width: TILE_W + (440 - TILE_W) * gather, height: TILE_H + (293 - TILE_H) * gather,
                borderRadius: 6 + 10 * gather, opacity: appear,
                outline: `${4 * ring}px solid ${AMBER}`, outlineOffset: 2,
                boxShadow: `0 ${20 * gather}px ${50 * gather}px rgba(0,0,0,${0.25 * gather})`,
                scale: 1 + 0.12 * ring * (1 - gather),
                zIndex: 2,
              }}
            />
          );
        })}
      </AbsoluteFill>

      <div style={{ position: "absolute", top: 110, width: "100%", textAlign: "center" }}>
        <div
          style={{
            fontSize: 100, fontWeight: 800, letterSpacing: -2, lineHeight: 1.02, whiteSpace: "pre-line",
            opacity: interpolate(t, [0.1, 0.4, 1.0, 1.2], [0, 1, 1, 0], clamp),
            translate: interpolate(t, [0.1, 0.5], ["0px 30px", "0px 0px"], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) }),
          }}
        >
          {"400 photos\non your card."}
        </div>
      </div>
      <div style={{ position: "absolute", top: 110, width: "100%", textAlign: "center" }}>
        <div
          style={{
            fontSize: 100, fontWeight: 800, letterSpacing: -2, lineHeight: 1.02, whiteSpace: "pre-line",
            opacity: interpolate(t, [1.15, 1.45, 2.2, 2.45], [0, 1, 1, 0], clamp),
            translate: interpolate(t, [1.15, 1.55], ["0px 30px", "0px 0px"], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) }),
          }}
        >
          {"You want\nmaybe 20."}
        </div>
      </div>
    </AbsoluteFill>
  );
};

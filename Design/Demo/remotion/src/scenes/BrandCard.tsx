import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { FONT, INK } from "../config";

// The icon springs in, then the name and line rise in behind it.
export const BrandCard: React.FC<{ line: string; footer?: string; exit?: boolean }> = ({ line, footer, exit = true }) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const rise = (from: number) => ({
    opacity: interpolate(frame, [from * fps, (from + 0.45) * fps], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
    translate: interpolate(frame, [from * fps, (from + 0.5) * fps], ["0px 40px", "0px 0px"], {
      extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.16, 1, 0.3, 1),
    }),
  });
  const out = durationInFrames - 0.35 * fps;
  return (
    <AbsoluteFill
      style={{
        alignItems: "center", justifyContent: "center", fontFamily: FONT, color: INK,
        opacity: exit ? interpolate(frame, [out, durationInFrames], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 1,
        scale: exit ? interpolate(frame, [out, durationInFrames], [1, 0.96], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.in(Easing.cubic) }) : 1,
      }}
    >
      <Img
        src={staticFile("icon.png")}
        style={{
          width: 380, height: 380,
          scale: interpolate(frame, [0, 0.7 * fps], [0.6, 1], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.spring({ damping: 12 }), output: "perceptual-scale",
          }),
          opacity: interpolate(frame, [0, 0.2 * fps], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        }}
      />
      <div style={{ marginTop: 20, fontSize: 120, fontWeight: 800, letterSpacing: -2, ...rise(0.15) }}>Winnow</div>
      <div style={{ marginTop: 16, fontSize: 52, lineHeight: 1.25, textAlign: "center", whiteSpace: "pre-line", color: "rgba(27,27,29,0.7)", ...rise(0.3) }}>
        {line}
      </div>
      {footer ? (
        <div style={{ position: "absolute", bottom: 200, fontSize: 36, fontWeight: 500, color: "rgba(27,27,29,0.45)", ...rise(0.6) }}>{footer}</div>
      ) : null}
    </AbsoluteFill>
  );
};

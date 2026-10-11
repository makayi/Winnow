import { AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { FONT, INK } from "../config";

// A big statement that rises in and out.
export const IntroCard: React.FC<{ title: string; sub?: string }> = ({ title, sub }) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const out = durationInFrames - 0.3 * fps;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT, color: INK, padding: 100 }}>
      <div
        style={{
          textAlign: "center",
          opacity: interpolate(frame, [out, durationInFrames], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
          translate: interpolate(frame, [out, durationInFrames], ["0px 0px", "0px -50px"], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.in(Easing.cubic),
          }),
        }}
      >
        <div style={{ fontSize: 110, fontWeight: 800, lineHeight: 1.05, letterSpacing: -2, whiteSpace: "pre-line" }}>{title}</div>
        {sub ? (
          <div
            style={{
              marginTop: 36, fontSize: 52, fontWeight: 400, opacity: interpolate(frame, [0.35 * fps, 0.8 * fps], [0, 0.6], {
                extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
              translate: interpolate(frame, [0.35 * fps, 0.8 * fps], ["0px 24px", "0px 0px"], {
                extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.16, 1, 0.3, 1),
              }),
            }}
          >
            {sub}
          </div>
        ) : null}
      </div>
    </AbsoluteFill>
  );
};

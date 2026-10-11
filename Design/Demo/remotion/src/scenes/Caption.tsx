import { AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { FONT, INK } from "../config";

// Headline and supporting line that slide up into place and fade out quickly.
export const Caption: React.FC<{ title: string; sub: string }> = ({ title, sub }) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const out = durationInFrames - 0.25 * fps;
  const enter = (delay: number) => ({
    opacity: interpolate(frame, [delay * fps, (delay + 0.4) * fps, out, durationInFrames], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
    translate: interpolate(frame, [delay * fps, (delay + 0.5) * fps], ["0px 34px", "0px 0px"], {
      extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.16, 1, 0.3, 1),
    }),
  });
  return (
    <AbsoluteFill style={{ alignItems: "center", fontFamily: FONT, color: INK, paddingLeft: 80, paddingRight: 80 }}>
      <div style={{ marginTop: 150, fontSize: 84, fontWeight: 800, lineHeight: 1.05, letterSpacing: -1.5, textAlign: "center", whiteSpace: "pre-line", ...enter(0) }}>
        {title}
      </div>
      <div style={{ marginTop: 22, fontSize: 44, lineHeight: 1.2, textAlign: "center", color: "rgba(27,27,29,0.6)", ...enter(0.08) }}>{sub}</div>
    </AbsoluteFill>
  );
};

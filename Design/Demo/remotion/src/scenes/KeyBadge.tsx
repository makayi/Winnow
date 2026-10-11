import { AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { INK, ROUNDED } from "../config";

const colors: Record<string, string> = { P: "#B27A12", X: "#C4432C" };

// A key cap that pops in with a little overshoot.
export const KeyBadge: React.FC<{ label: string }> = ({ label }) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const out = durationInFrames - 0.12 * fps;
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div
        style={{
          marginTop: 1555, minWidth: 128, height: 124, padding: "0 36px", borderRadius: 28, background: "white",
          border: "3px solid rgba(0,0,0,0.08)", boxShadow: "0 10px 26px rgba(0,0,0,0.16)",
          display: "flex", alignItems: "center", justifyContent: "center",
          fontFamily: ROUNDED, fontSize: 60, fontWeight: 600, color: colors[label] ?? INK,
          scale: interpolate(frame, [0, 0.22 * fps, out, durationInFrames], [0.6, 1, 1, 0.9], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.34, 1.56, 0.64, 1), output: "perceptual-scale",
          }),
          opacity: interpolate(frame, [0, 0.07 * fps, out, durationInFrames], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        }}
      >
        {label}
      </div>
    </AbsoluteFill>
  );
};

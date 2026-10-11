import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";

// White stage with two soft tints drifting in counter-motion (ambient layer).
export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  return (
    <AbsoluteFill style={{ background: "linear-gradient(180deg, #FFFFFF 35%, #F1F2F4 100%)" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(900px 900px at ${540 + 220 * Math.sin(t * 0.18)}px ${1000 + 160 * Math.cos(t * 0.13)}px, rgba(214, 222, 236, 0.55), rgba(214, 222, 236, 0) 70%)`,
        }}
      />
      <AbsoluteFill
        style={{
          background: `radial-gradient(700px 700px at ${540 - 260 * Math.sin(t * 0.15)}px ${1150 - 140 * Math.cos(t * 0.11)}px, rgba(245, 193, 90, 0.12), rgba(245, 193, 90, 0) 70%)`,
        }}
      />
    </AbsoluteFill>
  );
};

import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { FONT, VIEW } from "../config";

// Ending: the hero photo grows from the app window to fill the frame, with a slow push, and the
// name and line settle over it.
export const CapeTownEnding: React.FC<{ line: string; footer: string }> = ({ line, footer }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
  const grow = interpolate(frame, [0, 0.9 * fps], [0, 1], { ...clamp, easing: Easing.bezier(0.65, 0, 0.35, 1) });
  const rise = (from: number) => ({
    opacity: interpolate(frame, [from * fps, (from + 0.5) * fps], [0, 1], clamp),
    translate: interpolate(frame, [from * fps, (from + 0.6) * fps], ["0px 40px", "0px 0px"], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) }),
  });
  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute", overflow: "hidden",
          left: VIEW.x * (1 - grow), top: VIEW.y * (1 - grow),
          width: VIEW.w + (1080 - VIEW.w) * grow, height: VIEW.h + (1920 - VIEW.h) * grow,
          borderRadius: VIEW.radius * (1 - grow),
          opacity: interpolate(frame, [0, 0.2 * fps], [0, 1], clamp),
        }}
      >
        <Img
          src={staticFile("photos/hero.jpg")}
          style={{
            width: "100%", height: "100%", objectFit: "cover", objectPosition: "60% 50%",
            scale: interpolate(frame, [0, 4 * fps], [1.18, 1.04], { ...clamp, easing: Easing.out(Easing.quad) }),
          }}
        />
        <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,0,0) 40%, rgba(0,0,0,0.55) 100%)", opacity: grow }} />
      </div>
      <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "center", paddingBottom: 230, fontFamily: FONT, color: "white", textAlign: "center" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 22, ...rise(0.7) }}>
          <Img src={staticFile("icon.png")} style={{ width: 120, height: 120 }} />
          <div style={{ fontSize: 110, fontWeight: 800, letterSpacing: -2, textShadow: "0 4px 30px rgba(0,0,0,0.35)" }}>Winnow</div>
        </div>
        <div style={{ marginTop: 22, fontSize: 56, lineHeight: 1.25, whiteSpace: "pre-line", textShadow: "0 2px 20px rgba(0,0,0,0.4)", ...rise(0.9) }}>{line}</div>
        <div style={{ marginTop: 40, fontSize: 38, fontWeight: 500, color: "rgba(255,255,255,0.8)", ...rise(1.2) }}>{footer}</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

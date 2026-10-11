import { Video } from "@remotion/media";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { cameraMoves, cursorClicks, cursorPath, FONT, INK, keyPresses, punchAmount, punchKeys, VIEW } from "../config";

const smooth = Easing.bezier(0.65, 0, 0.35, 1);

// Camera state at time t (seconds into the recording): eased moves plus a punch-in on each pick.
const cameraAt = (t: number) => {
  let cur = { cx: 0.5, cy: 0.5, zoom: 1 };
  for (const m of cameraMoves) {
    if (t <= m.t) break;
    const p = smooth(Math.min(1, (t - m.t) / m.dur));
    cur = { cx: cur.cx + (m.cx - cur.cx) * p, cy: cur.cy + (m.cy - cur.cy) * p, zoom: cur.zoom + (m.zoom - cur.zoom) * p };
  }
  let punch = 0;
  for (const k of keyPresses) {
    const d = t - k.t;
    if (punchKeys.includes(k.value) && d >= 0 && d < 0.45) {
      punch += punchAmount * Math.sin((Math.min(1, d / 0.12) * Math.PI) / 2) * Math.exp(-d * 7);
    }
  }
  return { ...cur, zoom: cur.zoom * (1 + punch) };
};

// Cursor position at time t: glides (0.55 s, eased) from each point to the next.
const cursorAt = (t: number) => {
  let x = cursorPath[0].x, y = cursorPath[0].y, show = 0;
  for (const p of cursorPath) {
    if (t < p.t) break;
    const k = smooth(Math.min(1, (t - p.t) / 0.55));
    x = x + (p.x - x) * k;
    y = y + (p.y - y) * k;
    if (p.show !== undefined) show = p.show;
  }
  return { x, y, show };
};

const Cursor: React.FC<{ t: number; px: number; py: number; size: number }> = ({ t, px, py, size }) => {
  const click = cursorClicks.map((c) => t - c).find((d) => d >= -0.08 && d < 0.6);
  const press = click === undefined ? 1 : 1 - 0.18 * Math.max(0, 1 - Math.abs(click) / 0.12);
  return (
    <>
      {click !== undefined && click >= 0 ? (
        <div
          style={{
            position: "absolute", left: px - size, top: py - size, width: size * 2, height: size * 2, borderRadius: "50%",
            border: `${3}px solid rgba(10,132,255,${0.8 * (1 - click / 0.6)})`, background: `rgba(10,132,255,${0.15 * (1 - click / 0.6)})`,
            scale: 0.3 + 1.2 * Math.min(1, click / 0.45),
          }}
        />
      ) : null}
      <svg width={size} height={size * 1.5} viewBox="0 0 20 30" style={{ position: "absolute", left: px - size * 0.12, top: py - size * 0.06, scale: press, transformOrigin: "top left", filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.35))" }}>
        <path d="M1.5 1.5 L1.5 23 L6.8 18 L10.4 26.5 L14 25 L10.5 16.8 L17.6 16.8 Z" fill="black" stroke="white" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    </>
  );
};

// The app recording in a floating window: springs in, the camera moves inside it, then it eases away.
export const AppWindow: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  const t = frame / fps;
  const cam = cameraAt(t);

  const w = VIEW.w * cam.zoom;
  const h = VIEW.h * cam.zoom;
  const left = Math.min(0, Math.max(VIEW.w - w, VIEW.w / 2 - cam.cx * w));
  const top = Math.min(0, Math.max(VIEW.h - h, VIEW.h / 2 - cam.cy * h));
  const exitFrom = durationInFrames - 0.5 * fps;

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute", left: VIEW.x, top: VIEW.y, width: VIEW.w, height: VIEW.h,
          borderRadius: VIEW.radius, overflow: "hidden", background: "white",
          boxShadow: "0 30px 80px rgba(0,0,0,0.22), 0 4px 14px rgba(0,0,0,0.08)",
          scale: interpolate(frame, [0, 0.8 * fps, exitFrom, durationInFrames], [0.86, 1, 1, 0.92], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.spring({ damping: 14 }), output: "perceptual-scale",
          }),
          translate: interpolate(frame, [0, 0.7 * fps, exitFrom, durationInFrames], ["0px 90px", "0px 0px", "0px 0px", "0px -60px"], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.bezier(0.16, 1, 0.3, 1),
          }),
          opacity: interpolate(frame, [0, 0.35 * fps, exitFrom, durationInFrames], [0, 1, 1, 0], {
            extrapolateLeft: "clamp", extrapolateRight: "clamp",
          }),
        }}
      >
        <Video
          src={staticFile("recording.mp4")}
          muted
          premountFor={fps}
          style={{ position: "absolute", left, top, width: w, height: h }}
        />
        {(() => {
          const c = cursorAt(t);
          if (c.show <= 0) return null;
          return <Cursor t={t} px={left + c.x * w} py={top + c.y * h} size={30 * Math.sqrt(cam.zoom)} />;
        })()}
      </div>
      <div
        style={{
          position: "absolute", top: 1700, width: "100%", display: "flex", justifyContent: "center", alignItems: "center", gap: 16,
          fontFamily: FONT, fontSize: 40, fontWeight: 600, color: INK,
          opacity: interpolate(frame, [0.2 * fps, 0.7 * fps, exitFrom, durationInFrames], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
        }}
      >
        <Img src={staticFile("icon.png")} style={{ width: 72, height: 72 }} />
        Winnow
      </div>
    </AbsoluteFill>
  );
};

import { Audio } from "@remotion/media";
import { AbsoluteFill, Sequence, staticFile, useVideoConfig } from "remotion";
import { APP_AT, CARD2_AT, captions, cursorClicks, END_AT, keyPresses, recordingLength, scenes, TOTAL } from "./config";
import { AppWindow } from "./scenes/AppWindow";
import { Background } from "./scenes/Background";
import { BrandCard } from "./scenes/BrandCard";
import { Caption } from "./scenes/Caption";
import { CapeTownEnding } from "./scenes/CapeTownEnding";
import { PhotoWall } from "./scenes/PhotoWall";
import { KeyBadge } from "./scenes/KeyBadge";

export const WinnowDemo: React.FC = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill>
      <Background />

      <Sequence name="Photo wall" durationInFrames={Math.round((CARD2_AT + 0.3) * fps)} premountFor={fps}>
        <PhotoWall />
      </Sequence>
      <Sequence name="Title" from={Math.round(CARD2_AT * fps)} durationInFrames={Math.round((APP_AT - CARD2_AT + 0.2) * fps)} premountFor={fps}>
        <BrandCard line={"Pick your best,\nright off the card."} />
      </Sequence>

      <Sequence name="App" from={Math.round(APP_AT * fps)} durationInFrames={Math.round((END_AT - APP_AT + 0.5) * fps)} premountFor={fps}>
        <AppWindow />
      </Sequence>

      {/* One caption per scene of the recording, until the next scene starts. */}
      {scenes.map((s, i) => {
        const start = APP_AT + s.t + (i === 0 ? 0.35 : 0.05);
        const end = APP_AT + (i + 1 < scenes.length ? scenes[i + 1].t : recordingLength - 0.2);
        const copy = captions[s.value];
        return (
          <Sequence key={s.value} name={`Caption: ${s.value}`} from={Math.round(start * fps)} durationInFrames={Math.round((end - start) * fps)} premountFor={fps}>
            <Caption title={copy.title} sub={copy.sub} />
          </Sequence>
        );
      })}

      {/* A key badge for every key press in the recording. */}
      {keyPresses.filter((k) => !cursorClicks.some((c) => Math.abs(c - k.t) < 0.1)).map((k, i, shown) => {
        const next = i + 1 < shown.length ? shown[i + 1].t : k.t + 1;
        const dur = Math.max(0.3, Math.min(0.6, next - k.t - 0.03));
        return (
          <Sequence key={`${k.t}`} name={`Key ${k.value}`} from={Math.round((APP_AT + k.t) * fps)} durationInFrames={Math.round(dur * fps)} premountFor={fps}>
            <KeyBadge label={k.value} />
          </Sequence>
        );
      })}

      <Sequence name="Cape Town ending" from={Math.round((END_AT - 0.1) * fps)} durationInFrames={Math.round((TOTAL - END_AT + 0.1) * fps)} premountFor={fps}>
        <CapeTownEnding line={"See every shot big.\nKeep only your favourites."} footer="Made for Mac" />
      </Sequence>

      <Audio src={staticFile("music.wav")} premountFor={fps} />
    </AbsoluteFill>
  );
};

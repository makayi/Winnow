import { Composition, Folder } from "remotion";
import { FPS, HEIGHT, TOTAL, WIDTH } from "./config";
import { AppWindow } from "./scenes/AppWindow";
import { BrandCard } from "./scenes/BrandCard";
import { IntroCard } from "./scenes/IntroCard";
import { WinnowDemo } from "./WinnowDemo";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="WinnowDemo" component={WinnowDemo} durationInFrames={Math.round(TOTAL * FPS)} fps={FPS} width={WIDTH} height={HEIGHT} />
      <Folder name="Scenes">
        <Composition id="Hook" component={IntroCard} durationInFrames={71} fps={FPS} width={WIDTH} height={HEIGHT}
          defaultProps={{ title: "400 photos\non your card.", sub: "You want maybe 20." }} />
        <Composition id="Title" component={BrandCard} durationInFrames={82} fps={FPS} width={WIDTH} height={HEIGHT}
          defaultProps={{ line: "Pick your best,\nright off the card." }} />
        <Composition id="App" component={AppWindow} durationInFrames={760} fps={FPS} width={WIDTH} height={HEIGHT} />
      </Folder>
    </>
  );
};

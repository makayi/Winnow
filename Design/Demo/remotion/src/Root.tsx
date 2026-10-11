import { Composition, Folder } from "remotion";
import { FPS, HEIGHT, TOTAL, WIDTH } from "./config";
import { AppWindow } from "./scenes/AppWindow";
import { BrandCard } from "./scenes/BrandCard";
import { CapeTownEnding } from "./scenes/CapeTownEnding";
import { PhotoWall } from "./scenes/PhotoWall";
import { WinnowDemo } from "./WinnowDemo";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="WinnowDemo" component={WinnowDemo} durationInFrames={Math.round(TOTAL * FPS)} fps={FPS} width={WIDTH} height={HEIGHT} />
      <Folder name="Scenes">
        <Composition id="PhotoWall" component={PhotoWall} durationInFrames={80} fps={FPS} width={WIDTH} height={HEIGHT} />
        <Composition id="CapeTownEnding" component={CapeTownEnding} durationInFrames={110} fps={FPS} width={WIDTH} height={HEIGHT}
          defaultProps={{ line: "See every shot big.\nKeep only your favourites.", footer: "Made for Mac" }} />
        <Composition id="Title" component={BrandCard} durationInFrames={82} fps={FPS} width={WIDTH} height={HEIGHT}
          defaultProps={{ line: "Pick your best,\nright off the card." }} />
        <Composition id="App" component={AppWindow} durationInFrames={760} fps={FPS} width={WIDTH} height={HEIGHT} />
      </Folder>
    </>
  );
};

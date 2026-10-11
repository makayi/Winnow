// Timing, copy and camera for the Winnow demo. Edit here; the scenes read from it.
import timeline from "./data/timeline.json";

export const FPS = 30;
export const WIDTH = 1080;
export const HEIGHT = 1920;

// Music sync ("Product – Product Launch", starting 0.24 s in): opening hit at 0,
// second hit at 4.898 s, when the app appears.
export const CARD2_AT = 2.364;
export const APP_AT = 4.898;

const recordingLength = timeline.duration[0].t;
export const END_AT = APP_AT + recordingLength - 0.2;
export const TOTAL = END_AT + 3.6;

export const sec = (s: number) => Math.round(s * FPS);

export const FONT = 'system-ui, -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';
export const ROUNDED = 'ui-rounded, "SF Pro Rounded", system-ui, sans-serif';
export const INK = "#1B1B1D";
export const AMBER = "#F5C15A";

// Where the app window sits in the portrait frame, and the recording's pixel size.
export const VIEW = { x: 40, y: 560, w: 1000, h: 958, radius: 26 };
export const SOURCE = { w: 2080, h: 1994 };

export type TimelineEvent = { t: number; kind: string; value: string };
export const scenes = (timeline.events as TimelineEvent[]).filter((e) => e.kind === "scene");
export const keyPresses = (timeline.events as TimelineEvent[]).filter((e) => e.kind === "key");
export { recordingLength };

export const captions: Record<string, { title: string; sub: string }> = {
  grow: { title: "See every shot big", sub: "Right off the SD card. Nothing to import first." },
  cull: { title: "Pick your favourites\nwith one key", sub: "Press P to keep a photo, X to skip it" },
  loupe: { title: "Look closer before\nyou decide", sub: "With the camera settings for every shot" },
  import: { title: "Copy only the ones\nyou picked", sub: "Straight into your own folders, ready for Lightroom" },
  delete: { title: "Then free up your card", sub: "Winnow only deletes photos it copied safely" },
};

// Virtual camera over the recording. t is seconds into the recording; cx, cy is the focus point
// as a fraction of the window; zoom 1 shows the whole window. Each move eases from the last.
export const cameraMoves = [
  { t: 1.3, dur: 2.4, cx: 0.55, cy: 0.48, zoom: 1.08 },   // slow push while thumbnails grow
  { t: 3.9, dur: 0.8, cx: 0.615, cy: 0.5, zoom: 1.32 },   // into the grid for picking
  { t: 10.85, dur: 0.8, cx: 0.36, cy: 0.47, zoom: 1.55 }, // the photo, large
  { t: 13.15, dur: 0.7, cx: 0.83, cy: 0.25, zoom: 2.25 }, // Pick button and camera settings
  { t: 15.1, dur: 0.7, cx: 0.5, cy: 0.5, zoom: 1.0 },     // back out to the grid
  { t: 16.3, dur: 0.8, cx: 0.615, cy: 0.5, zoom: 1.62 },  // import sheet
  { t: 18.6, dur: 0.6, cx: 0.615, cy: 0.5, zoom: 1.78 },  // copying
  { t: 21.7, dur: 1.2, cx: 0.615, cy: 0.5, zoom: 1.9 },   // deleted from the card
  { t: 23.7, dur: 0.9, cx: 0.5, cy: 0.5, zoom: 1.0 },     // pull back out
];
export const punchKeys = ["P", "X"];
export const punchAmount = 0.035;

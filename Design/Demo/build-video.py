#!/usr/bin/env python3
"""Composes the portrait product demo from recording.mov, timeline.json and the rendered assets.

usage: build-video.py <demo dir> <assets dir> <output.mp4> [soundtrack.wav] [--cards 0,2.065 --t0 3.88]

--cards are the start times of the intro cards and --t0 is when the app footage starts, so both
can be placed on the music's beats.
"""
import argparse, json, subprocess

ap = argparse.ArgumentParser()
ap.add_argument("demo"); ap.add_argument("assets"); ap.add_argument("output"); ap.add_argument("soundtrack", nargs="?")
ap.add_argument("--cards", default="0,2"); ap.add_argument("--t0", type=float, default=4.0)
args = ap.parse_args()
demo, assets, output, soundtrack = args.demo, args.assets, args.output, args.soundtrack
timeline = json.load(open(f"{demo}/timeline.json"))
events = timeline["events"]
rec_len = timeline["duration"][0]["t"]

INTRO = ["intro-1", "title"]
CARD_STARTS = [float(x) for x in args.cards.split(",")]
T0 = args.t0                 # recording starts as the last intro card fades
END_IN = T0 + rec_len - 0.2  # end card fades in over the last frames
TOTAL = END_IN + 3.6
WIN_X, WIN_Y, WIN_W, WIN_H = 40, 560, 1000, 958
KEY_FILES = {"P": "P", "X": "X", "→": "right", "Space": "space", "⌘ +": "cmd-plus", "⌘ I": "cmd-i", "↩": "return"}

inputs, filters, layers = [], [], []

def add_input(args):
    inputs.extend(args)
    return len([a for a in inputs if a == "-i"]) - 1

def still(name, start, dur, fade_in=0.3, fade_out=0.3):
    """A full-canvas PNG shown from start for dur seconds, with alpha fades."""
    idx = add_input(["-loop", "1", "-framerate", "30", "-t", f"{dur:.3f}", "-i", f"{assets}/{name}.png"])
    label = f"s{idx}"
    chain = f"[{idx}:v]format=rgba"
    if fade_in: chain += f",fade=t=in:st=0:d={fade_in}:alpha=1"
    if fade_out: chain += f",fade=t=out:st={max(dur - fade_out, 0):.3f}:d={fade_out}:alpha=1"
    chain += f",setpts=PTS+{start:.3f}/TB[{label}]"
    filters.append(chain)
    layers.append((label, 0, 0))

bg = add_input(["-loop", "1", "-framerate", "30", "-t", f"{TOTAL:.3f}", "-i", f"{assets}/bg.png"])
shadow = add_input(["-loop", "1", "-framerate", "30", "-t", f"{TOTAL:.3f}", "-i", f"{assets}/shadow.png"])
rec = add_input(["-i", f"{demo}/recording.mov"])
mask = add_input(["-loop", "1", "-framerate", "30", "-t", f"{rec_len + 1:.3f}", "-i", f"{assets}/mask.png"])

filters.append(f"[{rec}:v]fps=30,scale={WIN_W}:{WIN_H}:flags=lanczos,format=rgba[recs]")
filters.append(f"[{mask}:v]format=gray,scale={WIN_W}:{WIN_H}[m]")
filters.append(f"[recs][m]alphamerge,setpts=PTS+{T0}/TB[win]")

# Captions: one per scene, until the next scene starts.
scenes = [e for e in events if e["kind"] == "scene"]
for i, s in enumerate(scenes):
    start = T0 + s["t"] + (0.25 if i == 0 else 0)
    end = T0 + (scenes[i + 1]["t"] if i + 1 < len(scenes) else rec_len)
    still(f"cap-{s['value']}", start, end - start)

# Key badges, timed to the real key events.
keys = [e for e in events if e["kind"] == "key"]
for i, k in enumerate(keys):
    nxt = keys[i + 1]["t"] if i + 1 < len(keys) else k["t"] + 1
    dur = max(0.3, min(0.6, nxt - k["t"] - 0.03))
    still(f"key-{KEY_FILES[k['value']]}", T0 + k["t"], dur, fade_in=0.06, fade_out=0.12)

still("brand", T0, END_IN - T0 + 0.4, fade_in=0.4, fade_out=0)
for i, name in enumerate(INTRO):
    last = i == len(INTRO) - 1
    start = CARD_STARTS[i]
    end = T0 if last else CARD_STARTS[i + 1]
    still(name, start, end - start + (0.4 if last else 0.2), fade_in=0 if i == 0 else 0.2, fade_out=0.45 if last else 0.2)
still("end", END_IN, TOTAL - END_IN, fade_in=0.45, fade_out=0)

graph = [f"[{bg}:v][{shadow}:v]overlay=0:0[base0]", f"[base0][win]overlay={WIN_X}:{WIN_Y}:eof_action=repeat[base1]"]
prev = "base1"
for n, (label, x, y) in enumerate(layers):
    out = f"o{n}"
    graph.append(f"[{prev}][{label}]overlay={x}:{y}:eof_action=pass[{out}]")
    prev = out
filters += graph
filters.append(f"[{prev}]format=yuv420p,trim=duration={TOTAL:.3f}[outv]")

audio = []
if soundtrack:
    a = add_input(["-i", soundtrack])
    # Normalise to -16 LUFS, a common target for social video.
    filters.append(f"[{a}:a]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,atrim=duration={TOTAL:.3f}[outa]")
    audio = ["-map", "[outa]", "-c:a", "aac", "-b:a", "192k"]

cmd = ["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filters), "-map", "[outv]", *audio,
       "-r", "30", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-profile:v", "high", "-movflags", "+faststart", output]
subprocess.run(cmd, check=True)
print(f"wrote {output} ({TOTAL:.1f}s, {len(keys)} key badges, {len(scenes)} captions)")

#!/usr/bin/env python3
"""Lays a music track under the demo and adds very soft key clicks from timeline.json.

usage: mix-music.py <timeline.json> <track> <out.wav> --t0 3.88 [--offset 0] [--length 32.6]

--offset is where in the track the video starts. The music fades out over the last 2.5 s.
"""
import argparse, json, math, random, struct, subprocess, wave

ap = argparse.ArgumentParser()
ap.add_argument("timeline"); ap.add_argument("track"); ap.add_argument("out")
ap.add_argument("--t0", type=float, required=True); ap.add_argument("--offset", type=float, default=0.0)
ap.add_argument("--length", type=float); ap.add_argument("--click-gain", type=float, default=0.12)
a = ap.parse_args()

tl = json.load(open(a.timeline))
rec_len = tl["duration"][0]["t"]
length = a.length or (a.t0 + rec_len - 0.2 + 3.6)
SR = 48000

# Soft clicks: a short filtered tick at each key press.
random.seed(5)
n = int(length * SR)
buf = [0.0] * n
tick = []
prev = 0.0
for k in range(int(0.025 * SR)):
    x = random.uniform(-1, 1); hp = x - 0.7 * prev; prev = x
    tick.append(hp * math.exp(-(k / SR) * 220))
for e in tl["events"]:
    if e["kind"] == "key":
        i0 = int((a.t0 + e["t"]) * SR)
        for k, v in enumerate(tick):
            if 0 <= i0 + k < n: buf[i0 + k] += v * a.click_gain
clicks = a.out + ".clicks.wav"
with wave.open(clicks, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32000)) for v in buf))

fade = 2.5
graph = (f"[0:a]atrim=start={a.offset}:duration={length},asetpts=PTS-STARTPTS,aresample={SR},"
         f"afade=t=out:st={length - fade:.3f}:d={fade}[m];"
         f"[1:a]aresample={SR},pan=stereo|c0=c0|c1=c0[c];"
         f"[m][c]amix=inputs=2:normalize=0,alimiter=limit=0.95[out]")
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.track, "-i", clicks, "-filter_complex", graph, "-map", "[out]",
                "-t", f"{length:.3f}", a.out], check=True)
print(f"wrote {a.out} ({length:.1f}s from {a.offset:.2f}s into the track)")

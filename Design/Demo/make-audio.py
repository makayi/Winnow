#!/usr/bin/env python3
"""Composes the demo's soundtrack in code: an upbeat 120 bpm pop/house cue in D major
(I–V–vi–IV) with four-on-the-floor drums, a bouncing bass, offbeat chord stabs and a lead
hook, plus soft key clicks and a chime timed from timeline.json. No samples or third-party
audio, so there is nothing to license.

usage: make-audio.py <timeline.json> <out.wav> [intro_length=8.0]
"""
import json, math, random, struct, sys, wave

SR = 44100
timeline = json.load(open(sys.argv[1]))
out = sys.argv[2]
T0 = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
events = timeline["events"]
rec_len = timeline["duration"][0]["t"]
END_IN = T0 + rec_len - 0.2
TOTAL = END_IN + 3.6
N = int(TOTAL * SR)
random.seed(3)

BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
EIGHTH = BEAT / 2
ORIGIN = T0 - math.ceil(T0 / BAR) * BAR  # intro bars play under the opening cards; the groove lands with the app
scenes = {e["value"]: T0 + e["t"] for e in events if e["kind"] == "scene"}
LEAD_IN = scenes.get("cull", T0 + 4)

class Bus:
    def __init__(self): self.l = [0.0] * N; self.r = [0.0] * N
    def add(self, start, samples, pan=0.0, gain=1.0):
        i0 = int(round(start * SR))
        gl, gr = gain * math.cos((pan + 1) * math.pi / 4), gain * math.sin((pan + 1) * math.pi / 4)
        l, r = self.l, self.r
        for k, v in enumerate(samples):
            i = i0 + k
            if 0 <= i < N:
                l[i] += v * gl
                r[i] += v * gr

music, drums, sfx = Bus(), Bus(), Bus()
cache = {}

def midi(n): return 440.0 * 2 ** ((n - 69) / 12)

def lowpass(x, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out

def saw(freq, dur, harmonics, env):
    n = int(dur * SR)
    hs = [h for h in range(1, harmonics + 1) if freq * h < 12000]
    w = 2 * math.pi * freq / SR
    return [env(k / SR) * sum(math.sin(w * h * k) / h for h in hs) * 0.6 for k in range(n)]

def note(kind, n, dur):
    key = (kind, n, round(dur, 3))
    if key in cache: return cache[key]
    f = midi(n)
    if kind == "bass":
        s = lowpass(saw(f, dur, 10, lambda t: min(1, t / 0.004) * math.exp(-t * 6) * (1 if t < dur - 0.02 else max(0, (dur - t) / 0.02))), 900)
    elif kind == "stab":
        s = lowpass(saw(f, dur, 14, lambda t: min(1, t / 0.003) * math.exp(-t * 11)), 2600)
    elif kind == "lead":
        # Square-ish pluck: odd harmonics with a quick decay.
        n_ = int(dur * SR); w = 2 * math.pi * f / SR
        s = [min(1, (k / SR) / 0.003) * math.exp(-(k / SR) * 4.5) *
             (math.sin(w * k) + math.sin(3 * w * k) / 3 * 0.7 + math.sin(5 * w * k) / 5 * 0.4 + 0.25 * math.sin(2 * w * k))
             for k in range(n_)]
    elif kind == "pad":
        s = lowpass(saw(f, dur, 8, lambda t: min(1, t / 0.6) * min(1, max(0, dur - t) / 0.6)), 1400)
    cache[key] = s
    return s

def kick():
    if "kick" not in cache:
        out, ph = [], 0.0
        for k in range(int(0.3 * SR)):
            t = k / SR
            ph += 2 * math.pi * (50 + 110 * math.exp(-t * 35)) / SR
            out.append(math.sin(ph) * math.exp(-t * 11) + (random.uniform(-1, 1) * 0.15 * math.exp(-t * 300)))
        cache["kick"] = out
    return cache["kick"]

def noise_hit(name, dur, decay, hp, lp):
    if name not in cache:
        x = [random.uniform(-1, 1) for _ in range(int(dur * SR))]
        lo = lowpass(x, lp)
        hi_cut = lowpass(lo, hp)
        cache[name] = [(a - b) * math.exp(-(k / SR) * decay) for k, (a, b) in enumerate(zip(lo, hi_cut))]
    return cache[name]

def clap():
    if "clap" not in cache:
        body = noise_hit("clapbody", 0.25, 18, 900, 5000)
        out = [0.0] * len(body)
        for d in (0, 0.011, 0.022):  # three quick bursts
            o = int(d * SR)
            for k in range(len(body) - o):
                out[k + o] += body[k] * (0.7 if d else 1.0)
        cache["clap"] = out
    return cache["clap"]

# Progression: D – A – Bm – G
chords = [(50, [62, 66, 69]), (45, [61, 64, 69]), (47, [62, 66, 71]), (43, [62, 67, 71])]
# Lead hook, (eighth step, midi, length in eighths) per bar.
hook = [
    [(0, 69, 1), (2, 66, 1), (3, 69, 1), (5, 71, 1), (6, 69, 2)],
    [(0, 73, 1), (2, 69, 1), (3, 76, 2), (6, 73, 2)],
    [(0, 74, 1), (2, 71, 1), (3, 78, 1), (5, 76, 1), (6, 74, 2)],
    [(0, 71, 1), (2, 74, 1), (3, 79, 2), (6, 78, 1), (7, 76, 1)],
]

last_bar = int((END_IN - ORIGIN) / BAR)
kick_times = []
for b in range(last_bar + 1):
    t0 = ORIGIN + b * BAR
    root, tri = chords[b % 4]
    intro = t0 < T0 - 0.01
    # Pad underneath everything.
    for i, n in enumerate(tri):
        music.add(t0, note("pad", n, BAR), pan=-0.4 + 0.4 * i, gain=0.05 if not intro else 0.08)
    # Offbeat chord stabs (muffled during the intro).
    for step in (1, 3, 5, 7):
        for i, n in enumerate(tri):
            s = note("stab", n + 12 if not intro else n, EIGHTH * 0.9)
            music.add(t0 + step * EIGHTH, s, pan=-0.3 + 0.3 * i, gain=0.07 if not intro else 0.04)
    # Hats on every eighth from the start; open-ish hat on the offbeats.
    for step in range(8):
        h = noise_hit("hat", 0.05, 70, 7000, 14000) if step % 2 == 0 else noise_hit("ohat", 0.12, 28, 6500, 14000)
        drums.add(t0 + step * EIGHTH, h, pan=0.3, gain=0.12 if step % 2 else 0.07)
    if intro:
        continue
    # Four on the floor, claps on 2 and 4.
    for beat in range(4):
        drums.add(t0 + beat * BEAT, kick(), gain=0.9)
        kick_times.append(t0 + beat * BEAT)
        if beat in (1, 3):
            drums.add(t0 + beat * BEAT, clap(), pan=-0.1, gain=0.35)
    # Bass: bouncing eighths with octave pops.
    for step in range(8):
        n = root + (12 if step in (3, 6) else 0)
        music.add(t0 + step * EIGHTH, note("bass", n, EIGHTH * 0.92), gain=0.32)
    # Lead hook once culling starts, with a dotted-eighth echo.
    if t0 + BAR > LEAD_IN + 0.01:
        for step, n, length in hook[b % 4]:
            t = t0 + step * EIGHTH
            if t < LEAD_IN - 0.01: continue
            s = note("lead", n, length * EIGHTH + 0.25)
            music.add(t, s, pan=0.1, gain=0.12)
            music.add(t + 0.75 * BEAT, s, pan=-0.35, gain=0.04)

# Final chord under the end card.
end_t = ORIGIN + (last_bar + 1) * BAR
for i, n in enumerate([50, 62, 66, 69, 74]):
    music.add(end_t, note("pad", n, 2.6), pan=-0.4 + 0.2 * i, gain=0.09)
    music.add(end_t, note("stab", n + 12, 0.6), pan=-0.4 + 0.2 * i, gain=0.08)
drums.add(end_t, kick(), gain=0.9)
drums.add(end_t, noise_hit("crash", 1.6, 2.6, 5000, 15000), pan=0.2, gain=0.18)

# UI sounds: soft clicks on key presses, a chime when the import lands.
click = noise_hit("click", 0.03, 180, 2500, 9000)
for e in events:
    if e["kind"] == "key":
        sfx.add(T0 + e["t"], click, gain=0.35)
if "delete" in scenes:
    for j, n in enumerate([81, 85, 88]):
        w = 2 * math.pi * midi(n) / SR
        bell = [math.sin(w * k) * math.exp(-(k / SR) * 3.5) * min(1, (k / SR) / 0.005) for k in range(int(1.6 * SR))]
        sfx.add(scenes["delete"] + 0.05 + j * 0.08, bell, pan=-0.2 + 0.2 * j, gain=0.08)

# Mix: light sidechain on the music from the kick, then fades and a soft limiter.
duck = [1.0] * N
for t in kick_times + [end_t]:
    i0 = int(t * SR)
    for k in range(int(0.22 * SR)):
        i = i0 + k
        if i < N: duck[i] = min(duck[i], 0.55 + 0.45 * (k / (0.22 * SR)))

fade_in, fade_out = 0.4, 1.8
L, R = [0.0] * N, [0.0] * N
peak = 0.0
for i in range(N):
    t = i / SR
    g = min(1.0, t / fade_in) * min(1.0, (TOTAL - t) / fade_out)
    l = (music.l[i] * duck[i] + drums.l[i] + sfx.l[i]) * g
    r = (music.r[i] * duck[i] + drums.r[i] + sfx.r[i]) * g
    L[i], R[i] = math.tanh(l * 1.2) * 0.9, math.tanh(r * 1.2) * 0.9
    peak = max(peak, abs(L[i]), abs(R[i]))

with wave.open(out, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<hh", int(L[i] * 32000), int(R[i] * 32000)) for i in range(N)))
print(f"wrote {out} ({TOTAL:.1f}s, {BPM} bpm, peak {peak:.2f})")

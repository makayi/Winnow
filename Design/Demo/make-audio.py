#!/usr/bin/env python3
"""Synthesises the demo's soundtrack: an original warm instrumental bed plus UI sounds
(key clicks, a chime when the import lands and on the end card), timed from timeline.json.
No samples or third-party audio, so there are no licensing questions.

usage: make-audio.py <timeline.json> <out.wav> [title_offset=2.2]
"""
import json, math, random, struct, sys, wave

SR = 44100
timeline = json.load(open(sys.argv[1]))
out = sys.argv[2]
T0 = float(sys.argv[3]) if len(sys.argv) > 3 else 2.2
rec_len = timeline["duration"][0]["t"]
END_IN = T0 + rec_len - 0.2
TOTAL = END_IN + 3.6
N = int(TOTAL * SR)
L = [0.0] * N
R = [0.0] * N
random.seed(7)

def midi(n): return 440.0 * 2 ** ((n - 69) / 12)

def add(buf_l, buf_r, start, samples, pan=0.0, gain=1.0):
    i0 = int(start * SR)
    gl, gr = gain * math.cos((pan + 1) * math.pi / 4), gain * math.sin((pan + 1) * math.pi / 4)
    for k, v in enumerate(samples):
        i = i0 + k
        if 0 <= i < N:
            buf_l[i] += v * gl
            buf_r[i] += v * gr

def pad_note(freq, dur, attack=0.9, release=1.4):
    n = int((dur + release) * SR)
    out = []
    det = (1.0, 1.0045, 0.9962)
    for k in range(n):
        t = k / SR
        env = min(1.0, t / attack) if t < dur else max(0.0, 1 - (t - dur) / release)
        s = 0.0
        for d in det:
            p = 2 * math.pi * freq * d * t
            s += math.sin(p) + 0.32 * math.sin(2 * p) + 0.12 * math.sin(3 * p)
        out.append(s / 3 * env * env)
    return out

def pluck(freq, dur=0.9):
    n = int(dur * SR)
    out = []
    for k in range(n):
        t = k / SR
        env = math.exp(-t * 5.5) * min(1.0, t / 0.004)
        p = 2 * math.pi * freq * t
        out.append((math.sin(p) + 0.45 * math.sin(2 * p) * math.exp(-t * 9) + 0.15 * math.sin(3 * p) * math.exp(-t * 14)) * env)
    return out

def kick():
    n = int(0.35 * SR)
    out, phase = [], 0.0
    for k in range(n):
        t = k / SR
        f = 48 + 90 * math.exp(-t * 28)
        phase += 2 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-t * 9))
    return out

def shaker():
    n = int(0.09 * SR)
    out, prev = [], 0.0
    for k in range(n):
        t = k / SR
        x = random.uniform(-1, 1)
        hp = x - prev  # crude high-pass
        prev = x
        out.append(hp * math.exp(-t * 55) * min(1, t / 0.003))
    return out

def click():
    n = int(0.05 * SR)
    out, prev = [], 0.0
    for k in range(n):
        t = k / SR
        x = random.uniform(-1, 1)
        hp = x - 0.6 * prev
        prev = x
        out.append((0.6 * hp + 0.5 * math.sin(2 * math.pi * 2300 * t)) * math.exp(-t * 140))
    return out

def chime(notes, start, gain):
    for j, n in enumerate(notes):
        f = midi(n)
        dur = 2.2
        s = [math.sin(2 * math.pi * f * (k / SR)) * math.exp(-(k / SR) * 2.4) * min(1, (k / SR) / 0.006)
             + 0.25 * math.sin(2 * math.pi * f * 2.01 * (k / SR)) * math.exp(-(k / SR) * 4) for k in range(int(dur * SR))]
        add(L, R, start + j * 0.11, s, pan=-0.2 + 0.2 * j, gain=gain)

# Music: 96 bpm, warm major-seventh progression.
BEAT = 60 / 96
BAR = 4 * BEAT
chords = [[53, 57, 60, 64], [57, 60, 64, 67], [50, 53, 57, 60, 64], [46, 50, 53, 57]]  # Fmaj7 Am7 Dm9 Bbmaj7
bars = int(TOTAL / BAR) + 1
for b in range(0, bars, 2):
    chord = chords[(b // 2) % len(chords)]
    start = b * BAR
    for i, n in enumerate(chord):
        add(L, R, start, pad_note(midi(n), 2 * BAR - 0.2), pan=-0.5 + i / max(1, len(chord) - 1), gain=0.045)
    add(L, R, start, pad_note(midi(chord[0] - 12), 2 * BAR - 0.2, attack=0.3), gain=0.06)  # bass
    # Arpeggio in eighths, entering after the title card.
    for step in range(16):
        t = start + step * BEAT / 2
        if t < T0 - 0.2:
            continue
        note = chord[[0, 2, 1, 3, 2, 1, 3, 2][step % 8] % len(chord)] + 12
        add(L, R, t, pluck(midi(note)), pan=0.35 if step % 2 else -0.35, gain=0.06 if step % 2 else 0.075)

# The beat comes in with the second scene (culling).
scenes = [e for e in timeline["events"] if e["kind"] == "scene"]
beat_in = T0 + (scenes[1]["t"] if len(scenes) > 1 else 0)
for b in range(int(TOTAL / BEAT)):
    t = b * BEAT
    if beat_in <= t < END_IN + BAR:
        if b % 4 in (0, 2):
            add(L, R, t, kick(), gain=0.32)
        add(L, R, t + BEAT / 2, shaker(), pan=0.25, gain=0.05)

# UI sounds from the recorded timeline.
for e in timeline["events"]:
    if e["kind"] == "key":
        add(L, R, T0 + e["t"], click(), pan=0.0, gain=0.22)
    if e["kind"] == "scene" and e["value"] == "delete":
        chime([72, 76, 79], T0 + e["t"] + 0.05, 0.10)  # import landed
chime([77, 81, 84, 88], END_IN + 0.15, 0.09)

# Master: fades and a soft limiter.
fade_in, fade_out = 0.8, 2.2
peak = 0.0
for i in range(N):
    t = i / SR
    g = min(1.0, t / fade_in) * min(1.0, (TOTAL - t) / fade_out)
    L[i] = math.tanh(L[i] * g * 1.4) * 0.85
    R[i] = math.tanh(R[i] * g * 1.4) * 0.85
    peak = max(peak, abs(L[i]), abs(R[i]))

with wave.open(out, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    frames = bytearray()
    for i in range(N):
        frames += struct.pack("<hh", int(L[i] * 32000), int(R[i] * 32000))
    w.writeframes(bytes(frames))
print(f"wrote {out} ({TOTAL:.1f}s, peak {peak:.2f})")

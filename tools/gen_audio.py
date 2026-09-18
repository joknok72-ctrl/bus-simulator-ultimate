#!/usr/bin/env python3
"""
Procedural sound generator for Bus Simulator Ultimate.
Generates all SFX/music as small 16-bit WAV files into ../audio/.
No external assets needed — everything is synthesized.
"""
import os, struct, math
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)


def save(name, data, loop=False):
    data = np.clip(data, -1, 1)
    pcm = (data * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE")
        f.write(b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(pcm)) + pcm)
    print(f"  {name:22s} {len(data)/SR:5.2f}s")


def env(n, a=0.005, r=0.1):
    e = np.ones(n)
    ai, ri = int(a * SR), int(r * SR)
    if ai > 0:
        e[:ai] = np.linspace(0, 1, ai)
    if ri > 0:
        e[-ri:] *= np.linspace(1, 0, ri)
    return e


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def t(sec):
    return np.arange(int(sec * SR)) / SR


# ---------------------------------------------------------------- Engine loop
# Diesel idle: low fundamental + harmonics + noise, seamless loop
def engine_loop():
    dur = 1.0
    n = int(dur * SR)
    tt = np.arange(n) / SR
    f0 = 38.0  # cycles per second, integer multiple -> seamless loop
    sig = np.zeros(n)
    for k, amp in [(1, 1.0), (2, 0.55), (3, 0.35), (4, 0.22), (6, 0.12), (8, 0.06)]:
        sig += amp * np.sin(2 * np.pi * f0 * k * tt + 0.3 * k)
    # combustion knock pulses
    pulses = np.zeros(n)
    period = int(SR / (f0 * 2))
    for i in range(0, n, period):
        L = min(180, n - i)
        pulses[i:i + L] += np.exp(-np.linspace(0, 6, L)) * rng.uniform(0.6, 1.0)
    sig += 0.9 * pulses
    noise = lowpass(rng.normal(0, 1, n), 0.08) * 0.6
    sig += noise
    sig /= np.max(np.abs(sig))
    return sig * 0.7


save("engine_loop.wav", engine_loop())


# ---------------------------------------------------------------- Air brake
def air_brake():
    n = int(0.7 * SR)
    noise = rng.normal(0, 1, n)
    hp = noise - lowpass(noise, 0.2)
    e = np.exp(-np.linspace(0, 5, n))
    sig = hp * e
    # hiss tail
    sig += lowpass(rng.normal(0, 1, n), 0.5) * np.exp(-np.linspace(0, 3, n)) * 0.3
    return sig / np.max(np.abs(sig)) * 0.6


save("air_brake.wav", air_brake())


# ---------------------------------------------------------------- Doors
def doors(open_):
    n = int(0.6 * SR)
    tt = np.arange(n) / SR
    f = np.linspace(180, 90, n) if open_ else np.linspace(90, 180, n)
    hiss = lowpass(rng.normal(0, 1, n), 0.3) * np.exp(-np.linspace(0, 4, n))
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-np.linspace(0, 6, n))
    click = np.zeros(n)
    pos = n - int(0.08 * SR) if open_ else int(0.02 * SR)
    click[pos:pos + 400] = rng.normal(0, 1, 400) * np.exp(-np.linspace(0, 8, 400))
    sig = hiss * 0.5 + tone * 0.4 + click * 0.8
    return sig / np.max(np.abs(sig)) * 0.6


save("door_open.wav", doors(True))
save("door_close.wav", doors(False))


# ---------------------------------------------------------------- Horn
def horn():
    n = int(0.8 * SR)
    tt = np.arange(n) / SR
    sig = np.zeros(n)
    for f, a in [(330, 1.0), (415, 0.8), (660, 0.3), (830, 0.2)]:
        sig += a * np.sign(np.sin(2 * np.pi * f * tt)) * 0.4 + a * np.sin(2 * np.pi * f * tt) * 0.6
    sig = lowpass(sig, 0.35)
    return sig / np.max(np.abs(sig)) * env(n, 0.02, 0.15) * 0.7


save("horn.wav", horn())


# ---------------------------------------------------------------- Stop bell (ding)
def bell():
    n = int(1.2 * SR)
    tt = np.arange(n) / SR
    sig = np.zeros(n)
    for f, a, d in [(880, 1.0, 3), (1760, 0.5, 5), (2637, 0.25, 7), (1320, 0.3, 4)]:
        sig += a * np.sin(2 * np.pi * f * tt) * np.exp(-d * tt)
    return sig / np.max(np.abs(sig)) * 0.6


save("bell.wav", bell())


# ---------------------------------------------------------------- Coin / money
def coin():
    n = int(0.35 * SR)
    tt = np.arange(n) / SR
    sig = np.sin(2 * np.pi * 1200 * tt) * np.exp(-8 * tt)
    sig += np.sin(2 * np.pi * 1800 * tt) * np.exp(-12 * tt) * 0.6
    n2 = int(0.12 * SR)
    sig[n2:] += (np.sin(2 * np.pi * 1600 * tt[:n - n2]) * np.exp(-10 * tt[:n - n2]))
    return sig / np.max(np.abs(sig)) * 0.5


save("coin.wav", coin())


# ---------------------------------------------------------------- Crash
def crash():
    n = int(0.9 * SR)
    noise = rng.normal(0, 1, n)
    low = lowpass(noise, 0.05) * np.exp(-np.linspace(0, 4, n)) * 3
    mid = lowpass(noise, 0.4) * np.exp(-np.linspace(0, 9, n))
    tt = np.arange(n) / SR
    thud = np.sin(2 * np.pi * np.linspace(90, 30, n) * tt) * np.exp(-6 * tt)
    sig = low + mid * 0.6 + thud * 1.5
    return sig / np.max(np.abs(sig)) * 0.8


save("crash.wav", crash())


# ---------------------------------------------------------------- Tire skid
def skid():
    n = int(1.0 * SR)
    tt = np.arange(n) / SR
    f = 900 + 120 * np.sin(2 * np.pi * 7 * tt)
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR)
    sig += lowpass(rng.normal(0, 1, n), 0.6) * 0.5
    return sig / np.max(np.abs(sig)) * 0.5


save("skid.wav", skid())


# ---------------------------------------------------------------- UI click / success / fail
def ui_click():
    n = int(0.08 * SR)
    tt = np.arange(n) / SR
    return np.sin(2 * np.pi * 900 * tt) * np.exp(-40 * tt) * 0.5


save("ui_click.wav", ui_click())


def success():
    n = int(1.0 * SR)
    sig = np.zeros(n)
    notes = [523, 659, 784, 1046]
    step = int(0.13 * SR)
    for i, f in enumerate(notes):
        s = i * step
        L = n - s
        tt = np.arange(L) / SR
        sig[s:] += np.sin(2 * np.pi * f * tt) * np.exp(-4 * tt) * 0.6
    return sig / np.max(np.abs(sig)) * 0.6


save("success.wav", success())


def fail():
    n = int(0.7 * SR)
    tt = np.arange(n) / SR
    f = np.linspace(300, 150, n)
    sig = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.3 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.7
    return lowpass(sig, 0.3) / 1.0 * env(n, 0.01, 0.2) * 0.5


save("fail.wav", fail())


def perfect():
    n = int(0.8 * SR)
    tt = np.arange(n) / SR
    sig = np.zeros(n)
    for f, a in [(1046, 1.0), (1318, 0.8), (1568, 0.6), (2093, 0.4)]:
        sig += a * np.sin(2 * np.pi * f * tt) * np.exp(-5 * tt)
    return sig / np.max(np.abs(sig)) * 0.55


save("perfect.wav", perfect())


# ---------------------------------------------------------------- Ambient music loop (calm, 8 bars)
def music():
    bpm = 84
    beat = 60 / bpm
    bars = 8
    dur = bars * 4 * beat
    n = int(dur * SR)
    tt = np.arange(n) / SR
    sig = np.zeros(n)
    # chord progression (Am - F - C - G), soft pads
    chords = [
        [220, 261.6, 329.6], [174.6, 220, 261.6],
        [130.8, 164.8, 196], [196, 246.9, 293.7],
    ]
    bar_n = int(4 * beat * SR)
    for b in range(bars):
        ch = chords[b % 4]
        s = b * bar_n
        L = min(bar_n, n - s)
        ttb = np.arange(L) / SR
        e = np.minimum(ttb / 0.4, 1) * np.minimum((L / SR - ttb) / 0.6, 1)
        for f in ch:
            sig[s:s + L] += 0.12 * np.sin(2 * np.pi * f * ttb) * e
            sig[s:s + L] += 0.06 * np.sin(2 * np.pi * f * 2 * ttb + 0.5) * e
    # gentle pluck melody
    scale = [440, 493.9, 523.3, 587.3, 659.3, 783.9, 880]
    mel_rng = np.random.default_rng(7)
    step = int(beat * SR)
    for i in range(bars * 4):
        if mel_rng.random() < 0.65:
            f = scale[mel_rng.integers(0, len(scale))]
            s = i * step
            L = min(int(0.6 * SR), n - s)
            ttm = np.arange(L) / SR
            sig[s:s + L] += 0.18 * np.sin(2 * np.pi * f * ttm) * np.exp(-4 * ttm)
    # soft kick on beats
    for i in range(bars * 4):
        s = i * step
        L = min(int(0.15 * SR), n - s)
        ttk = np.arange(L) / SR
        sig[s:s + L] += 0.25 * np.sin(2 * np.pi * np.linspace(80, 40, L) * ttk) * np.exp(-25 * ttk)
    sig = lowpass(sig, 0.6)
    return sig / np.max(np.abs(sig)) * 0.5


save("music_loop.wav", music())


# ---------------------------------------------------------------- Traffic ambience loop
def ambience():
    n = int(4.0 * SR)
    noise = lowpass(rng.normal(0, 1, n), 0.04)
    tt = np.arange(n) / SR
    mod = 1 + 0.3 * np.sin(2 * np.pi * 0.25 * tt)
    sig = noise * mod
    # crossfade for looping
    f = int(0.3 * SR)
    fade = np.linspace(0, 1, f)
    sig[:f] = sig[:f] * fade + sig[-f:] * (1 - fade)
    return sig / np.max(np.abs(sig)) * 0.3


save("ambience_loop.wav", ambience())

print("done.")

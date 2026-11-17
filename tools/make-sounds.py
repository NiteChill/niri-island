#!/usr/bin/env python3
"""Generates the island's sounds (assets/sounds/*.wav), so they can be tuned and remade.

Run: python3 tools/make-sounds.py   (pure Python, no packages)

The look of the sounds (retuned 2026-11-15, after studying how bencho.dev builds its UI sounds: layered
sine tones, low cut-offs, quiet layers; our motifs and code are our own; then made flatter: the first
retune "really woke you up"): soft, low and short, never a beep; they should just exist.
  - each note is a pure sine with a rounded attack (no click) and a natural exponential fade
  - dark and low: notes around 260-660 Hz, every layer through a low-pass around 1.1-1.4 kHz
  - soft starts (24-30 ms) and even levels: nothing jumps out
  - where it helps, a soft body under the notes: a rounded triangle tone gliding up (or down), low-passed
    hard, that gives weight without being heard as a note
  - every layer stays quiet; the files are then normalised to the same loudness, capped well under full
Each alert keeps its own short motif so it's recognisable without looking ("hey, something's up"):
  notification    a rising fourth, light (the one you hear most: the gentlest)
  lowBattery      a falling major third, lower and rounder, a body sinking under it
  charging        a quick rising arpeggio over a body gliding up, the "power on" feeling
  headphones      a rising fifth, mid-register
  wifiConnected   one soft high note
The shell scales them all with sounds.volume.
"""
import math
import os
import struct
import wave

RATE = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")


def layer(seconds, freq, start, ms, gain, wave_="sine", atk=5, glide_to=None, glide_ms=120):
    """One tone: starts at `start` s, fades over about `ms` ms (exponential), `atk` ms rounded attack;
    `glide_to`: the pitch slides from freq to glide_to over glide_ms (eased)."""
    buf = [0.0] * int(seconds * RATE)
    n0 = int(start * RATE)
    tau = ms / 1000 / 3.2
    length = int(ms / 1000 * 2.2 * RATE)
    phase = 0.0
    for i in range(length):
        if n0 + i >= len(buf):
            break
        t = i / RATE
        env = math.exp(-t / tau)
        a = atk / 1000
        if t < a:
            env *= 0.5 - 0.5 * math.cos(math.pi * t / a)
        f = freq
        if glide_to:
            k = min(1.0, t / (glide_ms / 1000))
            f = freq + (glide_to - freq) * (1 - (1 - k) ** 3)
        phase += 2 * math.pi * f / RATE
        if wave_ == "triangle":
            # a rounded triangle: the fundamental and a soft third harmonic (no edge)
            s = math.sin(phase) - math.sin(3 * phase) / 9
        else:
            s = math.sin(phase)
        buf[n0 + i] = gain * env * s
    return buf


def lowpass(buf, cutoff):
    # two one-pole stages: a gentle 12 dB/octave roll-off
    a = math.exp(-2 * math.pi * cutoff / RATE)
    for _ in range(2):
        y = 0.0
        for i, x in enumerate(buf):
            y = (1 - a) * x + a * y
            buf[i] = y
    return buf


def room(buf):
    # a faint short room: two low feedback combs
    for delay, gain in ((0.029, 0.12), (0.043, 0.08)):
        d = int(delay * RATE)
        for i in range(d, len(buf)):
            buf[i] += gain * buf[i - d]
    return buf


def finish(buf, name, loudness, peak=0.3):
    # end once 99.95 % of the energy is out (the rest is an inaudible tail), fading the last 80 ms
    total = sum(x * x for x in buf)
    acc, end = 0.0, len(buf)
    for i, x in enumerate(buf):
        acc += x * x
        if acc >= 0.9995 * total:
            end = min(len(buf), i + int(0.08 * RATE))
            break
    buf = buf[:end]
    fade = int(0.08 * RATE)
    for i in range(min(fade, len(buf))):
        buf[len(buf) - 1 - i] *= i / fade
    rms = math.sqrt(sum(x * x for x in buf) / len(buf))
    k = min(loudness / rms, peak / max(abs(x) for x in buf))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, x * k)) * 32767)) for x in buf)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(name, round(len(buf) / RATE, 2), "s")


def make(name, seconds, layers, loudness=0.04):
    """layers: (cutoff Hz, layer(...) kwargs); each filtered on its own, then mixed, then the room."""
    mix = [0.0] * int(seconds * RATE)
    for cutoff, kw in layers:
        b = lowpass(layer(seconds, **kw), cutoff)
        for i, x in enumerate(b):
            mix[i] += x
    finish(room(mix), name, loudness)


# an octave lower than the first version (high notes are what pierce), then 3 semitones lower again (DOWN),
# soft 24-30 ms attacks (no startle), even levels between the notes, cut-offs around 1.1-1.4 kHz, no
# sparkle, quiet: flat, warm, it just exists
DOWN = 2 ** (-3 / 12)
Ds4, E4, G4, A4, B4, C5, D5, E5, G5 = (f * DOWN for f in (311.13, 329.63, 392.0, 440.0, 493.88, 523.25, 587.33, 659.25, 783.99))

make("notification", 1.2, [
    (1200, dict(freq=A4, start=0.0, ms=260, gain=0.05, atk=24)),
    (1300, dict(freq=D5, start=0.09, ms=480, gain=0.05, atk=28)),
])

make("lowBattery", 1.4, [
    (1100, dict(freq=G4, start=0.0, ms=320, gain=0.05, atk=26)),
    (1100, dict(freq=Ds4, start=0.14, ms=560, gain=0.05, atk=30)),
    (500, dict(freq=G4 / 2, start=0.0, ms=480, gain=0.02, wave_="triangle", atk=50, glide_to=Ds4 / 2, glide_ms=300)),
])

make("charging", 1.3, [
    (600, dict(freq=196.0 * DOWN, start=0.0, ms=260, gain=0.02, wave_="triangle", atk=50, glide_to=262.0 * DOWN, glide_ms=160)),
    (1200, dict(freq=C5, start=0.06, ms=200, gain=0.04, atk=24)),
    (1300, dict(freq=E5, start=0.13, ms=210, gain=0.04, atk=24)),
    (1400, dict(freq=G5, start=0.2, ms=480, gain=0.045, atk=26)),
])

make("headphones", 1.2, [
    (1200, dict(freq=E4, start=0.0, ms=240, gain=0.05, atk=24)),
    (1300, dict(freq=B4, start=0.085, ms=460, gain=0.05, atk=28)),
])

make("wifiConnected", 1.0, [
    (1400, dict(freq=D5, start=0.0, ms=420, gain=0.05, atk=28)),
])

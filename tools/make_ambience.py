"""Synthesised ambience loops for the sound zones (sl_ambience, #46): python tools/make_ambience.py

Three mono 16 kHz 16-bit loops written to mod/art/sound/street_legal/ambience/ (the game places only mono sounds in the world):
  harbour.wav  - waves washing in and out over a low rumble, a little hiss in the foam
  freeway.wav  - the steady roar of distant traffic with slow swells as cars go by
  crowd.wav    - many voices: band-limited noise carrying 3-6 Hz syllable-like modulation, from several 'speakers'
Made from random noise with a fixed seed, so nothing is taken from anywhere; the ends are cross-faded so a loop has no click.
"""
import os
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "mod", "art", "sound", "street_legal", "ambience")
RATE = 16000
SECONDS = 12


def lowpass(x, hz):
    a = np.exp(-2 * np.pi * hz / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = a * acc + (1 - a) * v
        y[i] = acc
    return y


def bandpass(x, lo, hi):
    return lowpass(x, hi) - lowpass(x, lo)


def loopable(x, fade=int(0.8 * RATE)):
    """Cross-fade the tail into the head so the loop's seam is silent."""
    x = x.copy()
    t = np.linspace(0, 1, fade)
    x[:fade] = x[:fade] * t + x[-fade:] * (1 - t)
    return x[:-fade]


def norm(x, peak=0.6):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def harbour(rng, n):
    t = np.arange(n) / RATE
    rumble = lowpass(rng.standard_normal(n), 120) * 6
    foam = rng.standard_normal(n)
    swell = (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t + 1.0)) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.27 * t))
    wash = bandpass(rng.standard_normal(n), 200, 2200) * 5 * swell
    hiss = lowpass(foam, 6000) * swell ** 2 * 0.5
    return norm(rumble * 0.5 + wash + hiss)


def freeway(rng, n):
    t = np.arange(n) / RATE
    roar = bandpass(rng.standard_normal(n), 60, 900) * 5
    tyres = bandpass(rng.standard_normal(n), 900, 3500) * 1.2
    swells = np.zeros(n)
    for centre, width in zip(rng.uniform(0.5, SECONDS - 0.5, 9), rng.uniform(0.4, 1.2, 9)):
        swells += np.exp(-((t - centre) / width) ** 2)
    return norm((roar + tyres * (0.3 + swells)) * (0.7 + 0.3 * swells))


def crowd(rng, n):
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for voice in range(6):
        pitch = rng.uniform(120, 260)
        base = bandpass(rng.standard_normal(n), pitch, pitch * 6)
        # syllables: bursts a few times a second with silences between phrases
        rate = rng.uniform(3.0, 5.5)
        syll = np.clip(np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28)), 0, 1) ** 1.5
        phrase = np.clip(np.sin(2 * np.pi * rng.uniform(0.15, 0.4) * t + rng.uniform(0, 6.28)) + 0.3, 0, 1)
        out += base * syll * phrase
    murmur = bandpass(rng.standard_normal(n), 300, 2500) * 0.5
    return norm(out * 3 + murmur)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print(name, "%.1f s, %d KB" % (len(pcm) / RATE, pcm.nbytes // 1024))


def main():
    n = int((SECONDS + 0.8) * RATE)
    for name, fn, seed in (("harbour.wav", harbour, 11), ("freeway.wav", freeway, 12), ("crowd.wav", crowd, 13)):
        write(name, norm(loopable(fn(np.random.default_rng(seed), n))))


if __name__ == "__main__":
    main()

"""Render the opening piano and letter pickup triangle. Offline: numpy, soundfile.

Piano: soft Salamander Grand Piano samples by Alexander Holm, CC BY 3.0.
Triangle: original modal synthesis. See ../SFX/Update_SFX.md for attribution.
Run from any directory: python Audio/Tools/Generate_Update_SFX.py
"""
from pathlib import Path
import json
import wave

import numpy as np
import soundfile as sf


RATE = 44100
OUTPUT = Path(__file__).resolve().parents[1] / "SFX"
PIANO_SAMPLES = Path(__file__).resolve().parent / "PianoSamples"
# The isolated first G5 in mainscene.ogg is approximately 785.33 Hz, +2.95 cents.
MENU_TUNING_CENTS = 2.95


def midi_frequency(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def low_pass(signal, cutoff):
    """Gentle soundboard/room damping, without a runtime DSP dependency."""
    frequency = np.fft.rfftfreq(len(signal), 1.0 / RATE)
    response = 1.0 / np.sqrt(1.0 + (frequency / cutoff) ** 4)
    return np.fft.irfft(np.fft.rfft(signal) * response, n=len(signal))


def sample_frequency(signal, sample_rate, note):
    """Fit the recorded fundamental; keep natural string beating and overtones."""
    section = signal[round(0.09 * sample_rate):round(0.64 * sample_rate)].mean(axis=1)
    size = 262144
    spectrum = np.abs(np.fft.rfft(section * np.hanning(len(section)), size))
    frequencies = np.fft.rfftfreq(size, 1.0 / sample_rate)
    expected = midi_frequency(note)
    candidates = np.flatnonzero((frequencies > expected * 0.975) &
                               (frequencies < expected * 1.025))
    peak = candidates[np.argmax(spectrum[candidates])]
    left, center, right = np.log(np.maximum(spectrum[peak-1:peak+2], 1e-12))
    fraction = 0.5 * (left - right) / (left - 2.0 * center + right)
    return (peak + fraction) * sample_rate / size


def piano_note(note, source_note, filename, frame_count, velocity):
    source, source_rate = sf.read(PIANO_SAMPLES / filename, always_2d=True)
    source -= source.mean(axis=0)
    recorded_pitch = sample_frequency(source, source_rate, source_note)
    target_pitch = midi_frequency(note) * 2.0 ** (MENU_TUNING_CENTS / 1200.0)
    ratio = target_pitch / recorded_pitch
    positions = np.arange(frame_count) * source_rate / RATE * ratio
    sound = np.column_stack([np.interp(positions, np.arange(len(source)), source[:, channel],
                                      left=0.0, right=0.0) for channel in range(2)])
    # Low velocity recordings supply the felt strike, soundboard and natural pedal tail.
    # A gentle upper shelf and 4 ms touch soften the attack without removing its character.
    for channel in range(2):
        sound[:, channel] = low_pass(sound[:, channel], 5100.0)
    touch = round(0.004 * RATE)
    sound[:touch] *= np.linspace(0.0, 1.0, touch)[:, None]
    sound *= velocity / max(float(np.abs(sound[:RATE]).max()), 1e-9)
    return sound


def room(dry, wet, decay, seed):
    """Short asymmetric early reflections plus a quiet diffuse stereo tail."""
    rng = np.random.default_rng(seed)
    reflected = np.zeros_like(dry)
    for channel in range(2):
        damped = low_pass(dry[:, channel], 3700.0)
        delays = np.r_[0.019 + channel * 0.004, 0.037 - channel * 0.003,
                       np.linspace(0.055, 0.62, 42) + rng.uniform(-0.004, 0.004, 42)]
        for index, seconds in enumerate(delays):
            delay = round(float(seconds) * RATE)
            strength = wet * np.exp(-float(seconds) / decay) / np.sqrt(len(delays))
            strength *= 1.0 if index < 2 else rng.choice([-1.0, 1.0])
            reflected[delay:, channel] += damped[:-delay] * strength
    return dry + reflected


def opening_piano():
    duration = 6.40
    sound = np.zeros((round(duration * RATE), 2))
    # Raise the original C-major voicing by an octave into the menu's register.
    # Longer human-spaced strikes let every note ring together under a held pedal.
    notes = [60, 67, 72, 76, 79, 84]
    sources = [(60, "C4v4.flac"), (66, "F#4v4.flac"), (72, "C5v4.flac"),
               (75, "D#5v4.flac"), (78, "F#5v4.flac"), (84, "C6v4.flac")]
    starts = [0.0, 0.22, 0.47, 0.73, 1.02, 1.34]
    velocities = [0.72, 0.61, 0.67, 0.64, 0.60, 0.56]
    for index, (note, start, velocity) in enumerate(zip(notes, starts, velocities)):
        offset = round(start * RATE)
        source_note, filename = sources[index]
        tone = piano_note(note, source_note, filename, len(sound) - offset, velocity)
        pan = -0.12 + index * 0.048
        sound[offset:, 0] += tone[:, 0] * np.sqrt(1.0 - pan)
        sound[offset:, 1] += tone[:, 1] * np.sqrt(1.0 + pan)
    return room(sound, wet=0.18, decay=0.30, seed=2718)


def collection_triangle():
    duration = 2.30
    rng = np.random.default_rng(31415)
    time = np.arange(round(duration * RATE)) / RATE
    stereo = np.zeros((len(time), 2))
    # Inharmonic steel modes make a triangle, rather than a pitched sine bell.
    pitch_ratio = 2.0 ** (5.0 / 12.0)
    modes = [(1760.0, 0.08, 0.42), (2637.02, 1.0, 0.58),
             (3847.0, 0.63, 0.36), (5118.0, 0.42, 0.28),
             (6679.0, 0.23, 0.20), (8241.0, 0.12, 0.14),
             (10783.0, 0.05, 0.09), (12397.0, 0.015, 0.06)]
    attack = 1.0 - np.exp(-time / 0.00028)
    for index, (frequency, amplitude, decay) in enumerate(modes):
        frequency *= pitch_ratio
        phase = rng.uniform(-np.pi, np.pi)
        mode = np.sin(2.0 * np.pi * frequency * time + phase)
        mode += 0.19 * np.sin(2.0 * np.pi * (frequency + 3.1 + index * 0.27) * time + phase)
        mode *= amplitude * attack * np.exp(-time / decay)
        pan = rng.uniform(-0.13, 0.13)
        stereo[:, 0] += mode * np.sqrt((1.0 - pan) / 2.0)
        stereo[:, 1] += mode * np.sqrt((1.0 + pan) / 2.0)
    strike = low_pass(rng.normal(0.0, 1.0, len(time)), 11000.0)
    strike *= attack * np.exp(-time / 0.0015) * 0.10
    stereo += strike[:, None]
    return room(stereo, wet=0.06, decay=0.11, seed=1618)


def write_sound(name, signal, peak_db):
    # Smoothly close the final tail; no hard cut, clipping, leading silence or loop.
    fade = round(min(0.60, len(signal) / RATE * 0.1) * RATE)
    signal[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None] ** 2
    signal -= signal.mean(axis=0)
    signal *= 10.0 ** (peak_db / 20.0) / np.abs(signal).max()
    dither = np.random.default_rng(42).triangular(-1, 0, 1, signal.shape) / 65536.0
    pcm = np.round(np.clip(signal + dither, -1.0, 1.0) * 32767).astype('<i2')
    path = OUTPUT / name
    with wave.open(str(path), 'wb') as out:
        out.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(pcm.tobytes())
    print(json.dumps({'file': name, 'seconds': len(signal) / RATE,
                      'peak_dbfs': round(20 * np.log10(np.abs(signal).max()), 2),
                      'rms_dbfs': round(20 * np.log10(np.sqrt(np.mean(signal**2))), 2)}))


if __name__ == '__main__':
    OUTPUT.mkdir(parents=True, exist_ok=True)
    write_sound('opening_piano.wav', opening_piano(), -7.0)
    write_sound('collection_triangle.wav', collection_triangle(), -8.0)

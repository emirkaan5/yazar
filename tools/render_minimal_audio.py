#!/usr/bin/env python3
"""Render all or selected web-kits/audio patch sounds to deterministic WAV files."""

import json
import math
import struct
import sys
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
SILENCE = 0.0001


def oscillator_sample(source: dict, elapsed: float, duration: float) -> float:
    frequency = source["frequency"]
    if isinstance(frequency, (int, float)):
        phase = 2 * math.pi * frequency * elapsed
    else:
        start = frequency["start"]
        end = max(frequency["end"], 1)
        ratio_log = math.log(end / start)
        if abs(ratio_log) < 1e-12:
            cycles = start * elapsed
        else:
            cycles = start * duration * math.expm1(ratio_log * elapsed / duration) / ratio_log
        phase = 2 * math.pi * cycles

    if fm := source.get("fm"):
        carrier = frequency if isinstance(frequency, (int, float)) else frequency["start"]
        modulator_frequency = carrier * fm["ratio"]
        phase += fm["depth"] / modulator_frequency * (
            1 - math.cos(2 * math.pi * modulator_frequency * elapsed)
        )
    return math.sin(phase)


def envelope_gain(envelope: dict, gain: float, elapsed: float) -> float:
    attack = envelope.get("attack", 0)
    decay = envelope["decay"]
    sustain = envelope.get("sustain", 0)
    release = envelope.get("release", 0)

    if elapsed < attack and attack > 0:
        return SILENCE + (gain - SILENCE) * elapsed / attack

    decay_elapsed = elapsed - attack
    decay_target = max(sustain * gain, SILENCE)
    decay_gain = decay_target + (gain - decay_target) * math.exp(-decay_elapsed / (decay / 3))

    if sustain > 0 and release > 0 and decay_elapsed >= decay:
        release_elapsed = decay_elapsed - decay
        return SILENCE + (decay_gain - SILENCE) * math.exp(-release_elapsed / (release / 3))
    return decay_gain


def render_sound(definition: dict) -> list[float]:
    layers = definition.get("layers", [definition])
    end_time = max(
        layer.get("delay", 0)
        + layer["envelope"].get("attack", 0)
        + layer["envelope"]["decay"]
        + layer["envelope"].get("release", 0)
        + 0.1
        for layer in layers
    )
    frame_count = math.ceil(end_time * SAMPLE_RATE)
    samples = [0.0] * frame_count

    for layer in layers:
        delay = layer.get("delay", 0)
        envelope = layer["envelope"]
        duration = envelope.get("attack", 0) + envelope["decay"] + envelope.get("release", 0)
        stop_time = delay + duration + 0.1
        gain = layer.get("gain", 0.5)
        start_frame = round(delay * SAMPLE_RATE)
        stop_frame = min(frame_count, math.ceil(stop_time * SAMPLE_RATE))

        for frame in range(start_frame, stop_frame):
            elapsed = frame / SAMPLE_RATE - delay
            samples[frame] += oscillator_sample(layer["source"], elapsed, duration) * envelope_gain(
                envelope, gain, elapsed
            )

    return samples


def write_wav(path: Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            clipped = max(-1.0, min(1.0, sample))
            pcm = round(clipped * (32768 if clipped < 0 else 32767))
            frames.extend(struct.pack("<hh", pcm, pcm))
        output.writeframes(frames)


def main() -> None:
    patch_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    selected_names = set(sys.argv[3:])
    patch = json.loads(patch_path.read_text())
    output_dir.mkdir(parents=True, exist_ok=True)

    for name, definition in patch["sounds"].items():
        if selected_names and name not in selected_names:
            continue
        write_wav(output_dir / f"{name}.wav", render_sound(definition))

    selected_patch = patch | {
        "sounds": {
            name: definition
            for name, definition in patch["sounds"].items()
            if not selected_names or name in selected_names
        }
    }
    (output_dir / f"{patch_path.stem}.json").write_text(json.dumps(selected_patch, indent=2) + "\n")


if __name__ == "__main__":
    main()

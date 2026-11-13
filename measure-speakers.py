#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""measure-speakers.py — measure the speakers' bass with the built-in mics.

Plays a log sweep at -20 dBFS through the live speaker chain three times and
records each run with the four built-in mics: the current tuning, the same
with the woofer cut (wol_6, wor_6) at 0 dB, and the current tuning again.
Prints the response relative to the mids, in a 30 ms window that leaves out
the room, and how well the runs and the mics agree.

The sweeps are audible. For their duration the raw sink goes to 100 %, since
at normal listening levels the sweep is lost in the mics' noise. The volume
and the cut are put back afterwards; leave the volume keys alone meanwhile.
The mics agree only up to about 180 Hz, so read the result for the bass and
nothing above it. They also pick up typing and anything else that touches the
desk: keep still while it runs.

    ./measure-speakers.py              measure and print
    ./measure-speakers.py --keep DIR   also keep the recordings in DIR
    ./measure-speakers.py --analyze DIR   print again from kept recordings
"""
import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
import warnings

import numpy as np
from scipy.io import wavfile

RATE = 48000
SINK = "imacpro_speakers"
RAW_SINK = "alsa_output.pci-0000_02_00.3.HiFi__Speaker__sink"
MICS = "alsa_input.pci-0000_02_00.3.HiFi__Mic__source"
CUT = ("wol_6:Gain", "wor_6:Gain")
SWEEP_S, F_LO, F_HI = 5.0, 20.0, 20000.0
SILENCE_S = 1.5   # before and after the sweep
SKIP_S = 1.5      # the mics pop when the recorder starts; the sweep comes later
RUNS = {"now": "current tuning", "nocut": "woofer cut at 0 dB", "again": "current tuning, repeated"}
MIDS = (300, 1000)


def sweep():
    t = np.arange(int(SWEEP_S * RATE)) / RATE
    k = SWEEP_S / np.log(F_HI / F_LO)
    x = np.sin(2 * np.pi * F_LO * k * (np.exp(t / k) - 1))
    fade_in, fade_out = int(0.05 * RATE), int(0.01 * RATE)
    x[:fade_in] *= np.sin(np.linspace(0, np.pi / 2, fade_in)) ** 2
    x[-fade_out:] *= np.cos(np.linspace(0, np.pi / 2, fade_out)) ** 2
    return x * 10 ** (-20 / 20)


def live_controls():
    nodes = json.loads(subprocess.run(["pw-dump"], check=True, capture_output=True, text=True).stdout)
    for node in nodes:
        if node.get("info", {}).get("props", {}).get("node.name") == SINK:
            controls = {}
            for props in node["info"]["params"].get("Props", []):
                flat = props.get("params", [])
                controls.update(zip(flat[::2], flat[1::2]))
            return controls
    raise SystemExit(f"{SINK} not found: is imacpro-speakers.service running?")


def set_controls(values):
    flat = " ".join(f'"{name}" {value}' for name, value in values.items())
    subprocess.run(["pw-cli", "s", SINK, "Props", f"{{ params = [ {flat} ] }}"],
                   check=True, stdout=subprocess.DEVNULL)
    time.sleep(0.4)


def other_playback():
    inputs = json.loads(subprocess.run(["pactl", "--format=json", "list", "sink-inputs"],
                                       check=True, capture_output=True, text=True).stdout)
    return [i["properties"].get("application.name") or i["properties"].get("media.name", "a stream")
            for i in inputs
            if not i.get("corked") and i["properties"].get("node.name") != f"{SINK}.out"]


def record(path, sweep_file):
    recorder = subprocess.Popen(
        ["pw-record", "--target", MICS, "--channels", "4", "--channel-map", "FL,FR,RL,RR",
         "--rate", str(RATE), "--format", "f32", path])
    time.sleep(1.2)
    subprocess.run(["pw-play", "--target", SINK, sweep_file], check=True)
    time.sleep(0.3)
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=5)


def raw_volume():
    out = subprocess.run(["pactl", "get-sink-volume", RAW_SINK], check=True, capture_output=True,
                         text=True, env={**os.environ, "LC_ALL": "C"}).stdout
    return out.split(":")[2].split("/")[0].strip()  # raw value of the first channel


def measure(folder):
    if playing := other_playback():
        raise SystemExit(f"{', '.join(playing)} is playing: stop it first, the sweeps run at 100 % volume")
    silence = np.zeros(int(SILENCE_S * RATE))
    mono = np.concatenate([silence, sweep(), silence]).astype(np.float32)
    sweep_file = f"{folder}/sweep.wav"
    wavfile.write(sweep_file, RATE, np.stack([mono, mono], axis=1))

    volume = raw_volume()
    cut = {name: live_controls()[name] for name in CUT}
    try:
        subprocess.run(["pactl", "set-sink-volume", RAW_SINK, "100%"], check=True)
        full = raw_volume()
        for run in RUNS:
            set_controls(dict.fromkeys(CUT, 0.0) if run == "nocut" else cut)
            record(f"{folder}/{run}.wav", sweep_file)
            if raw_volume() != full:
                raise SystemExit("the volume changed during a sweep: measure again and leave the volume keys alone")
    finally:
        set_controls(cut)
        subprocess.run(["pactl", "set-sink-volume", RAW_SINK, volume], check=True)


def impulse_response(recorded, played):
    recorded = recorded.copy()
    skip, fade = int(SKIP_S * RATE), int(0.05 * RATE)
    recorded[:skip] = 0
    recorded[skip:skip + fade] *= np.sin(np.linspace(0, np.pi / 2, fade)) ** 2
    n = 1 << int(np.ceil(np.log2(len(recorded) + len(played))))
    x, y = np.fft.rfft(played, n), np.fft.rfft(recorded, n)
    freq = np.fft.rfftfreq(n, 1 / RATE)
    h = y * np.conj(x) / (np.abs(x) ** 2 + 1e-9 * np.max(np.abs(x)) ** 2)
    h[(freq < 18) | (freq > 21000)] = 0
    return np.fft.irfft(h, n)


def windowed(ir, window_ms):
    """Spectrum of the first window_ms after the sound arrives, and of the
    same window one second later, where only noise is left."""
    level = np.abs(ir)
    level[:int(SKIP_S * RATE)] = 0
    level[int(6 * RATE):] = 0
    peak = int(np.argmax(level))
    early = peak - int(0.005 * RATE)
    onset = early + int(np.argmax(level[early:peak + 1] > 0.2 * level[peak]))
    lead = int(0.001 * RATE)
    start = onset - lead
    n = int(window_ms / 1000 * RATE)
    window = np.ones(n)
    window[:lead] = np.sin(np.linspace(0, np.pi / 2, lead)) ** 2
    fall = n // 5
    window[-fall:] = np.cos(np.linspace(0, np.pi / 2, fall)) ** 2
    size = 1 << 18
    later = start + RATE
    return (np.fft.rfftfreq(size, 1 / RATE),
            np.abs(np.fft.rfft(ir[start:start + n] * window, size)),
            np.abs(np.fft.rfft(ir[later:later + n] * window, size)))


def band_levels(freq, spectrum, centers):
    """Level in dB per sixth-octave band."""
    levels = []
    for center in centers:
        band = (freq >= center * 2 ** (-1 / 12)) & (freq <= center * 2 ** (1 / 12))
        levels.append(10 * np.log10(np.mean(spectrum[band] ** 2)))
    return np.array(levels)


def analyze(folder):
    played = sweep()
    centers = 40 * 2 ** (np.arange(0, 57) / 12)  # 40 Hz to 1 kHz in twelfth octaves
    mids = (centers >= MIDS[0]) & (centers <= MIDS[1])
    bass = (centers >= 50) & (centers <= 180)
    result = {}
    for run in RUNS:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", wavfile.WavFileWarning)
            rate, recorded = wavfile.read(f"{folder}/{run}.wav")
        if rate != RATE or recorded.ndim != 2 or recorded.shape[1] != 4:
            raise SystemExit(f"{run}.wav: expected 4 channels at {RATE} Hz")
        for window_ms in (30, 300):
            signal_db, noise_db = [], []
            for mic in range(4):
                freq, heard, noise = windowed(impulse_response(recorded[:, mic].astype(float), played), window_ms)
                signal_db.append(band_levels(freq, heard, centers))
                noise_db.append(band_levels(freq, noise, centers))
            signal_db, noise_db = np.array(signal_db), np.array(noise_db)
            relative = signal_db - signal_db[:, mids].mean(axis=1, keepdims=True)
            result[run, window_ms] = {
                "response": relative.mean(axis=0),
                "snr": (signal_db - noise_db)[:, bass].min(),
                "mics_bass": np.ptp(signal_db[:, bass], axis=0).max(),
                "mics_above": np.ptp(signal_db[:, centers >= 200], axis=0).max(),
            }

    now, nocut, again = (result[run, 30]["response"] for run in RUNS)
    print(f"Level relative to the mids ({MIDS[0]}-{MIDS[1]} Hz), 30 ms window, mean of the four mics:\n")
    print("     Hz    now   cut at 0 dB")
    for i in range(0, len(centers), 2):
        if 45 <= centers[i] <= 260:
            print(f"  {centers[i]:5.0f}  {now[i]:+5.1f}  {nocut[i]:+5.1f}")
    hump = (centers >= 85) & (centers <= 170)
    late = result["now", 300]["response"]
    for label, response in (("now", now), ("cut at 0 dB", nocut), ("now, 300 ms window", late)):
        i = int(np.argmax(np.where(hump, response, -np.inf)))
        print(f"\n  hump, {label}: {response[i]:+.1f} dB at {centers[i]:.0f} Hz", end="")
    repeat = np.abs(now - again)[centers >= 50].max()
    snr = min(result[run, 30]["snr"] for run in RUNS)
    print(f"\n\n  the two runs with the current tuning differ by up to {repeat:.1f} dB")
    print(f"  signal above noise, 50-180 Hz, worst mic and run: {snr:.0f} dB")
    print(f"  the mics differ by up to {result['now', 30]['mics_bass']:.1f} dB from 50 to 180 Hz "
          f"and {result['now', 30]['mics_above']:.1f} dB above 200 Hz")
    if repeat > 1 or snr < 20:
        print("\n  DISTURBED: the runs disagree or the noise is too high. Something else made"
              "\n  noise during a sweep. Don't use these numbers; measure again.")


def main():
    parser = argparse.ArgumentParser(description="Measure the speakers' bass with the built-in mics.")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--keep", metavar="DIR", help="keep the recordings in DIR")
    group.add_argument("--analyze", metavar="DIR", help="print again from recordings kept in DIR, without playing")
    args = parser.parse_args()
    if args.analyze:
        analyze(args.analyze)
    elif args.keep:
        subprocess.run(["mkdir", "-p", args.keep], check=True)
        measure(args.keep)
        analyze(args.keep)
    else:
        with tempfile.TemporaryDirectory() as folder:
            measure(folder)
            analyze(folder)


if __name__ == "__main__":
    main()

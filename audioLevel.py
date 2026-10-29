#!/usr/bin/env python3
"""Live audio-level source for the Hyprwhspr Voice Overlay desktop widget.

Prints one line per update on stdout (~12 Hz):

    R <level>   level 0.000-1.000, audio present
    S <mode>    resolved source mode, printed once at start
    I           idle: no audio for more than --hold seconds (once per transition)

Levels are perceptual (linear RMS mapped through dB, silence -> 0) so bars have
usable dynamics regardless of mic gain or player volume. Pure stdlib; the only
external programs are `pw-record` (PipeWire) and `wpctl` (WirePlumber).

Sources:
    hyprwhspr  read hyprwhspr IPC files (recording_status / audio_level)
    mic        capture the default microphone
    output     capture the default sink monitor (everything you hear)
    both       max(mic, output)
    auto       hyprwhspr when ~/.config/hyprwhspr exists, else output

Note: a PipeWire capture stream must target a node by **serial**, not by
node.name -- `pw-record --target <sink node.name>` silently falls back to the
default source (the microphone), which makes an output monitor look alive when
it is only hearing room noise.
"""

import argparse
import array
import math
import os
import subprocess
import sys
import threading
import time

RATE = 8000
CHANNELS = 1
BLOCK_MS = 40
BLOCK_BYTES = max(2, int(RATE * BLOCK_MS / 1000) * 2 * CHANNELS)

DB_FLOOR = -50.0        # rms at or below this -> level 0
DB_CEIL = -8.0          # rms at or above this -> level 1
ABS_GATE_RMS = 45.0     # never treat anything quieter as sound (~ -57 dBFS)
MAX_GATE_RMS = 600.0    # ceiling for a calibrated gate (~ -35 dBFS): room hum in
                        # a noisy place must not mute the widget permanently
NOISE_MULT = 2.5        # signal must exceed the calibrated noise floor by this
CALIBRATION_BLOCKS = 25 # ~1 s of samples used to measure the noise floor
CALIBRATION_SKIP = 5    # blocks skipped: the device's DMA ramp is not noise


def log(msg):
    sys.stderr.write("audio_level: %s\n" % msg)
    sys.stderr.flush()


def to_level(rms):
    """Linear RMS (0..32768) -> perceptual level (0..1)."""
    if rms <= 0.0:
        return 0.0
    db = 20.0 * math.log10(rms / 32768.0)
    level = (db - DB_FLOOR) / (DB_CEIL - DB_FLOOR)
    return 0.0 if level < 0.0 else (1.0 if level > 1.0 else level)


def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "hyprwhspr")


def ensure_runtime_dir():
    if os.environ.get("XDG_RUNTIME_DIR"):
        return
    guess = "/run/user/%d" % os.getuid()
    if os.path.isdir(guess):
        os.environ["XDG_RUNTIME_DIR"] = guess


def wpctl_serial(alias):
    """object.serial of a WirePlumber alias such as @DEFAULT_AUDIO_SINK@."""
    try:
        out = subprocess.run(["wpctl", "inspect", alias],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception as exc:
        log("wpctl failed: %s" % exc)
        return None
    for line in out.splitlines():
        line = line.strip().lstrip("*").strip()
        if line.startswith("object.serial"):
            value = line.split("=", 1)[1].strip().strip('"')
            return value or None
    return None


class Capture(threading.Thread):
    """One long-lived pw-record child feeding a rolling level with a noise gate."""

    def __init__(self, kind):
        super().__init__(daemon=True)
        self.kind = kind            # "mic" | "output"
        self.level = 0.0
        self.target = None
        self.gate = None            # RMS gate from the one-shot calibration
        self._seed = []
        self.stopped = False

    def resolve_target(self):
        if self.kind == "output":
            return wpctl_serial("@DEFAULT_AUDIO_SINK@")
        return None                 # mic: let PipeWire pick the default source

    def calibrate(self, rms):
        """One-shot noise-floor measurement -> gate in RMS units.

        Deliberately one-shot instead of continuously adaptive: a gate that
        learns while audio plays slowly climbs to the music level and the bars
        go dead mid-song. A capped gate cannot be poisoned by loud audio, and
        mic hiss (~ -40 dBFS here) stays below it.
        """
        self._seed.append(rms)
        if len(self._seed) < CALIBRATION_SKIP + CALIBRATION_BLOCKS:
            return None
        values = sorted(self._seed[CALIBRATION_SKIP:])
        noise = values[len(values) // 2]          # median of the calibration window
        self.gate = min(max(noise * NOISE_MULT, ABS_GATE_RMS), MAX_GATE_RMS)
        return self.gate

    def run(self):
        while not self.stopped:
            self.target = self.resolve_target()
            if self.kind == "output" and not self.target:
                time.sleep(2.0)
                continue
            cmd = ["pw-record", "--rate", str(RATE), "--channels", str(CHANNELS),
                   "--format", "s16", "--latency", "100ms"]
            if self.target:
                cmd += ["--target", self.target]
            cmd.append("-")
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, bufsize=0)
            except Exception as exc:
                log("pw-record (%s) failed to start: %s" % (self.kind, exc))
                time.sleep(1.5)
                continue

            self.gate = None
            self._seed = []
            last_recheck = time.time()
            while not self.stopped:
                chunk = self.read_exact(proc.stdout, BLOCK_BYTES)
                if not chunk:
                    break
                samples = array.array("h")
                samples.frombytes(chunk[: len(chunk) // 2 * 2])
                if not samples:
                    continue
                peak = 0
                acc = 0
                for value in samples:
                    acc += value * value
                    mag = value if value >= 0 else -value
                    if mag > peak:
                        peak = mag
                rms = math.sqrt(acc / len(samples))
                # Peak only shapes the level of real sound; the gate itself is
                # driven by RMS, otherwise ambient hiss (low RMS, high peak)
                # reads as continuous audio and the bars never rest.
                gate = self.calibrate(rms)
                if gate is not None and rms > gate:
                    self.level = to_level(max(rms, peak * 0.3))
                else:
                    self.level = 0.0

                now = time.time()
                if now - last_recheck > 5.0:
                    last_recheck = now
                    if self.kind == "output":
                        current = wpctl_serial("@DEFAULT_AUDIO_SINK@")
                        if current and current != self.target:
                            break       # default sink changed: restart capture

            self.level = 0.0
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass
            if not self.stopped:
                time.sleep(0.5)

    @staticmethod
    def read_exact(stream, count):
        buf = b""
        while len(buf) < count:
            try:
                chunk = stream.read(count - len(buf))
            except Exception:
                return b""
            if not chunk:
                return buf
            buf += chunk
        return buf

    def stop(self):
        self.stopped = True


def hypr_state():
    """(recording, amplitude) from hyprwhspr's IPC files."""
    path = config_dir()
    if not os.path.exists(os.path.join(path, "recording_status")):
        return False, 0.0
    try:
        with open(os.path.join(path, "audio_level"), "r") as handle:
            value = float(handle.read().strip() or 0.0)
    except Exception:
        value = 0.0
    return True, max(0.0, min(1.0, value))


def main():
    parser = argparse.ArgumentParser(description="Audio level lines for the voice overlay widget")
    parser.add_argument("--source", default="auto",
                        choices=["auto", "hyprwhspr", "mic", "output", "both"])
    parser.add_argument("--hold", type=float, default=0.35,
                        help="seconds below the gate before reporting idle (default 0.35)")
    parser.add_argument("--hz", type=float, default=12.0, help="updates per second (default 12)")
    args = parser.parse_args()

    ensure_runtime_dir()

    mode = args.source
    if mode == "auto":
        mode = "hyprwhspr" if os.path.isdir(config_dir()) else "output"

    captures = []
    if mode in ("mic", "both"):
        captures.append(Capture("mic"))
    if mode in ("output", "both"):
        captures.append(Capture("output"))
    for capture in captures:
        capture.start()

    interval = 1.0 / max(1.0, args.hz)
    print("S %s" % mode, flush=True)
    print("I", flush=True)

    last_sound = 0.0
    idle = True
    while True:
        started = time.time()
        if mode == "hyprwhspr":
            recording, amplitude = hypr_state()
            if recording:
                print("R %.3f" % to_level(amplitude * 32768.0), flush=True)
                idle = False
                last_sound = started
            elif not idle:
                print("I", flush=True)
                idle = True
        else:
            level = max((capture.level for capture in captures), default=0.0)
            if level > 0.0:
                print("R %.3f" % level, flush=True)
                idle = False
                last_sound = started
            elif not idle and started - last_sound > args.hold:
                print("I", flush=True)
                idle = True
        delay = interval - (time.time() - started)
        if delay > 0:
            time.sleep(delay)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

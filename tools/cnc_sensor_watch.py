#!/usr/bin/env python3
"""
Bench-side CNC hint monitor (webcam + microphone).

Uses coarse heuristics only — not safety-rated and not a substitute for limits,
E-stop, or staying near the machine.

  pip install -r requirements-cnc-watch.txt
  python tools/cnc_sensor_watch.py

Alerts:
  - AUDIO_SPIKE: mic RMS jumps far above the calibrated room baseline.
  - MOTION_DROP: frame-to-frame motion fell for a sustained interval after motion
    had been seen (very rough proxy for “something stopped moving”).
  - GRBL_ALARM / GRBL_HOLD / GRBL_ERROR / GRBL_PN: from periodic ``?`` status on --com
    (close Candle / other senders so this script owns the port).
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np


def _load_sounddevice():
    try:
        import sounddevice as sd
    except ImportError as e:
        print("Missing sounddevice. Run: pip install -r requirements-cnc-watch.txt", file=sys.stderr)
        raise SystemExit(1) from e
    return sd


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def rms_audio(chunk: np.ndarray) -> float:
    if chunk.size == 0:
        return 0.0
    return float(math.sqrt(np.mean(np.square(chunk.astype(np.float64)))))


def _open_grbl_serial(port: str):
    try:
        import serial
    except ImportError as e:
        print("Missing pyserial. Run: pip install -r requirements-cnc-watch.txt", file=sys.stderr)
        raise SystemExit(1) from e

    try:
        ser = serial.Serial(port, 115200, timeout=0.15)
    except serial.SerialException as e:
        raise SystemExit(
            f"Cannot open serial {port}: {e}\n"
            "Close Candle / G-code streamers using this COM port, then retry."
        ) from e

    ser.dtr = False
    ser.rts = False
    time.sleep(2.0)
    return ser


def _poll_grbl_status(ser) -> str:
    ser.reset_input_buffer()
    ser.write(b"?\r")
    time.sleep(0.08)
    return ser.read(4096).decode("ascii", errors="replace")


def _latest_status_angle(raw: str) -> str:
    blocks = re.findall(r"<[^>]+>", raw)
    return blocks[-1] if blocks else ""


def _grbl_serial_alerts(raw: str, status_line: str) -> list[tuple[str, str]]:
    """Return (kind, detail) tuples for notable GRBL conditions."""
    found: list[tuple[str, str]] = []
    st = status_line
    if not st:
        return found

    head = st.split("|", 1)[0]
    if re.match(r"<Alarm", head, re.I):
        found.append(("GRBL_ALARM", st[:220]))
    elif re.match(r"<Hold", head, re.I):
        found.append(("GRBL_HOLD", st[:220]))

    em = re.search(r"error:\s*(\d+)", raw, re.I)
    if em:
        found.append(("GRBL_ERROR", f"error:{em.group(1)} — {raw.strip()[:180]}"))

    mp = re.search(r"\|Pn:([^|]*)\|", st)
    if mp:
        pins = mp.group(1).strip()
        if pins:
            found.append(("GRBL_PN", f"limit/probe pins asserted Pn:{pins} — {st[:200]}"))

    return found


def main() -> None:
    ap = argparse.ArgumentParser(description="Webcam + mic CNC bench monitor (heuristic alerts).")
    ap.add_argument("--camera", type=int, default=0, help="OpenCV camera index (default 0).")
    ap.add_argument("--width", type=int, default=320, help="Capture width (resize for CPU).")
    ap.add_argument("--height", type=int, default=240, help="Capture height.")
    ap.add_argument("--sample-rate", type=int, default=22050, help="Audio sample rate.")
    ap.add_argument("--audio-block", type=int, default=2048, help="Audio frames per read.")
    ap.add_argument("--calibrate-s", type=float, default=3.0, help="Seconds to learn baseline audio motion.")
    ap.add_argument(
        "--audio-spike-sigma",
        type=float,
        default=10.0,
        help="Alert if RMS exceeds baseline_mean + this * baseline_std.",
    )
    ap.add_argument(
        "--audio-floor",
        type=float,
        default=0.08,
        help="Absolute RMS alert floor (float32-ish scale); catches huge noises even if baseline is noisy.",
    )
    ap.add_argument(
        "--motion-low",
        type=float,
        default=1.2,
        help="Mean abs grayscale frame diff below this counts as “static” (after resize).",
    )
    ap.add_argument(
        "--motion-drop-s",
        type=float,
        default=45.0,
        help="Warn if motion stays below --motion-low this many seconds after motion was seen.",
    )
    ap.add_argument("--cooldown-s", type=float, default=5.0, help="Min seconds between duplicate alerts of same kind.")
    ap.add_argument("--log-csv", type=Path, default=None, help="Append periodic samples / alerts to CSV.")
    ap.add_argument("--no-audio", action="store_true", help="Camera only (motion hints).")
    ap.add_argument(
        "--com",
        type=str,
        default=None,
        metavar="PORT",
        help="GRBL serial port (e.g. COM7). Close Candle/streamers first — port must be exclusive.",
    )
    ap.add_argument(
        "--serial-poll-s",
        type=float,
        default=0.25,
        help="Minimum seconds between ? status polls.",
    )
    ap.add_argument(
        "--serial-alert-cooldown-s",
        type=float,
        default=12.0,
        help="Minimum seconds between repeats of the same GRBL_* alert kind.",
    )
    args = ap.parse_args()

    sd = None if args.no_audio else _load_sounddevice()

    ser = None
    if args.com:
        print(f"[{now_iso()}] Opening GRBL serial {args.com} …")
        ser = _open_grbl_serial(args.com)

    cap = cv2.VideoCapture(args.camera, cv2.CAP_DSHOW)
    if not cap.isOpened():
        cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        raise SystemExit(f"Cannot open camera index {args.camera}")
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)

    prev_gray: np.ndarray | None = None
    audio_buf: list[float] = []
    motion_buf: list[float] = []
    t_cal0 = time.monotonic()

    print(
        f"[{now_iso()}] Calibrating ~{args.calibrate_s:.1f}s — stay quiet; aim camera at machine; "
        f"stop with Ctrl+C."
    )
    last_audio_alert = 0.0
    last_motion_alert = 0.0
    motion_seen = False
    low_motion_since: float | None = None
    last_serial_poll = 0.0
    last_status_display = ""
    last_serial_alert_ts: dict[str, float] = {}

    def maybe_csv(kind: str, rms: float, mot: float, note: str = "") -> None:
        if args.log_csv is None:
            return
        args.log_csv.parent.mkdir(parents=True, exist_ok=True)
        new_file = not args.log_csv.exists()
        with args.log_csv.open("a", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            if new_file:
                w.writerow(["utc", "kind", "rms", "motion", "note"])
            w.writerow([now_iso(), kind, f"{rms:.6f}", f"{mot:.4f}", note])

    monitoring_started = False

    try:
        while True:
            t = time.monotonic()
            ret, bgr = cap.read()
            if not ret or bgr is None:
                print(f"[{now_iso()}] WARN: frame grab failed")
                time.sleep(0.05)
                continue

            small = cv2.resize(bgr, (args.width, args.height), interpolation=cv2.INTER_AREA)
            gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
            mot = 0.0
            if prev_gray is not None:
                mot = float(np.mean(cv2.absdiff(gray, prev_gray)))
            prev_gray = gray

            rms = 0.0
            if sd is not None:
                chunk = sd.rec(
                    args.audio_block,
                    samplerate=args.sample_rate,
                    channels=1,
                    dtype="float32",
                )
                sd.wait()
                rms = rms_audio(chunk)

            calibrating = (t - t_cal0) < args.calibrate_s

            if ser is not None and (t - last_serial_poll) >= args.serial_poll_s:
                last_serial_poll = t
                raw_g = _poll_grbl_status(ser)
                grbl_snip = _latest_status_angle(raw_g)
                if grbl_snip:
                    last_status_display = grbl_snip
                for kind, detail in _grbl_serial_alerts(raw_g, grbl_snip):
                    if t - last_serial_alert_ts.get(kind, 0.0) >= args.serial_alert_cooldown_s:
                        print(f"\n[{now_iso()}] ALERT {kind}: {detail}")
                        maybe_csv(kind, rms, mot, detail[:500])
                        last_serial_alert_ts[kind] = t

            if calibrating:
                if sd is not None:
                    audio_buf.append(rms)
                motion_buf.append(mot)
                if int((t - t_cal0) * 10) % 5 == 0:
                    if sd is not None:
                        print(f"\r  cal… rms={rms:.5f} motion={mot:.3f}   ", end="", flush=True)
                    else:
                        print(f"\r  cal… motion={mot:.3f}   ", end="", flush=True)
                continue

            if not monitoring_started:
                print()
                print(f"[{now_iso()}] Monitoring (Ctrl+C to stop).")
                monitoring_started = True

            if audio_buf:
                a_mean = float(np.mean(audio_buf))
                a_std = float(np.std(audio_buf)) + 1e-9
            else:
                a_mean, a_std = 0.0, 1e-9
            if motion_buf:
                m_med = float(np.median(motion_buf))
            else:
                m_med = 0.0

            if mot > max(args.motion_low, m_med * 2.5):
                motion_seen = True
                low_motion_since = None

            if motion_seen and mot < args.motion_low:
                if low_motion_since is None:
                    low_motion_since = t
                elif (t - low_motion_since) >= args.motion_drop_s:
                    if t - last_motion_alert >= args.cooldown_s:
                        msg = (
                            f"MOTION_DROP ~{t - low_motion_since:.0f}s near-static "
                            f"(motion={mot:.3f} < {args.motion_low}) — verify machine / stream."
                        )
                        print(f"\n[{now_iso()}] ALERT {msg}")
                        maybe_csv("MOTION_DROP", rms, mot, msg)
                        last_motion_alert = t
            else:
                low_motion_since = None

            spike = sd is not None and rms > max(
                args.audio_floor, a_mean + args.audio_spike_sigma * a_std
            )
            if spike and t - last_audio_alert >= args.cooldown_s:
                msg = (
                    f"AUDIO_SPIKE rms={rms:.5f} (baseline ~{a_mean:.5f}+/-{a_std:.5f}) "
                    f"— possible crash, stall screech, or loud knock."
                )
                print(f"\n[{now_iso()}] ALERT {msg}")
                maybe_csv("AUDIO_SPIKE", rms, mot, msg)
                last_audio_alert = t

            line = f"\r  motion={mot:.3f}"
            if sd is not None:
                line += f"  rms={rms:.5f}  baseline_rms~{a_mean:.5f}"
            if last_status_display:
                g = last_status_display.replace("\r", " ").strip()
                if len(g) > 52:
                    g = g[:49] + "…"
                line += f"  | {g}"
            line += "   "
            print(line, end="", flush=True)
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        if ser is not None:
            try:
                ser.close()
            except Exception:
                pass
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()

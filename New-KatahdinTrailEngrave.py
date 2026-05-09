"""Shallow single-line G-code for the Appalachian Trail on the Katahdin board.

Use after the main terrain carve: a light groove to hold a thin red paint line.
Default depth is conservative for hard oak; adjust --depth-mm if needed.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import katahdin_trail as kt


def fnum(v: float) -> str:
    return f"{v:.4f}".rstrip("0").rstrip(".") or "0"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path("samples/katahdin-trail-light.nc"))
    ap.add_argument("--depth-mm", type=float, default=-0.35, help="Negative Z below stock top (shallow groove).")
    ap.add_argument("--safe-z", type=float, default=10.0)
    ap.add_argument("--feed-xy", type=int, default=400)
    ap.add_argument("--feed-plunge", type=int, default=120)
    ap.add_argument("--spin-rpm", type=int, default=12000)
    ap.add_argument("--spinup-s", type=int, default=4)
    ap.add_argument("--cols", type=int, default=kt.DEFAULT_COLS)
    ap.add_argument("--rows", type=int, default=kt.DEFAULT_ROWS)
    ap.add_argument("--px-mm", type=float, default=kt.DEFAULT_PX_MM)
    args = ap.parse_args()

    if args.depth_mm >= 0:
        raise SystemExit("--depth-mm must be negative (below stock top).")

    pts = kt.trail_points_g54(cols=args.cols, rows=args.rows, px_mm=args.px_mm)
    if len(pts) < 2:
        raise SystemExit("Not enough trail points inside the bbox.")

    lines: list[str] = [
        "; Katahdin Appalachian Trail - shallow groove for paint (G stock top = Z0)",
        "; Run AFTER main terrain carve; same G54 XY / Z0 as terrain job.",
        f"; Depth {fnum(args.depth_mm)} mm | approx center of small vee or ball tip",
        f"M3 S{args.spin_rpm}",
        f"G4 P{args.spinup_s}",
        "G21",
        "G17",
        "G90",
        "G94",
        "G54",
        f"G0 Z{fnum(args.safe_z)}",
        "",
    ]

    x0, y0 = pts[0]
    lines.append(f"G0 X{fnum(x0)} Y{fnum(y0)}")
    lines.append(f"G1 Z{fnum(args.depth_mm)} F{args.feed_plunge}")
    for x, y in pts[1:]:
        lines.append(f"G1 X{fnum(x)} Y{fnum(y)} F{args.feed_xy}")

    lines.append(f"G0 Z{fnum(args.safe_z)}")
    lines.append("M5")
    lines.append("")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines), encoding="ascii")
    print(f"Wrote {args.out} ({len(pts)} points)")


if __name__ == "__main__":
    main()

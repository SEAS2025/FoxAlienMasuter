"""Render a 3D orthographic view of a terrain heightmap (from New-TerrainNc.py).

The PNG is normalized depth: bright pixels are peaks (shallow cut / high stock),
dark pixels are the deepest carved valleys. For display, Z is mapped so peaks are
tall using --max-depth-mm (match your --max-cut-mm for a physically scaled plot).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--in",
        dest="inp",
        type=Path,
        default=Path("samples/katahdin.heightmap.png"),
        help="Grayscale heightmap (bright = peaks).",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("samples/katahdin.ortho3d.png"),
        help="Output PNG (orthographic 3D render).",
    )
    ap.add_argument(
        "--max-depth-mm",
        type=float,
        default=22.0,
        help="Peak-to-valley vertical scale in mm (use same as New-TerrainNc --max-cut-mm).",
    )
    ap.add_argument("--px-mm", type=float, default=1.0, help="Pixel pitch in mm.")
    ap.add_argument("--elev", type=float, default=28.0, help="Camera elevation (deg).")
    ap.add_argument("--azim", type=float, default=-58.0, help="Camera azimuth (deg).")
    ap.add_argument(
        "--step",
        type=int,
        default=1,
        help="Subsample every Nth pixel (2 or 3 speeds up large maps).",
    )
    ap.add_argument("--dpi", type=int, default=180, help="Figure DPI.")
    ap.add_argument(
        "--cmap",
        type=str,
        default="terrain",
        help="Matplotlib colormap for the surface.",
    )
    args = ap.parse_args()

    if args.step < 1:
        raise SystemExit("--step must be >= 1")

    if not args.inp.exists():
        raise SystemExit(f"Missing input: {args.inp}")

    gray = np.asarray(Image.open(args.inp).convert("L"), dtype=np.float32)
    if args.step > 1:
        gray = gray[:: args.step, :: args.step]

    h, w = gray.shape
    z = (gray / 255.0) * args.max_depth_mm

    x = np.arange(w, dtype=np.float32) * args.px_mm * args.step
    y = np.arange(h, dtype=np.float32) * args.px_mm * args.step
    x_grid, y_grid = np.meshgrid(x, y)

    fig = plt.figure(figsize=(9.5, 9.5), dpi=args.dpi)
    ax = fig.add_subplot(111, projection="3d")
    try:
        ax.set_proj_type("ortho")
    except Exception as exc:
        raise SystemExit(
            "Orthographic projection requires matplotlib>=3.2: " + str(exc)
        ) from exc

    surf = ax.plot_surface(
        x_grid,
        y_grid,
        z,
        cmap=args.cmap,
        linewidth=0,
        antialiased=True,
        rstride=1,
        cstride=1,
        shade=True,
    )

    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    ax.set_zlabel("Z (mm)")
    ax.view_init(elev=args.elev, azim=args.azim)

    xr = float(np.ptp(x))
    yr = float(np.ptp(y))
    zr = float(np.ptp(z)) or 1.0
    ax.set_box_aspect((xr, yr, zr))

    fig.colorbar(surf, ax=ax, shrink=0.55, aspect=18, label="Height (mm)")
    ax.set_title("Orthographic 3D (height ∝ carved relief)")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, bbox_inches="tight", pad_inches=0.12, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()

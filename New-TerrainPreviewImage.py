"""Create a shaded-relief image that approximates how the carved board will read.

Reads the grayscale heightmap emitted by New-TerrainNc.py (bright = peaks / high
stock, dark = deepest cuts). Derives a synthetic surface and applies hillshade +
a slight warm pine tint so it reads like physical relief under raking light.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def hillshade(
    z: np.ndarray,
    *,
    cell_mm: float = 1.0,
    azimuth_deg: float = 315.0,
    altitude_deg: float = 42.0,
) -> np.ndarray:
    """ESRI-style hillshade in [0, 1]."""
    z = z.astype(np.float64)
    dy, dx = np.gradient(z, cell_mm)
    slope = np.arctan(np.hypot(dx, dy))
    aspect = np.arctan2(-dx, dy)
    az = np.radians(360.0 - azimuth_deg + 90.0)
    alt = np.radians(altitude_deg)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    hs = (hs - hs.min()) / (hs.max() - hs.min() + 1e-9)
    return hs.astype(np.float32)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--in",
        dest="inp",
        type=Path,
        default=Path("samples/katahdin.heightmap.png"),
        help="Grayscale heightmap from New-TerrainNc (bright = peaks).",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("samples/katahdin.carve-preview.png"),
        help="RGB relief preview PNG.",
    )
    ap.add_argument("--px-mm", type=float, default=1.0, help="Pixel pitch in mm (for shading scale).")
    ap.add_argument("--azimuth", type=float, default=315.0, help="Light azimuth, degrees.")
    ap.add_argument("--altitude", type=float, default=42.0, help="Light elevation, degrees.")
    args = ap.parse_args()

    if not args.inp.exists():
        raise SystemExit(f"Missing input: {args.inp}")

    gray = np.asarray(Image.open(args.inp).convert("L"), dtype=np.float32)
    # Surface height for carving: peaks high, valleys low (matches PNG convention).
    z = gray

    hs = hillshade(z, cell_mm=args.px_mm, azimuth_deg=args.azimuth, altitude_deg=args.altitude)

    # Warm pine-ish base color; modulate by hillshade.
    wood = np.array([0.88, 0.72, 0.52], dtype=np.float32)
    rgb = np.stack([hs * wood[i] for i in range(3)], axis=-1)
    rgb = np.clip(rgb * 1.08, 0.0, 1.0)
    out = (rgb * 255.0).astype(np.uint8)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, mode="RGB").save(args.out)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()

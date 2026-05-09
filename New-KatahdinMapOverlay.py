"""Trail-only preview: hillshade base + thin red Appalachian Trail (OpenStreetMap).

Reads samples/katahdin.heightmap.png, overlays the A.T. from katahdin_trail.py,
writes samples/katahdin.map-overlay.png (no lettering).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import katahdin_trail as kt


def hillshade(
    z: np.ndarray,
    *,
    cell_mm: float = 1.0,
    azimuth_deg: float = 315.0,
    altitude_deg: float = 42.0,
) -> np.ndarray:
    z = z.astype(np.float64)
    dy, dx = np.gradient(z, cell_mm)
    slope = np.arctan(np.hypot(dx, dy))
    aspect = np.arctan2(-dx, dy)
    az = np.radians(360.0 - azimuth_deg + 90.0)
    alt = np.radians(altitude_deg)
    hs = np.sin(alt) * np.cos(slope) + np.cos(alt) * np.sin(slope) * np.cos(az - aspect)
    hs = (hs - hs.min()) / (hs.max() - hs.min() + 1e-9)
    return hs.astype(np.float32)


def relief_rgb(gray: np.ndarray, px_mm: float) -> np.ndarray:
    hs = hillshade(gray.astype(np.float32), cell_mm=px_mm)
    wood = np.array([0.88, 0.72, 0.52], dtype=np.float32)
    rgb = np.stack([hs * wood[i] for i in range(3)], axis=-1)
    rgb = np.clip(rgb * 1.08, 0.0, 1.0)
    return (rgb * 255.0).astype(np.uint8)


def lonlat_to_pixel(lon: float, lat: float, w: int, h: int) -> tuple[float, float]:
    x = (lon - kt.LON_MIN) / (kt.LON_MAX - kt.LON_MIN) * (w - 1)
    y = (kt.LAT_MAX - lat) / (kt.LAT_MAX - kt.LAT_MIN) * (h - 1)
    return x, y


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--heightmap", type=Path, default=Path("samples/katahdin.heightmap.png"))
    ap.add_argument("--out", type=Path, default=Path("samples/katahdin.map-overlay.png"))
    ap.add_argument("--px-mm", type=float, default=1.0)
    ap.add_argument("--line-width", type=int, default=2, help="Preview trail thickness in pixels")
    args = ap.parse_args()

    if not args.heightmap.exists():
        raise SystemExit(f"Missing heightmap: {args.heightmap}")

    gray = np.asarray(Image.open(args.heightmap).convert("L"), dtype=np.float32)
    h, w = gray.shape
    base = Image.fromarray(relief_rgb(gray, args.px_mm), mode="RGB")
    overlay = base.copy()
    dr = ImageDraw.Draw(overlay)

    trail = kt.fetch_trail_wgs84()
    px_line: list[tuple[float, float]] = []
    for lon, lat in trail:
        if not (kt.LON_MIN <= lon <= kt.LON_MAX and kt.LAT_MIN <= lat <= kt.LAT_MAX):
            continue
        px_line.append(lonlat_to_pixel(lon, lat, w, h))

    if len(px_line) >= 2:
        # Thin red line (matches intent: light groove you'd paint later)
        seq = [(p[0], p[1]) for p in px_line]
        lw = max(1, args.line_width)
        if lw > 1:
            dr.line(seq, fill=(50, 25, 15), width=lw + 1)
        dr.line(seq, fill=(210, 45, 55), width=lw)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    overlay.save(args.out)
    print(f"Wrote {args.out}  (trail screen points: {len(px_line)})")


if __name__ == "__main__":
    main()

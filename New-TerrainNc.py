"""Generate 3D-relief CNC G-code (rough + finish) from a real DEM bbox.

Pipeline:
  1. Compute slippy-map XYZ tile coverage for the bbox at zoom Z.
  2. Download Mapzen Terrarium PNG tiles from AWS Open Data
     (s3://elevation-tiles-prod, public, no auth).
  3. Decode RGB -> elevation_m and stitch to a single grid.
  4. Crop to exact bbox, resample to board resolution.
  5. Convert elevation -> negative depth from stock top (Z0).
  6. Emit GRBL/Candle-friendly NC files:
       <out>.rough.nc    : flat endmill, multi-pass step-down by Z tiers.
       <out>.finish.nc   : ball-nose endmill, raster scan in X.
     Both files share our M3 -> G4 -> setup -> G0 Z<safe> ordering.

CLI:
  python New-TerrainNc.py --name katahdin --lat-min 45.86 --lat-max 45.95 \
      --lon-min -68.99 --lon-max -68.85 --board-mm 356 \
      --stock-mm 25 --max-cut-mm 18 --vexag 1.0 \
      --rough-tool 3.0 --finish-tool 3.0 --finish-stepover 0.4 \
      --out samples/katahdin

  Use --board-mm ~356 (not 380) on Fox Alien Masuter when G54 WCO X ~ -363
  so max work X stays within ~363 mm travel to machine X=0.
"""

from __future__ import annotations

import argparse
import io
import math
import os
import sys
from pathlib import Path

import numpy as np
import requests
from PIL import Image

S3_TILE_URL = (
    "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
)
TILE_PX = 256


def lonlat_to_tile(lon: float, lat: float, z: int) -> tuple[float, float]:
    lat_rad = math.radians(lat)
    n = 2.0 ** z
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - math.log(math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n
    return x, y


def tile_to_lonlat(x: float, y: float, z: int) -> tuple[float, float]:
    n = 2.0 ** z
    lon = x / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * y / n)))
    return lon, math.degrees(lat_rad)


def fetch_tile(z: int, x: int, y: int, cache_dir: Path) -> np.ndarray:
    cache = cache_dir / f"{z}_{x}_{y}.png"
    if not cache.exists():
        url = S3_TILE_URL.format(z=z, x=x, y=y)
        r = requests.get(url, timeout=30)
        if r.status_code != 200:
            raise RuntimeError(f"Tile fetch failed {url} -> {r.status_code}")
        cache.write_bytes(r.content)
    img = Image.open(cache).convert("RGB")
    arr = np.asarray(img, dtype=np.float32)
    elev = arr[..., 0] * 256.0 + arr[..., 1] + arr[..., 2] / 256.0 - 32768.0
    return elev


def build_dem(lat_min, lat_max, lon_min, lon_max, zoom, cache_dir):
    x0f, y1f = lonlat_to_tile(lon_min, lat_min, zoom)
    x1f, y0f = lonlat_to_tile(lon_max, lat_max, zoom)
    x0, x1 = int(math.floor(min(x0f, x1f))), int(math.floor(max(x0f, x1f)))
    y0, y1 = int(math.floor(min(y0f, y1f))), int(math.floor(max(y0f, y1f)))

    cols, rows = (x1 - x0 + 1), (y1 - y0 + 1)
    grid = np.zeros((rows * TILE_PX, cols * TILE_PX), dtype=np.float32)

    print(f"Tiles: z={zoom} x=[{x0}..{x1}] y=[{y0}..{y1}]  ({cols * rows} tiles)")
    for j, ty in enumerate(range(y0, y1 + 1)):
        for i, tx in enumerate(range(x0, x1 + 1)):
            elev = fetch_tile(zoom, tx, ty, cache_dir)
            grid[j * TILE_PX : (j + 1) * TILE_PX, i * TILE_PX : (i + 1) * TILE_PX] = elev

    sub_x0 = (x0f - x0) * TILE_PX
    sub_x1 = (x1f - x0) * TILE_PX
    sub_y0 = (y0f - y0) * TILE_PX
    sub_y1 = (y1f - y0) * TILE_PX
    px0, py0 = int(math.floor(min(sub_x0, sub_x1))), int(math.floor(min(sub_y0, sub_y1)))
    px1, py1 = int(math.ceil(max(sub_x0, sub_x1))),  int(math.ceil(max(sub_y0, sub_y1)))
    cropped = grid[py0:py1, px0:px1]
    return cropped


def resample(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    img = Image.fromarray(arr, mode="F")
    img = img.resize((w, h), Image.BILINEAR)
    return np.asarray(img, dtype=np.float32)


def save_heightmap_png(depth_mm: np.ndarray, path: Path):
    d = depth_mm
    norm = (d - d.min()) / max(1e-9, (d.max() - d.min()))
    img = (norm * 255).astype(np.uint8)
    Image.fromarray(img, mode="L").save(path)


# ----- G-code emission ------------------------------------------------------

def fnum(v: float) -> str:
    return f"{v:.4f}".rstrip("0").rstrip(".") or "0"


def header_lines(title: str, spin_rpm: int, spinup_s: int, safe_z: float) -> list[str]:
    return [
        f"; {title}",
        "; M3 + dwell BEFORE any XYZ move; ends with M5.",
        f"M3 S{spin_rpm}",
        f"G4 P{spinup_s}",
        "G21",
        "G17",
        "G90",
        "G94",
        "G54",
        "",
        f"G0 Z{fnum(safe_z)}",
        "",
    ]


def _simplify_scanline(xs_mm, zs, z_tol):
    """Keep first/last points; drop interior points that fall on a straight
    XZ segment between their neighbours within z_tol mm. Returns indices."""
    if len(xs_mm) <= 2:
        return list(range(len(xs_mm)))
    keep = [0]
    for i in range(1, len(xs_mm) - 1):
        x0, z0 = xs_mm[keep[-1]], zs[keep[-1]]
        x1, z1 = xs_mm[i], zs[i]
        x2, z2 = xs_mm[i + 1], zs[i + 1]
        if (x2 - x0) == 0:
            keep.append(i); continue
        z_interp = z0 + (z2 - z0) * (x1 - x0) / (x2 - x0)
        if abs(z1 - z_interp) > z_tol:
            keep.append(i)
    keep.append(len(xs_mm) - 1)
    return keep


def emit_rough(
    depth_grid: np.ndarray,
    px_mm: float,
    out_path: Path,
    *,
    tool_dia_mm: float,
    step_down_mm: float,
    safe_z_mm: float,
    feed_xy: int,
    feed_plunge: int,
    feed_approach: int,
    spin_rpm: int,
    spinup_s: int,
    z_tol_mm: float = 0.15,
):
    rows, cols = depth_grid.shape
    pitch_px = max(1, int(round(tool_dia_mm * 0.9 / px_mm)))
    z_min_global = float(np.min(depth_grid))
    levels = []
    z = -step_down_mm
    while z > z_min_global:
        levels.append(z); z -= step_down_mm
    levels.append(z_min_global)

    L = header_lines(
        f"terrain ROUGH flat-endmill {tool_dia_mm}mm step-down {step_down_mm}mm",
        spin_rpm, spinup_s, safe_z_mm,
    )

    def to_xy(ix: int, iy: int) -> tuple[float, float]:
        x = ix * px_mm
        y = (rows - 1 - iy) * px_mm
        return x, y

    for tier_idx, z_tier in enumerate(levels):
        tier_depth = np.maximum(depth_grid, z_tier)
        L.append(f"; --- ROUGH tier {tier_idx + 1}/{len(levels)} Z >= {fnum(z_tier)} ---")
        L.append(f"G0 Z{fnum(safe_z_mm)}")
        for j_idx, iy in enumerate(range(0, rows, pitch_px)):
            row_z = tier_depth[iy, :]
            xs_idx = np.arange(0, cols, pitch_px)
            zs = row_z[xs_idx].astype(np.float32)
            xs_mm = xs_idx * px_mm
            if j_idx % 2:
                xs_idx = xs_idx[::-1]; xs_mm = xs_mm[::-1]; zs = zs[::-1]
            keep = _simplify_scanline(xs_mm, zs, z_tol_mm)
            if len(keep) < 2:
                continue
            _, y0 = to_xy(0, iy)
            x_first = float(xs_mm[keep[0]])
            L.append(f"G0 X{fnum(x_first)} Y{fnum(y0)}")
            L.append(f"G1 Z{fnum(float(zs[keep[0]]))} F{feed_plunge}")
            for k in keep[1:]:
                L.append(f"G1 X{fnum(float(xs_mm[k]))} Z{fnum(float(zs[k]))} F{feed_xy}")
            L.append(f"G0 Z{fnum(safe_z_mm)}")
        L.append("")

    L.append("G0 Z" + fnum(safe_z_mm))
    L.append("M5")
    out_path.write_text("\n".join(L) + "\n", encoding="ascii")
    return len(L), len(levels)


def emit_finish(
    depth_grid: np.ndarray,
    px_mm: float,
    out_path: Path,
    *,
    tool_dia_mm: float,
    stepover_mm: float,
    safe_z_mm: float,
    feed_xy: int,
    feed_plunge: int,
    spin_rpm: int,
    spinup_s: int,
    z_tol_mm: float = 0.05,
):
    """Finishing raster with a ball-nose. Sphere-centre Z is the min depth in
    a disc of tool radius around (x,y), so the ball never crashes a peak.
    Each scanline is simplified so straight XZ runs collapse into one G1."""
    rows, cols = depth_grid.shape
    radius_px = max(1, int(round((tool_dia_mm * 0.5) / px_mm)))
    pitch_px = max(1, int(round(stepover_mm / px_mm)))
    x_sample_px = max(1, int(round(stepover_mm / px_mm)))

    L = header_lines(
        f"terrain FINISH ball-nose {tool_dia_mm}mm stepover {stepover_mm}mm",
        spin_rpm, spinup_s, safe_z_mm,
    )

    def to_xy(ix: int, iy: int) -> tuple[float, float]:
        x = ix * px_mm
        y = (rows - 1 - iy) * px_mm
        return x, y

    for j_idx, iy in enumerate(range(0, rows, pitch_px)):
        y_lo = max(0, iy - radius_px)
        y_hi = min(rows, iy + radius_px + 1)
        band = depth_grid[y_lo:y_hi, :]
        row_min = band.min(axis=0)
        # 1-D ball compensation along X: rolling min within radius_px window.
        if radius_px > 0:
            from numpy.lib.stride_tricks import sliding_window_view
            pad = np.pad(row_min, radius_px, mode="edge")
            row_z = sliding_window_view(pad, 2 * radius_px + 1).min(axis=-1)
        else:
            row_z = row_min

        xs_idx = np.arange(0, cols, x_sample_px)
        zs = row_z[xs_idx].astype(np.float32)
        xs_mm = xs_idx * px_mm
        if j_idx % 2:
            xs_idx = xs_idx[::-1]; xs_mm = xs_mm[::-1]; zs = zs[::-1]

        keep = _simplify_scanline(xs_mm, zs, z_tol_mm)
        if len(keep) < 2:
            continue
        _, y0 = to_xy(0, iy)
        x_first = float(xs_mm[keep[0]])
        L.append(f"G0 X{fnum(x_first)} Y{fnum(y0)}")
        L.append(f"G1 Z{fnum(float(zs[keep[0]]))} F{feed_plunge}")
        for k in keep[1:]:
            L.append(f"G1 X{fnum(float(xs_mm[k]))} Z{fnum(float(zs[k]))} F{feed_xy}")
        L.append(f"G0 Z{fnum(safe_z_mm)}")

    L.append("M5")
    out_path.write_text("\n".join(L) + "\n", encoding="ascii")
    return len(L)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--lat-min", type=float, required=True)
    ap.add_argument("--lat-max", type=float, required=True)
    ap.add_argument("--lon-min", type=float, required=True)
    ap.add_argument("--lon-max", type=float, required=True)
    ap.add_argument("--zoom", type=int, default=12)
    ap.add_argument("--board-mm", type=float, default=380.0)
    ap.add_argument("--stock-mm", type=float, default=25.0)
    ap.add_argument("--max-cut-mm", type=float, default=18.0,
                    help="Max usable depth below stock top (Z0).")
    ap.add_argument("--vexag", type=float, default=1.0,
                    help="Multiply on top of the auto-fit vertical scale.")
    ap.add_argument("--rough-tool", type=float, default=3.0)
    ap.add_argument("--rough-stepdown", type=float, default=2.0)
    ap.add_argument("--finish-tool", type=float, default=3.0)
    ap.add_argument("--finish-stepover", type=float, default=0.4)
    ap.add_argument("--feed-xy", type=int, default=900)
    ap.add_argument("--feed-plunge", type=int, default=200)
    ap.add_argument("--feed-approach", type=int, default=1500)
    ap.add_argument("--safe-z", type=float, default=10.0)
    ap.add_argument("--spin-rpm", type=int, default=10000)
    ap.add_argument("--spinup-s", type=int, default=18)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache-dir", default=".dem-cache")
    ap.add_argument("--px-mm", type=float, default=1.0,
                    help="Heightmap pixel pitch in mm (lower = finer + slower).")
    ap.add_argument("--rough-z-tol", type=float, default=0.15)
    ap.add_argument("--finish-z-tol", type=float, default=0.05)
    args = ap.parse_args()

    cache = Path(args.cache_dir)
    cache.mkdir(parents=True, exist_ok=True)
    out_base = Path(args.out)
    out_base.parent.mkdir(parents=True, exist_ok=True)

    print(f"Bbox: lat [{args.lat_min},{args.lat_max}] lon [{args.lon_min},{args.lon_max}] z={args.zoom}")
    dem = build_dem(args.lat_min, args.lat_max, args.lon_min, args.lon_max, args.zoom, cache)
    print(f"DEM grid: {dem.shape}  elev range {dem.min():.1f} .. {dem.max():.1f} m")

    px_mm = args.px_mm
    if dem.shape[0] >= dem.shape[1]:
        rows = max(8, int(round(args.board_mm / px_mm)))
        cols = max(8, int(round(args.board_mm * dem.shape[1] / dem.shape[0] / px_mm)))
    else:
        cols = max(8, int(round(args.board_mm / px_mm)))
        rows = max(8, int(round(args.board_mm * dem.shape[0] / dem.shape[1] / px_mm)))
    print(f"Resampling DEM -> {rows} x {cols} px @ {px_mm} mm/px (~{cols * px_mm:.0f} x {rows * px_mm:.0f} mm)")
    height = resample(dem, cols, rows)

    h_min, h_max = float(height.min()), float(height.max())
    elev_range = max(1.0, h_max - h_min)
    auto_v_scale = args.max_cut_mm / elev_range
    v_scale = auto_v_scale * args.vexag

    depth = -((h_max - height) * v_scale)
    depth = np.clip(depth, -args.max_cut_mm, 0.0)
    print(f"Vertical: range {elev_range:.1f} m -> auto {auto_v_scale * 1000:.2f} mm/km, x{args.vexag} -> {v_scale * 1000:.2f} mm/km")
    print(f"Depth grid: {depth.min():.2f} .. {depth.max():.2f} mm")

    save_heightmap_png(depth, out_base.with_suffix(".heightmap.png"))

    rough_lines, tiers = emit_rough(
        depth, px_mm, out_base.with_suffix(".rough.nc"),
        tool_dia_mm=args.rough_tool, step_down_mm=args.rough_stepdown,
        safe_z_mm=args.safe_z, feed_xy=args.feed_xy, feed_plunge=args.feed_plunge,
        feed_approach=args.feed_approach, spin_rpm=args.spin_rpm, spinup_s=args.spinup_s,
        z_tol_mm=args.rough_z_tol,
    )
    finish_lines = emit_finish(
        depth, px_mm, out_base.with_suffix(".finish.nc"),
        tool_dia_mm=args.finish_tool, stepover_mm=args.finish_stepover,
        safe_z_mm=args.safe_z, feed_xy=args.feed_xy, feed_plunge=args.feed_plunge,
        spin_rpm=args.spin_rpm, spinup_s=args.spinup_s,
        z_tol_mm=args.finish_z_tol,
    )

    print(f"Wrote {out_base.with_suffix('.heightmap.png')}")
    print(f"Wrote {out_base.with_suffix('.rough.nc')}  lines={rough_lines} tiers={tiers}")
    print(f"Wrote {out_base.with_suffix('.finish.nc')} lines={finish_lines}")


if __name__ == "__main__":
    main()

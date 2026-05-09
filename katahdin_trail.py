"""Shared Appalachian Trail geometry for Katahdin preview + light engrave toolpaths.

Bbox and pixel grid must match New-TerrainNc.py runs for samples/katahdin*.
"""

from __future__ import annotations

# Must match New-TerrainNc.py Katahdin bbox
LAT_MIN, LAT_MAX = 45.86, 45.95
LON_MIN, LON_MAX = -68.99, -68.85

# Default resampled grid for current table-fit exaggerated Katahdin (356 x 330 mm @ 1 mm/px)
DEFAULT_COLS = 356
DEFAULT_ROWS = 330
DEFAULT_PX_MM = 1.0

# Approximate AT through Katahdin massif if OSM unavailable (lon, lat)
FALLBACK_TRAIL_WGS84: list[tuple[float, float]] = [
    (-68.9350, 45.8750),
    (-68.9280, 45.8880),
    (-68.9220, 45.8980),
    (-68.9195, 45.9040),
    (-68.9185, 45.9075),
    (-68.9190, 45.9095),
    (-68.9205, 45.9108),
    (-68.9225, 45.9120),
]


def fetch_trail_wgs84() -> list[tuple[float, float]]:
    import requests

    q = (
        "[out:json][timeout:120];"
        "("
        f'relation["name"="Appalachian Trail"]({LAT_MIN},{LON_MIN},{LAT_MAX},{LON_MAX});'
        ");"
        "way(r);"
        "out geom;"
    )
    try:
        r = requests.post(
            "https://overpass-api.de/api/interpreter",
            data={"data": q},
            timeout=95,
            headers={"User-Agent": "FoxAlienMasuter-KatahdinTrail/1.0"},
        )
        r.raise_for_status()
        data = r.json()
    except Exception:
        return list(FALLBACK_TRAIL_WGS84)

    pts: list[tuple[float, float]] = []
    for el in data.get("elements", []):
        geom = el.get("geometry")
        if not geom:
            continue
        for g in geom:
            pts.append((float(g["lon"]), float(g["lat"])))

    if len(pts) < 4:
        return list(FALLBACK_TRAIL_WGS84)

    out: list[tuple[float, float]] = []
    for p in pts:
        if not out or (abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6):
            out.append(p)
    return out


def lonlat_to_g54_xy(
    lon: float,
    lat: float,
    *,
    cols: int = DEFAULT_COLS,
    rows: int = DEFAULT_ROWS,
    px_mm: float = DEFAULT_PX_MM,
) -> tuple[float, float]:
    """Work coordinates matching New-TerrainNc emit (G54, mm, origin same as terrain file)."""
    x_mm = (lon - LON_MIN) / (LON_MAX - LON_MIN) * (cols - 1) * px_mm
    iy = (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * (rows - 1)
    y_mm = (rows - 1 - iy) * px_mm
    return float(x_mm), float(y_mm)


def trail_points_g54(
    *,
    cols: int = DEFAULT_COLS,
    rows: int = DEFAULT_ROWS,
    px_mm: float = DEFAULT_PX_MM,
) -> list[tuple[float, float]]:
    trail = fetch_trail_wgs84()
    out: list[tuple[float, float]] = []
    for lon, lat in trail:
        if not (LON_MIN <= lon <= LON_MAX and LAT_MIN <= lat <= LAT_MAX):
            continue
        x_mm, y_mm = lonlat_to_g54_xy(lon, lat, cols=cols, rows=rows, px_mm=px_mm)
        xmax = (cols - 1) * px_mm
        ymax = (rows - 1) * px_mm
        x_mm = max(0.0, min(xmax, x_mm))
        y_mm = max(0.0, min(ymax, y_mm))
        out.append((x_mm, y_mm))
    return out

# Swellbar

Del Mar surf in the menu bar: `● 3-4ft+` with the dot colored by rating. Click it for swell, wind, water temperature, weather, a tide chart and buoy readings, plus an **Open Surfline** button that shows Surfline's own Del Mar page inside the app.

Data refreshes every 10 minutes and whenever the Mac wakes.

## Data sources

| What | Source |
| --- | --- |
| Surf height | CDIP 153 Del Mar Nearshore buoy (NDBC 46266), Komar–Gaughan breaking height scaled to Surfline |
| Swell / windswell | 46266 spectral summary |
| Outer buoy | CDIP 100 Torrey Pines Outer (NDBC 46225) |
| Wind | Scripps Pier station LJPC1 (observed) |
| Tide | NOAA 9410230 La Jolla (Scripps Pier) predictions |
| Weather | NWS hourly forecast for Del Mar |

Surfline's data servers block non-browser requests, so the numbers come from these public feeds. `Surf.calibration` in `Sources/SurfMath.swift` was tuned against Surfline on 2026-10-18 (buoy 0.7 m at 17 s, Surfline 3–4 ft+). If Swellbar drifts from Surfline, adjust that one number. The rating is Swellbar's own estimate, not Surfline's forecaster call.

## Build

    ./build.sh --install

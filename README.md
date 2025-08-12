# Black Hole Sim (2D + 3D)

This Flutter + Flame sample contains:

- 2D null-geodesic integration with interactive pan/zoom and ray spawning.
- A simple 3D raytraced view that integrates in the ray plane and renders to an image buffer.

## Run

- Use the home screen buttons to launch either the 2D or 3D simulation.
- The 3D view renders once on load at the current widget size; increase device/window size for more pixels (slower).

Notes:

- The 3D cubemap is a placeholder gradient; replace `cubemapSample()` with real environment sampling if desired.

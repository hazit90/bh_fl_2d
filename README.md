# Black Hole Sim (2D + 3D)

This Flutter + Flame sample contains:

- 2D null-geodesic integration with interactive pan/zoom and ray spawning.
- A simple 3D raytraced view that integrates in the ray plane and renders to an image buffer.

## Run

- Use the home screen buttons to launch either the 2D or 3D simulation.
- The 3D view renders once on load at the current widget size; increase device/window size for more pixels (slower).

Notes:

- The 3D cubemap is a placeholder gradient; replace `cubemapSample()` with real environment sampling if desired.

## Native fast path (C++/Metal stub)

This app now includes a native rendering fast path callable via Dart FFI. On macOS/iOS, we export two C symbols:

- `bh_render_frame` returning RGBA bytes for a frame.
- `bh_free` to free the returned buffer.

For now, these are simple stubs that render a gradient, living in:

- `macos/Runner/bh_native.mm`
- `ios/Runner/bh_native.mm`

If Xcode does not automatically include these files in the build, open the respective Xcode project and add them to the Runner target sources.

The Dart wrapper is in `lib/game/native_renderer.dart`. The 3D renderer will try the native path first and fall back to the Dart isolate renderer if unavailable.

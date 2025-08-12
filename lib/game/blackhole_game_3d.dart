import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flame/game.dart' show FlameGame;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:flutter/foundation.dart' show compute;
import 'isolate_renderer.dart' as ir;

const double c = 299792458.0;
const double G = 6.67430e-11;

/// 3D Black hole simulation: raytracing per pixel
class BlackHoleSim3d extends FlameGame {
  final BlackHole3d blackHole;
  final Camera3d cam;
  final int imageWidth;
  final int imageHeight;
  late final ImageBuffer buffer;
  final double cubeHalfSize; // cube is centered at black hole, size in meters
  BackgroundSampler? _background;
  Uint8List? _bgRgba; // raw RGBA for isolate
  // Spin as a fraction of maximal Kerr (a/M in [0,1])
  final double spinFraction;
  // Viewer inclination from spin axis (0 = pole-on, pi/2 = edge-on)
  final double inclinationRad;

  BlackHoleSim3d({
    double? mass,
    required this.imageWidth,
    required this.imageHeight,
    required this.cubeHalfSize,
    this.spinFraction = 0.0,
    this.inclinationRad = 0.0,
  }) : blackHole = BlackHole3d(
         position: vm.Vector3.zero(),
         mass: mass ?? 8.54e36,
       ),
       cam = (() {
         // Place camera at distance R from origin and tilt by inclination about Y
         final R = 2.0e11;
         final ci = math.cos(inclinationRad);
         final si = math.sin(inclinationRad);
         // Rotate (-R,0,0) by Ry(incl) -> (-R*ci, 0, R*si)
         final pos = vm.Vector3(-R * ci, 0, R * si);
         // Up vector rotated similarly from (0,0,1)
         final up = vm.Vector3(si, 0, ci);
         return Camera3d(
           position: pos,
           target: vm.Vector3.zero(),
           up: up,
           fovY: math.pi / 2, // 90 deg
         );
       })() {
    buffer = ImageBuffer(imageWidth, imageHeight);
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Load background environment map once
    images.prefix = 'assets/'; // Make sure we load from assets/space.png
    await images.load('space.png');
    final img = images.fromCache('space.png');
    _background = await BackgroundSampler.fromImage(img, maxWidth: 512);
    _bgRgba = _background?.rgba;
    await renderFrame();
  }

  Future<void> renderFrame() async {
    // Prepare request payload for isolate
    Map<String, Object?>? bg;
    if (_background != null && _bgRgba != null) {
      bg = {
        'w': _background!.width,
        'h': _background!.height,
        'rgba': _bgRgba!,
      };
    }
    final req = <String, Object?>{
      'width': imageWidth,
      'height': imageHeight,
      'cubeHalfSize': cubeHalfSize,
      'rS': blackHole.rS,
      'dLambda': 1.0,
      'maxSteps': 4000,
      'camera': {
        'pos': [cam.position.x, cam.position.y, cam.position.z],
        'target': [cam.target.x, cam.target.y, cam.target.z],
        'up': [cam.up.x, cam.up.y, cam.up.z],
        'fovY': cam.fovY,
      },
      'bg': bg,
    };

    // Offload heavy render
    final rgba = await compute(ir.renderFrameIsolate, req);
    await buffer.rebuildImageFromRgba(rgba);
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    buffer.draw(canvas, size.x, size.y);
  }
}

/// Schwarzschild black hole in 3D
class BlackHole3d {
  BlackHole3d({required this.position, required this.mass})
    : rS = 2.0 * G * mass / (c * c);

  final vm.Vector3 position;
  final double mass;
  final double rS;
}

/// Simple pinhole camera
class Camera3d {
  final vm.Vector3 position;
  final vm.Vector3 target;
  final vm.Vector3 up;
  final double fovY;

  Camera3d({
    required this.position,
    required this.target,
    required this.up,
    required this.fovY,
  });

  /// Returns a ray from camera through pixel (x, y)
  Ray3d rayForPixel(int px, int py, int width, int height) {
    final aspect = width / height;
    final theta = fovY;
    final h = math.tan(theta / 2);
    final w = aspect * h;

    final forward = (target - position).normalized();
    final right = forward.cross(up).normalized();
    final trueUp = right.cross(forward);

    final nx = (2 * ((px + 0.5) / width) - 1) * w;
    final ny = (1 - 2 * ((py + 0.5) / height)) * h;

    final dir = (forward + right * nx + trueUp * ny).normalized();

    return Ray3d(position, dir);
  }
}

/// 3D ray
class Ray3d {
  vm.Vector3 origin;
  vm.Vector3 direction;
  Ray3d(this.origin, this.direction);
}

double _maxAbs3(vm.Vector3 v) {
  final ax = v.x.abs();
  final ay = v.y.abs();
  final az = v.z.abs();
  return ax > ay ? (ax > az ? ax : az) : (ay > az ? ay : az);
}

/// Integrate Schwarzschild geodesic in the plane of ray
ui.Color traceRay(
  Ray3d ray,
  BlackHole3d bh,
  double cubeHalfSize,
  BackgroundSampler? bg,
) {
  // Transform ray to BH-centric coordinates
  final origin = ray.origin - bh.position;
  final dir = ray.direction.normalized();

  // Project onto orbital plane with robust basis construction
  vm.Vector3 planeNormal = origin.cross(dir);
  if (planeNormal.length2 < 1e-24) {
    // If origin is nearly collinear with dir, pick an arbitrary stable normal
    planeNormal = dir.cross(vm.Vector3(0, 0, 1));
    if (planeNormal.length2 < 1e-24) {
      planeNormal = dir.cross(vm.Vector3(0, 1, 0));
      if (planeNormal.length2 < 1e-24) {
        planeNormal = dir.cross(vm.Vector3(1, 0, 0));
      }
    }
  }
  planeNormal.normalize();
  final xAxis = dir.normalized();
  final yAxis = planeNormal.cross(xAxis).normalized();

  // Components in plane
  double x = origin.dot(xAxis);
  double y = origin.dot(yAxis);

  // Initial radius and angle
  double r = math.sqrt(x * x + y * y);
  double phi = math.atan2(y, x);

  // Initial direction in plane
  double vx = dir.dot(xAxis) * c;
  double vy = dir.dot(yAxis) * c;

  // Schwarzschild null geodesic initial conditions (same as 2D)
  var dr = vx * math.cos(phi) + vy * math.sin(phi); // m/s
  var dphi = (-vx * math.sin(phi) + vy * math.cos(phi)) / r;

  // final L = r * r * dphi; // conserved angular momentum (unused in this variant)
  final f = 1.0 - bh.rS / r;
  final dtDLambda = math.sqrt((dr * dr) / (f * f) + (r * r * dphi * dphi) / f);
  final E = f * dtDLambda;

  // Integration
  final dLambda = 1.0;
  final maxSteps = 4000; // cap for performance
  for (int step = 0; step < maxSteps; step++) {
    // RK4 integration
    final y0 = [r, phi, dr, dphi];
    final k1 = List<double>.filled(4, 0);
    final k2 = List<double>.filled(4, 0);
    final k3 = List<double>.filled(4, 0);
    final k4 = List<double>.filled(4, 0);
    final tmp = List<double>.filled(4, 0);

    geodesicRHS(r, dr, dphi, E, bh.rS, k1);
    _addState(y0, k1, dLambda / 2.0, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, bh.rS, k2);

    _addState(y0, k2, dLambda / 2.0, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, bh.rS, k3);

    _addState(y0, k3, dLambda, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, bh.rS, k4);

    r += (dLambda / 6.0) * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]);
    phi += (dLambda / 6.0) * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]);
    dr += (dLambda / 6.0) * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]);
    dphi += (dLambda / 6.0) * (k1[3] + 2 * k2[3] + 2 * k3[3] + k4[3]);

    // Back to 3D Cartesian in plane
    final px = r * math.cos(phi);
    final py = r * math.sin(phi);
    final pos3d = bh.position + xAxis * px + yAxis * py;

    // Check for capture
    if (r <= bh.rS) {
      return const ui.Color(0xFF000000); // black
    }
    // Check for escaping cube
    if (_maxAbs3(pos3d - bh.position) > cubeHalfSize) {
      final escapeDir = (pos3d - bh.position).normalized();
      return cubemapSample(escapeDir, bg);
    }
  }
  // If it never escapes/captures, treat as background
  return const ui.Color(0xFF000000);
}

/// Schwarzschild null geodesic equations (planar)
void geodesicRHS(
  double r,
  double dr,
  double dphi,
  double E,
  double rS,
  List<double> out,
) {
  final f = 1.0 - rS / r;
  out[0] = dr;
  out[1] = dphi;
  final dtDLambda = E / f;
  out[2] =
      -(rS / (2 * r * r)) * f * (dtDLambda * dtDLambda) +
      (rS / (2 * r * r * f)) * (dr * dr) +
      (r - rS) * (dphi * dphi);
  out[3] = -2.0 * dr * dphi / r;
}

void _addState(
  List<double> a,
  List<double> b,
  double factor,
  List<double> out,
) {
  for (var i = 0; i < 4; i++) {
    out[i] = a[i] + b[i] * factor;
  }
}

/// Simple cubemap sampling: gradient by direction
ui.Color cubemapSample(vm.Vector3 dir, BackgroundSampler? bg) {
  if (bg != null) {
    return bg.sampleDir(dir);
  }
  // Fallback gradient
  final r = ((dir.x + 1) * 127).clamp(0, 255).toInt();
  final g = ((dir.y + 1) * 127).clamp(0, 255).toInt();
  final b = ((dir.z + 1) * 127).clamp(0, 255).toInt();
  return ui.Color.fromARGB(255, r, g, b);
}

class BackgroundSampler {
  final int width;
  final int height;
  final Uint8List rgba; // RGBA8888 row-major

  BackgroundSampler(this.width, this.height, this.rgba);

  static Future<BackgroundSampler> fromImage(
    ui.Image image, {
    int? maxWidth,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      // Should not happen; fallback to 1x1 black
      return BackgroundSampler(1, 1, Uint8List.fromList([0, 0, 0, 255]));
    }
    var w = image.width;
    var h = image.height;
    var data = byteData.buffer.asUint8List();
    if (maxWidth != null && w > maxWidth) {
      final scale = maxWidth / w;
      final newW = maxWidth;
      final newH = (h * scale).round().clamp(1, h);
      final resized = Uint8List(newW * newH * 4);
      for (int yy = 0; yy < newH; yy++) {
        final srcY = (yy / scale).floor().clamp(0, h - 1);
        for (int xx = 0; xx < newW; xx++) {
          final srcX = (xx / scale).floor().clamp(0, w - 1);
          final si = (srcY * w + srcX) * 4;
          final di = (yy * newW + xx) * 4;
          resized[di] = data[si];
          resized[di + 1] = data[si + 1];
          resized[di + 2] = data[si + 2];
          resized[di + 3] = data[si + 3];
        }
      }
      w = newW;
      h = newH;
      data = resized;
    }
    return BackgroundSampler(w, h, data);
  }

  ui.Color sampleDir(vm.Vector3 dir) {
    final d = dir.normalized();
    final lon = math.atan2(d.y, d.x); // -pi..pi
    final lat = math.asin(d.z); // -pi/2..pi/2 (z is up)
    double u = (lon + math.pi) / (2 * math.pi);
    double v = (lat + math.pi / 2) / math.pi;
    // Convert to pixel coords (v flipped so north pole at top)
    int x = (u * width).floor().clamp(0, width - 1);
    int y = ((1 - v) * height).floor().clamp(0, height - 1);
    final idx = (y * width + x) * 4;
    final r = rgba[idx];
    final g = rgba[idx + 1];
    final b = rgba[idx + 2];
    final a = rgba[idx + 3];
    return ui.Color.fromARGB(a, r, g, b);
  }
}

/// Simple pixel buffer backed by a cached ui.Image
class ImageBuffer {
  final int width, height;
  final List<int> pixels; // ARGB32, Color.value
  ui.Image? _image;

  ImageBuffer(this.width, this.height)
    : pixels = List.filled(width * height, 0xFF000000);

  void setPixel(int x, int y, ui.Color color) {
    final a = (color.a * 255.0).round() & 0xff;
    final r = (color.r * 255.0).round() & 0xff;
    final g = (color.g * 255.0).round() & 0xff;
    final b = (color.b * 255.0).round() & 0xff;
    final argb = (a << 24) | (r << 16) | (g << 8) | b;
    pixels[y * width + x] = argb;
  }

  void draw(ui.Canvas canvas, double widthPx, double heightPx) {
    final img = _image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Rect.fromLTWH(0, 0, widthPx, heightPx),
        ui.Paint(),
      );
    }
  }

  Future<void> rebuildImage() async {
    // Convert ARGB -> RGBA for decodeImageFromPixels
    final data = Uint8List(width * height * 4);
    int di = 0;
    for (int i = 0; i < pixels.length; i++) {
      final argb = pixels[i];
      final a = (argb >> 24) & 0xFF;
      final r = (argb >> 16) & 0xFF;
      final g = (argb >> 8) & 0xFF;
      final b = argb & 0xFF;
      data[di++] = r;
      data[di++] = g;
      data[di++] = b;
      data[di++] = a;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      data,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
      rowBytes: width * 4,
    );
    _image = await completer.future;
  }

  Future<void> rebuildImageFromRgba(Uint8List rgba) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
      rowBytes: width * 4,
    );
    _image = await completer.future;
  }
}

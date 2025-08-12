import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';

// Physical constants
const double c = 299792458.0; // m/s
const double G = 6.67430e-11; // m^3 kg^-1 s^-2

class BlackHoleGame extends FlameGame
    with PanDetector, ScaleDetector, ScrollDetector, TapDetector {
  BlackHoleGame({double? mass})
    : blackHole = BlackHole(
        position: Vector2.zero(),
        mass: mass ?? 8.54e36, // Sagittarius A*
      );

  // Viewport in meters (half-extents, like the original glOrtho)
  final double _baseWidthMeters = 1.0e11;
  final double _baseHeightMeters = 7.5e10;

  // Navigation
  double offsetX = 0.0; // meters
  double offsetY = 0.0; // meters
  double zoom = 1.0; // >1 zooms in

  final BlackHole blackHole;
  final List<Ray> rays = [];

  // Simulation controls
  // Affine parameter step (dimensionless here, chosen for stability)
  double dLambda = 1.0;
  int stepsPerFrame = 2;
  int maxTrail = 2000;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Seed a sample ray similar to the C++ example
    // Position (meters) and direction (m/s components)
    final pos = Vector2(-1.0e11, 3.2760630272e10);
    final dir = Vector2(c, 0.0);
    rays.add(Ray.fromCartesian(pos, dir, blackHole.rS));

    // Seed a small fan of rays for a nicer visual
    for (int i = -4; i <= 4; i++) {
      if (i == 0) continue;
      final y = 3.2760630272e10 + i * 1.2e9;
      rays.add(
        Ray.fromCartesian(Vector2(-1.05e11, y), Vector2(c, 0.0), blackHole.rS),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    for (int s = 0; s < stepsPerFrame; s++) {
      for (final ray in rays) {
        ray.step(dLambda, blackHole.rS);
        if (ray.trail.length > maxTrail) {
          // Keep memory bounded
          ray.trail.removeRange(0, ray.trail.length - maxTrail);
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    // Set up a world->screen transform mimicking glOrtho(left,right,bottom,top)
    final widthMeters = _baseWidthMeters / zoom;
    final heightMeters = _baseHeightMeters / zoom;

    canvas.save();
    // Move origin to center of screen
    canvas.translate(size.x / 2, size.y / 2);
    // Scale world meters to pixels and flip Y up
    canvas.scale(size.x / (2 * widthMeters), -size.y / (2 * heightMeters));
    // Center the camera at (offsetX, offsetY)
    canvas.translate(-offsetX, -offsetY);

    // Clear background (space black)
    final bg = Paint()..color = const Color(0xFF000000);
    // Draw a rect covering the visible world bounds
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(offsetX, offsetY),
        width: 2 * widthMeters,
        height: 2 * heightMeters,
      ),
      bg,
    );

    // Draw black hole (red disc of radius r_s)
    blackHole.render(canvas);

    // Draw rays (point + fading trail)
    _renderRays(canvas);

    canvas.restore();
  }

  void _renderRays(Canvas canvas) {
    // Points for current positions
    final pointPaint = Paint()
      ..color = const Color(0xFFFF0000)
      ..style = PaintingStyle.fill;
    const pointRadius =
        2.5e9; // meters represented as a tiny dot in world units

    for (final ray in rays) {
      // Current position
      canvas.drawCircle(Offset(ray.x, ray.y), pointRadius, pointPaint);
    }

    // Trails with fading alpha per segment
    for (final ray in rays) {
      final trail = ray.trail;
      if (trail.length < 2) continue;

      final n = trail.length;
      for (int i = 0; i < n - 1; i++) {
        final t = i / (n - 1);
        final alpha = (t * 0xFF).clamp(12, 255).toInt(); // 5%-100%
        final paint = Paint()
          ..color = Color.fromARGB(alpha, 255, 255, 255)
          ..strokeWidth =
              2.0e9 // meters
          ..style = PaintingStyle.stroke;
        canvas.drawLine(trail[i], trail[i + 1], paint);
      }
    }
  }

  // Convert a screen-space position (pixels) to world meters
  Offset _screenToWorld(Vector2 screen) {
    final widthMeters = _baseWidthMeters / zoom;
    final heightMeters = _baseHeightMeters / zoom;
    final sx = screen.x;
    final sy = screen.y;
    final wx = ((sx - size.x / 2) * (2 * widthMeters) / size.x) + offsetX;
    final wy = (-(sy - size.y / 2) * (2 * heightMeters) / size.y) + offsetY;
    return Offset(wx, wy);
  }

  @override
  void onTapDown(TapDownInfo info) {
    final world = _screenToWorld(info.eventPosition.global);
    // Spawn at pointer, move right
    final startPos = Vector2(world.dx, world.dy);
    final dir = Vector2(c, 0);
    rays.add(Ray.fromCartesian(startPos, dir, blackHole.rS));
  }

  // Input: panning via drag, zoom via pinch or scroll
  @override
  void onPanUpdate(DragUpdateInfo info) {
    // Convert screen delta to world meters based on current scale
    final widthMeters = _baseWidthMeters / zoom;
    final heightMeters = _baseHeightMeters / zoom;
    final dxWorld = info.delta.global.x * (2 * widthMeters) / size.x;
    final dyWorld =
        -info.delta.global.y * (2 * heightMeters) / size.y; // flip y
    offsetX -= dxWorld;
    offsetY -= dyWorld;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    // Use average of X/Y scale as a scalar zoom factor
    final scaleVec = info.scale.global; // Vector2
    final s = (scaleVec.x + scaleVec.y) / 2;
    if (s != 1.0) {
      zoom = (zoom * s).clamp(0.05, 40.0);
      // Keep black hole centered when zooming
      offsetX = blackHole.position.x;
      offsetY = blackHole.position.y;
    }
  }

  @override
  void onScroll(PointerScrollInfo info) {
    final scroll = info.scrollDelta.global; // Vector2
    if (scroll.y != 0) {
      final factor = scroll.y > 0 ? (1 / 1.1) : 1.1;
      zoom = (zoom * factor).clamp(0.05, 40.0);
      // Keep black hole centered when zooming
      offsetX = blackHole.position.x;
      offsetY = blackHole.position.y;
    }
  }
}

class BlackHole {
  BlackHole({required this.position, required this.mass})
    : rS = 2.0 * G * mass / (c * c);

  final Vector2 position;
  final double mass; // kg
  final double rS; // Schwarzschild radius (m)

  void render(Canvas canvas) {
    // Draw a red filled circle at origin with radius r_s
    final paint = Paint()
      ..color = const Color(0xFFFF0000)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(position.x, position.y), rS, paint);
  }
}

class Ray {
  // Cartesian (meters)
  double x;
  double y;

  // Polar
  double r;
  double phi;
  double dr;
  double dphi;

  // Conserved quantities
  double E;
  double L;

  // Trail in world meters
  final List<Offset> trail;

  Ray._(this.x, this.y, this.r, this.phi, this.dr, this.dphi, this.E, this.L)
    : trail = [Offset(x, y)];

  factory Ray.fromCartesian(Vector2 pos, Vector2 dir, double rS) {
    final x = pos.x.toDouble();
    final y = pos.y.toDouble();
    final r = math.sqrt(x * x + y * y);
    final phi = math.atan2(y, x);
    // Convert Cartesian velocity components to polar
    final vx = dir.x.toDouble();
    final vy = dir.y.toDouble();

    var dr = vx * math.cos(phi) + vy * math.sin(phi); // m/s
    var dphi = (-vx * math.sin(phi) + vy * math.cos(phi)) / r;

    // Conserved quantities for null geodesic
    final L = r * r * dphi;
    final f = 1.0 - rS / r;
    final dtDLambda = math.sqrt(
      (dr * dr) / (f * f) + (r * r * dphi * dphi) / f,
    );
    final E = f * dtDLambda;

    return Ray._(x, y, r, phi, dr, dphi, E, L);
  }

  void step(double dLambda, double rS) {
    if (r <= rS) return; // stop inside event horizon

    final y0 = [r, phi, dr, dphi];
    final k1 = List<double>.filled(4, 0);
    final k2 = List<double>.filled(4, 0);
    final k3 = List<double>.filled(4, 0);
    final k4 = List<double>.filled(4, 0);
    final tmp = List<double>.filled(4, 0);

    geodesicRHS(this, k1, rS);
    _addState(y0, k1, dLambda / 2.0, tmp);
    final r2 = cloneWith(tmp);
    geodesicRHS(r2, k2, rS);

    _addState(y0, k2, dLambda / 2.0, tmp);
    final r3 = cloneWith(tmp);
    geodesicRHS(r3, k3, rS);

    _addState(y0, k3, dLambda, tmp);
    final r4 = cloneWith(tmp);
    geodesicRHS(r4, k4, rS);

    r += (dLambda / 6.0) * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]);
    phi += (dLambda / 6.0) * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]);
    dr += (dLambda / 6.0) * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]);
    dphi += (dLambda / 6.0) * (k1[3] + 2 * k2[3] + 2 * k3[3] + k4[3]);

    // Back to Cartesian
    x = r * math.cos(phi);
    y = r * math.sin(phi);

    trail.add(Offset(x, y));
  }

  Ray cloneWith(List<double> s) {
    final rr = Ray._(x, y, s[0], s[1], s[2], s[3], E, L);
    return rr;
  }
}

void geodesicRHS(Ray ray, List<double> out, double rS) {
  final r = ray.r;
  final dr = ray.dr;
  final dphi = ray.dphi;
  final E = ray.E;

  final f = 1.0 - rS / r;

  // dr/dλ = dr
  out[0] = dr;
  // dφ/dλ = dphi
  out[1] = dphi;

  // d²r/dλ² from Schwarzschild null geodesic
  final dtDLambda = E / f;
  out[2] =
      -(rS / (2 * r * r)) * f * (dtDLambda * dtDLambda) +
      (rS / (2 * r * r * f)) * (dr * dr) +
      (r - rS) * (dphi * dphi);

  // d²φ/dλ²
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

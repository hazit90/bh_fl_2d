import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math_64.dart' as vm;

// Constants
const double c = 299792458.0;

// Entry point for compute() isolate: expects a Map request, returns RGBA bytes
Uint8List renderFrameIsolate(Map<String, Object?> req) {
  final width = req['width'] as int;
  final height = req['height'] as int;
  final cubeHalfSize = (req['cubeHalfSize'] as num).toDouble();
  final rS = (req['rS'] as num).toDouble();
  final dLambda = (req['dLambda'] as num).toDouble();
  final maxSteps = req['maxSteps'] as int;

  final cam = req['camera'] as Map<String, Object?>;
  vm.Vector3 _v(List l) => vm.Vector3(
    (l[0] as num).toDouble(),
    (l[1] as num).toDouble(),
    (l[2] as num).toDouble(),
  );
  final camPos = _v(cam['pos'] as List);
  final camTarget = _v(cam['target'] as List);
  final camUp = _v(cam['up'] as List);
  final fovY = (cam['fovY'] as num).toDouble();

  Map<String, Object?>? bg = req['bg'] as Map<String, Object?>?;
  final bgW = bg != null ? bg['w'] as int : 0;
  final bgH = bg != null ? bg['h'] as int : 0;
  final bgData = bg != null ? (bg['rgba'] as Uint8List?) : null;

  // Prepare camera basis
  final aspect = width / height;
  final theta = fovY;
  final h = math.tan(theta / 2);
  final w = aspect * h;

  final forward = (camTarget - camPos).normalized();
  final right = forward.cross(camUp).normalized();
  final trueUp = right.cross(forward);

  // Output buffer
  final rgba = Uint8List(width * height * 4);

  // Per-pixel ray
  for (int py = 0; py < height; py++) {
    for (int px = 0; px < width; px++) {
      final nx = (2 * ((px + 0.5) / width) - 1) * w;
      final ny = (1 - 2 * ((py + 0.5) / height)) * h;
      final dir = (forward + right * nx + trueUp * ny).normalized();
      final rayOrigin = camPos;

      // Trace and write RGBA
      final color = _traceRayRGBA(
        rayOrigin,
        dir,
        rS,
        cubeHalfSize,
        bgW,
        bgH,
        bgData,
        maxSteps,
        dLambda,
      );
      final i = (py * width + px) * 4;
      rgba[i] = color[0];
      rgba[i + 1] = color[1];
      rgba[i + 2] = color[2];
      rgba[i + 3] = color[3];
    }
  }

  return rgba;
}

List<int> _traceRayRGBA(
  vm.Vector3 originWorld,
  vm.Vector3 dirWorld,
  double rS,
  double cubeHalfSize,
  int bgW,
  int bgH,
  Uint8List? bg,
  int maxSteps,
  double dLambda,
) {
  final origin = originWorld;
  final dir = dirWorld.normalized();

  vm.Vector3 planeNormal = origin.cross(dir);
  if (planeNormal.length2 < 1e-24) {
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

  double x = origin.dot(xAxis);
  double y = origin.dot(yAxis);
  double r = math.sqrt(x * x + y * y);
  double phi = math.atan2(y, x);

  double vx = dir.dot(xAxis) * c;
  double vy = dir.dot(yAxis) * c;
  double dr = vx * math.cos(phi) + vy * math.sin(phi);
  double dphi =
      (-vx * math.sin(phi) + vy * math.cos(phi)) / (r == 0 ? 1e-12 : r);

  final f0 = 1.0 - rS / (r == 0 ? 1e-12 : r);
  final dtDLambda = math.sqrt(
    (dr * dr) / (f0 * f0) + (r * r * dphi * dphi) / f0,
  );
  final E = f0 * dtDLambda;

  for (int step = 0; step < maxSteps; step++) {
    final y0 = [r, phi, dr, dphi];
    final k1 = List<double>.filled(4, 0);
    final k2 = List<double>.filled(4, 0);
    final k3 = List<double>.filled(4, 0);
    final k4 = List<double>.filled(4, 0);
    final tmp = List<double>.filled(4, 0);

    _geodesicRHS(r, dr, dphi, E, rS, k1);
    _addState(y0, k1, dLambda / 2.0, tmp);
    _geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k2);
    _addState(y0, k2, dLambda / 2.0, tmp);
    _geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k3);
    _addState(y0, k3, dLambda, tmp);
    _geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k4);

    r += (dLambda / 6.0) * (k1[0] + 2 * k2[0] + 2 * k3[0] + k4[0]);
    phi += (dLambda / 6.0) * (k1[1] + 2 * k2[1] + 2 * k3[1] + k4[1]);
    dr += (dLambda / 6.0) * (k1[2] + 2 * k2[2] + 2 * k3[2] + k4[2]);
    dphi += (dLambda / 6.0) * (k1[3] + 2 * k2[3] + 2 * k3[3] + k4[3]);

    final px = r * math.cos(phi);
    final py = r * math.sin(phi);
    final pos3d = xAxis * px + yAxis * py;

    if (r <= rS) {
      return [0, 0, 0, 255];
    }
    if (_maxAbs3(pos3d) > cubeHalfSize) {
      final escapeDir = pos3d.normalized();
      return _sampleBg(escapeDir, bgW, bgH, bg);
    }
  }
  return [0, 0, 0, 255];
}

void _geodesicRHS(
  double r,
  double dr,
  double dphi,
  double E,
  double rS,
  List<double> out,
) {
  final f = 1.0 - rS / (r == 0 ? 1e-12 : r);
  out[0] = dr;
  out[1] = dphi;
  final dtDLambda = E / (f == 0 ? 1e-12 : f);
  out[2] =
      -(rS / (2 * r * r)) * f * (dtDLambda * dtDLambda) +
      (rS / (2 * r * r * (f == 0 ? 1e-12 : f))) * (dr * dr) +
      (r - rS) * (dphi * dphi);
  out[3] = -2.0 * dr * dphi / (r == 0 ? 1e-12 : r);
}

void _addState(List<double> a, List<double> b, double f, List<double> out) {
  for (var i = 0; i < 4; i++) {
    out[i] = a[i] + b[i] * f;
  }
}

double _maxAbs3(vm.Vector3 v) {
  final ax = v.x.abs();
  final ay = v.y.abs();
  final az = v.z.abs();
  return ax > ay ? (ax > az ? ax : az) : (ay > az ? ay : az);
}

List<int> _sampleBg(vm.Vector3 dir, int w, int h, Uint8List? data) {
  if (data == null || w <= 0 || h <= 0) return [0, 0, 0, 255];
  final d = dir.normalized();
  final lon = math.atan2(d.y, d.x);
  final lat = math.asin(d.z);
  double u = (lon + math.pi) / (2 * math.pi);
  double v = (lat + math.pi / 2) / math.pi;
  int x = (u * w).floor().clamp(0, w - 1);
  int y = ((1 - v) * h).floor().clamp(0, h - 1);
  final idx = (y * w + x) * 4;
  return [data[idx], data[idx + 1], data[idx + 2], data[idx + 3]];
}

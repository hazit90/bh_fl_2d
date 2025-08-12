import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class NativeTexture {
  static const _channel = MethodChannel('bh.native/tex');

  static Future<int?> create(int width, int height) async {
    if (!Platform.isMacOS) return null;
    final id = await _channel.invokeMethod<int>('create', {
      'width': width,
      'height': height,
    });
    return id;
  }

  static Future<void> render({
    required List<double> pos,
    required List<double> target,
    required List<double> up,
    required double fovY,
    required double rS,
    required double cubeHalfSize,
    required int maxSteps,
    required double dLambda,
    required int width,
    required int height,
  }) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('render', {
      'pos': pos,
      'target': target,
      'up': up,
      'fovY': fovY,
      'rS': rS,
      'cubeHalfSize': cubeHalfSize,
      'maxSteps': maxSteps,
      'dLambda': dLambda,
      'width': width,
      'height': height,
    });
  }

  static Future<void> dispose() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('dispose');
  }

  static Future<void> setBackground({required List<int> rgba, required int width, required int height}) async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod('setBackground', {
      'rgba': Uint8List.fromList(rgba),
      'width': width,
      'height': height,
    });
  }
}

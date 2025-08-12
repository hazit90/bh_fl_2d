import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkgffi;

// C signatures
typedef _BhRenderFrameC =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      ffi.Double,
      ffi.Double,
      ffi.Double,
      ffi.Int32,
      ffi.Double,
      ffi.Pointer<ffi.Uint8>,
      ffi.Int32,
      ffi.Int32,
    );
typedef _BhFreeC = ffi.Void Function(ffi.Pointer<ffi.Void>);

// Dart signatures
typedef _BhRenderFrameDart =
    ffi.Pointer<ffi.Uint8> Function(
      int,
      int,
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      ffi.Pointer<ffi.Double>,
      double,
      double,
      double,
      int,
      double,
      ffi.Pointer<ffi.Uint8>,
      int,
      int,
    );
typedef _BhFreeDart = void Function(ffi.Pointer<ffi.Void>);

class NativeRenderer {
  static NativeRenderer? _instance;
  final _BhRenderFrameDart _render;
  final _BhFreeDart _free;

  NativeRenderer._(this._render, this._free);

  static NativeRenderer? instance() {
    if (_instance != null) return _instance;
    try {
      final lib = _openLibrary();
      final render = lib.lookupFunction<_BhRenderFrameC, _BhRenderFrameDart>(
        'bh_render_frame',
      );
      final freeFn = lib.lookupFunction<_BhFreeC, _BhFreeDart>('bh_free');
      _instance = NativeRenderer._(render, freeFn);
      return _instance;
    } catch (_) {
      return null;
    }
  }

  static ffi.DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      // Flutter macOS bundles the app; load from process if linked, else fallback to path
      try {
        return ffi.DynamicLibrary.process();
      } catch (_) {
        // This path may vary; keep as last resort
        return ffi.DynamicLibrary.open('libbh_native.dylib');
      }
    } else if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    } else if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libbh_native.so');
    } else if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('bh_native.dll');
    } else if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libbh_native.so');
    }
    throw UnsupportedError('Platform not supported for native renderer');
  }

  Uint8List render({
    required int width,
    required int height,
    required Float64List camPos,
    required Float64List camTarget,
    required Float64List camUp,
    required double fovY,
    required double rS,
    required double cubeHalfSize,
    required int maxSteps,
    required double dLambda,
    Uint8List? bgRgba,
    int bgW = 0,
    int bgH = 0,
  }) {
    assert(camPos.length == 3 && camTarget.length == 3 && camUp.length == 3);

    final camPosPtr = pkgffi.malloc<ffi.Double>(3);
    final camTargetPtr = pkgffi.malloc<ffi.Double>(3);
    final camUpPtr = pkgffi.malloc<ffi.Double>(3);
    for (var i = 0; i < 3; i++) {
      camPosPtr[i] = camPos[i];
      camTargetPtr[i] = camTarget[i];
      camUpPtr[i] = camUp[i];
    }
    final bgPtr = (bgRgba != null && bgRgba.isNotEmpty)
        ? pkgffi.malloc<ffi.Uint8>(bgRgba.length)
        : ffi.Pointer<ffi.Uint8>.fromAddress(0);
    if (bgRgba != null && bgRgba.isNotEmpty) {
      final bytes = bgPtr.asTypedList(bgRgba.length);
      bytes.setAll(0, bgRgba);
    }

    final outPtr = _render(
      width,
      height,
      camPosPtr,
      camTargetPtr,
      camUpPtr,
      fovY,
      rS,
      cubeHalfSize,
      maxSteps,
      dLambda,
      bgPtr,
      bgW,
      bgH,
    );

    // Each pixel is RGBA
    final length = width * height * 4;
    final out = outPtr.asTypedList(length);
    final result = Uint8List.fromList(out);

    // Free native allocations
    _free(outPtr.cast());
    pkgffi.malloc.free(camPosPtr);
    pkgffi.malloc.free(camTargetPtr);
    pkgffi.malloc.free(camUpPtr);
    if (bgPtr.address != 0) pkgffi.malloc.free(bgPtr);

    return result;
  }
}

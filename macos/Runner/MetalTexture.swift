import Foundation
import Metal
import FlutterMacOS
import CoreVideo
import IOSurface
import simd

struct CameraUniforms {
  var camPos: SIMD3<Float>
  var forward: SIMD3<Float>
  var right: SIMD3<Float>
  var up: SIMD3<Float>
  var w: Float
  var hhalf: Float
  var rS: Float
  var cubeHalfSize: Float
  var maxSteps: Int32
  var dLambda: Float
  var width: Int32
  var height: Int32
  var bgW: Int32
  var bgH: Int32
  var hasBg: Int32
}

class MetalTexture: NSObject, FlutterTexture {
  private let device: MTLDevice
  private let queue: MTLCommandQueue
  private let pso: MTLComputePipelineState
  private var pixelBuffer: CVPixelBuffer?
  private var texture: MTLTexture?
  private var bgTexture: MTLTexture?
  private var bgSampler: MTLSamplerState?
  private var width: Int = 0
  private var height: Int = 0

  init?(device: MTLDevice) {
    self.device = device
    guard let queue = device.makeCommandQueue() else { return nil }
    self.queue = queue
  guard let lib = try? device.makeDefaultLibrary(bundle: .main),
          let fn = lib.makeFunction(name: "bh_kernel_tex"),
          let pso = try? device.makeComputePipelineState(function: fn) else { return nil }
    self.pso = pso
  // Default sampler
  let sd = MTLSamplerDescriptor()
  sd.minFilter = .linear
  sd.magFilter = .linear
  self.bgSampler = device.makeSamplerState(descriptor: sd)
  }

  func resize(width: Int, height: Int) -> Bool {
    if width == self.width && height == self.height, pixelBuffer != nil, texture != nil { return true }
    // Release old resources
    pixelBuffer = nil
    texture = nil
    var pbOut: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    let res = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pbOut)
    guard res == kCVReturnSuccess, let pb = pbOut else { return false }
  let io = CVPixelBufferGetIOSurface(pb)!.takeUnretainedValue()
  let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
  td.usage = [.shaderWrite, .shaderRead]
    guard let tex = device.makeTexture(descriptor: td, iosurface: io, plane: 0) else {
      return false
    }
    self.pixelBuffer = pb
    self.texture = tex
    self.width = width
    self.height = height
    return true
  }

  func render(pos: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>, fovY: Float, rS: Float, cubeHalfSize: Float, maxSteps: Int32, dLambda: Float) {
    guard let tex = texture else { return }

    let forward = simd_normalize(target - pos)
    let right = simd_normalize(simd_cross(forward, up))
    let trueUp = simd_cross(right, forward)

    let aspect = Float(width) / Float(height)
    let hhalf = tan(fovY * 0.5)
    let w = aspect * hhalf

    var U = CameraUniforms(
      camPos: pos,
      forward: forward,
      right: right,
      up: trueUp,
      w: w,
      hhalf: hhalf,
      rS: rS,
      cubeHalfSize: cubeHalfSize,
      maxSteps: maxSteps,
      dLambda: dLambda,
      width: Int32(width),
      height: Int32(height),
      bgW: 0, bgH: 0, hasBg: 0
    )

  guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return }
    enc.setComputePipelineState(pso)
  enc.setTexture(tex, index: 0)
  if let bg = bgTexture, let samp = bgSampler { enc.setTexture(bg, index: 1); enc.setSamplerState(samp, index: 0) }
    let ubo = device.makeBuffer(bytes: &U, length: MemoryLayout<CameraUniforms>.size, options: .storageModeShared)
    enc.setBuffer(ubo, offset: 0, index: 0)

  let grid = MTLSize(width: width, height: height, depth: 1)
  let tw = pso.threadExecutionWidth
  let th = max(1, pso.maxTotalThreadsPerThreadgroup / tw)
  let tg = MTLSize(width: tw, height: th, depth: 1)
    enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
    enc.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()
  }

  func setBackground(_ rgba: [UInt8], width: Int, height: Int) {
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    td.usage = [.shaderRead]
    guard let tex = device.makeTexture(descriptor: td) else { return }
    let bytesPerRow = width * 4
    tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: rgba, bytesPerRow: bytesPerRow)
    bgTexture = tex
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pb = pixelBuffer else { return nil }
    return Unmanaged.passRetained(pb)
  }
}

// AppDelegate hook for channel
extension AppDelegate {
  func setupBHTextureChannel(_ registrar: FlutterPluginRegistrar) {
  let channel = FlutterMethodChannel(name: "bh.native/tex", binaryMessenger: registrar.messenger)
  let textures = registrar.textures

    var metalTex: MetalTexture?
    var texId: Int64 = -1

  channel.setMethodCallHandler { call, result in
      switch call.method {
      case "create":
        guard let device = MTLCreateSystemDefaultDevice(), let args = call.arguments as? [String: Any], let w = args["width"] as? Int, let h = args["height"] as? Int, let tex = MetalTexture(device: device) else {
          result(FlutterError(code: "no_device", message: "Metal unavailable", details: nil))
          return
        }
        guard tex.resize(width: w, height: h) else {
          result(FlutterError(code: "resize_failed", message: "Could not allocate pixel buffer", details: nil))
          return
        }
        metalTex = tex
        texId = textures.register(tex)
        result(texId)
      case "setBackground":
        guard let args = call.arguments as? [String: Any], let w = args["width"] as? Int, let h = args["height"] as? Int, let data = args["rgba"] as? FlutterStandardTypedData, let tex = metalTex else {
          result(FlutterError(code: "bad_args", message: "Missing bg args", details: nil)); return
        }
        let bytes = [UInt8](data.data)
        tex.setBackground(bytes, width: w, height: h)
        result(nil)
      case "render":
        guard let tex = metalTex, let args = call.arguments as? [String: Any] else { result(FlutterError(code: "no_tex", message: "Texture not created", details: nil)); return }
        guard let pos = args["pos"] as? [Double], let tgt = args["target"] as? [Double], let up = args["up"] as? [Double], let fovY = args["fovY"] as? Double, let rS = args["rS"] as? Double, let cube = args["cubeHalfSize"] as? Double, let maxSteps = args["maxSteps"] as? Int, let dLambda = args["dLambda"] as? Double, let w = args["width"] as? Int, let h = args["height"] as? Int else {
          result(FlutterError(code: "bad_args", message: "Missing args", details: nil)); return
        }
        _ = tex.resize(width: w, height: h)
        tex.render(pos: SIMD3<Float>(Float(pos[0]), Float(pos[1]), Float(pos[2])),
                   target: SIMD3<Float>(Float(tgt[0]), Float(tgt[1]), Float(tgt[2])),
                   up: SIMD3<Float>(Float(up[0]), Float(up[1]), Float(up[2])),
                   fovY: Float(fovY), rS: Float(rS), cubeHalfSize: Float(cube), maxSteps: Int32(maxSteps), dLambda: Float(dLambda))
        textures.textureFrameAvailable(texId)
        result(nil)
      case "dispose":
        if texId >= 0 { textures.unregisterTexture(texId) }
        metalTex = nil
        texId = -1
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

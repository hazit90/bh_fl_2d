// Objective-C++ implementation of the ray tracer matching isolate_renderer.dart
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>

namespace bh {
static constexpr double c = 299792458.0;

struct Vec3 {
  double x, y, z;
  Vec3() : x(0), y(0), z(0) {}
  Vec3(double X, double Y, double Z) : x(X), y(Y), z(Z) {}
  inline Vec3 operator+(const Vec3& o) const { return Vec3(x+o.x, y+o.y, z+o.z); }
  inline Vec3 operator-(const Vec3& o) const { return Vec3(x-o.x, y-o.y, z-o.z); }
  inline Vec3 operator*(double s) const { return Vec3(x*s, y*s, z*s); }
  inline Vec3& operator+=(const Vec3& o) { x+=o.x; y+=o.y; z+=o.z; return *this; }
  inline double dot(const Vec3& o) const { return x*o.x + y*o.y + z*o.z; }
  inline Vec3 cross(const Vec3& o) const {
    return Vec3(y*o.z - z*o.y, z*o.x - x*o.z, x*o.y - y*o.x);
  }
  inline double len2() const { return x*x + y*y + z*z; }
  inline double len() const { return sqrt(len2()); }
  inline Vec3 normalized() const {
    double L = len();
    if (L <= 0.0) return Vec3(0,0,0);
    double inv = 1.0 / L;
    return Vec3(x*inv, y*inv, z*inv);
  }
};

static inline double maxAbs3(const Vec3& v) {
  double ax = fabs(v.x), ay = fabs(v.y), az = fabs(v.z);
  return ax > ay ? (ax > az ? ax : az) : (ay > az ? ay : az);
}

static inline void geodesicRHS(
  double r, double dr, double dphi, double E, double rS, double out[4]
) {
  double rr = (r == 0.0 ? 1e-12 : r);
  double f = 1.0 - rS / rr;
  double ff = (f == 0.0 ? 1e-12 : f);
  out[0] = dr;
  out[1] = dphi;
  double dtDLambda = E / ff;
  out[2] = -(rS / (2 * rr * rr)) * f * (dtDLambda * dtDLambda)
         + (rS / (2 * rr * rr * ff)) * (dr * dr)
         + (rr - rS) * (dphi * dphi);
  out[3] = -2.0 * dr * dphi / rr;
}

static inline void addState(const double a[4], const double b[4], double f, double out[4]) {
  out[0] = a[0] + b[0] * f;
  out[1] = a[1] + b[1] * f;
  out[2] = a[2] + b[2] * f;
  out[3] = a[3] + b[3] * f;
}

static inline void sampleBg(const Vec3& dir, int w, int h, const unsigned char* data,
                            unsigned char rgba[4]) {
  if (!data || w <= 0 || h <= 0) {
    // Fallback gradient by direction
    Vec3 d = dir.normalized();
    int R = (int)((d.x + 1.0) * 127.0); if (R < 0) R = 0; if (R > 255) R = 255;
    int G = (int)((d.y + 1.0) * 127.0); if (G < 0) G = 0; if (G > 255) G = 255;
    int B = (int)((d.z + 1.0) * 127.0); if (B < 0) B = 0; if (B > 255) B = 255;
    rgba[0] = (unsigned char)R;
    rgba[1] = (unsigned char)G;
    rgba[2] = (unsigned char)B;
    rgba[3] = 255;
    return;
  }
  Vec3 d = dir.normalized();
  double lon = atan2(d.y, d.x);
  double lat = asin(d.z);
  double u = (lon + M_PI) / (2.0 * M_PI);
  double v = (lat + M_PI_2) / M_PI;
  int x = (int)floor(u * w); if (x < 0) x = 0; if (x >= w) x = w-1;
  int y = (int)floor((1.0 - v) * h); if (y < 0) y = 0; if (y >= h) y = h-1;
  size_t idx = ((size_t)y * (size_t)w + (size_t)x) * 4;
  rgba[0] = data[idx + 0];
  rgba[1] = data[idx + 1];
  rgba[2] = data[idx + 2];
  rgba[3] = data[idx + 3];
}

static inline void tracePixel(
  int px, int py, int width, int height,
  const Vec3& camPos, const Vec3& forward, const Vec3& right, const Vec3& up,
  double w, double hhalf,
  double rS, double cubeHalfSize, int maxSteps, double dLambda,
  int bgW, int bgH, const unsigned char* bg,
  unsigned char out[4]
) {
  // Pixel to direction
  double nx = (2.0 * ((px + 0.5) / (double)width) - 1.0) * w;
  double ny = (1.0 - 2.0 * ((py + 0.5) / (double)height)) * hhalf;
  Vec3 dir = (forward + right * nx + up * ny).normalized();
  Vec3 origin = camPos;

  // Plane basis
  Vec3 planeNormal = origin.cross(dir);
  if (planeNormal.len2() < 1e-24) {
    planeNormal = dir.cross(Vec3(0,0,1));
    if (planeNormal.len2() < 1e-24) {
      planeNormal = dir.cross(Vec3(0,1,0));
      if (planeNormal.len2() < 1e-24) {
        planeNormal = dir.cross(Vec3(1,0,0));
      }
    }
  }
  planeNormal = planeNormal.normalized();
  Vec3 xAxis = dir.normalized();
  Vec3 yAxis = planeNormal.cross(xAxis).normalized();

  double x = origin.dot(xAxis);
  double y = origin.dot(yAxis);
  double r = sqrt(x*x + y*y);
  double phi = atan2(y, x);

  double vx = dir.dot(xAxis) * c;
  double vy = dir.dot(yAxis) * c;
  double dr = vx * cos(phi) + vy * sin(phi);
  double denom = (r == 0.0 ? 1e-12 : r);
  double dphi = (-vx * sin(phi) + vy * cos(phi)) / denom;

  double rr = (r == 0.0 ? 1e-12 : r);
  double f0 = 1.0 - rS / rr;
  double dtDLambda = sqrt((dr*dr) / (f0*f0) + (r*r * dphi * dphi) / f0);
  double E = f0 * dtDLambda;

  for (int step = 0; step < maxSteps; ++step) {
    double y0[4] = { r, phi, dr, dphi };
    double k1[4], k2[4], k3[4], k4[4], tmp[4];

    geodesicRHS(r, dr, dphi, E, rS, k1);
    addState(y0, k1, dLambda / 2.0, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k2);
    addState(y0, k2, dLambda / 2.0, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k3);
    addState(y0, k3, dLambda, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, rS, k4);

    r   += (dLambda / 6.0) * (k1[0] + 2*k2[0] + 2*k3[0] + k4[0]);
    phi += (dLambda / 6.0) * (k1[1] + 2*k2[1] + 2*k3[1] + k4[1]);
    dr  += (dLambda / 6.0) * (k1[2] + 2*k2[2] + 2*k3[2] + k4[2]);
    dphi+= (dLambda / 6.0) * (k1[3] + 2*k2[3] + 2*k3[3] + k4[3]);

    double px = r * cos(phi);
    double py = r * sin(phi);
    Vec3 pos3d = xAxis * px + yAxis * py;

    if (r <= rS) {
      out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 255; return;
    }
    if (maxAbs3(pos3d) > cubeHalfSize) {
      Vec3 escapeDir = pos3d.normalized();
      sampleBg(escapeDir, bgW, bgH, bg, out);
      return;
    }
  }
  out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 255;
}
} // namespace bh

extern "C" {
__attribute__((used, visibility("default"))) unsigned char* bh_render_frame(
  int width,
  int height,
  const double* camPos3,
  const double* camTarget3,
  const double* camUp3,
  double fovY,
  double rS,
  double cubeHalfSize,
  int maxSteps,
  double dLambda,
  const unsigned char* bgRgba,
  int bgW,
  int bgH
) {
  size_t len = (size_t)width * (size_t)height * 4;
  unsigned char* out = (unsigned char*)malloc(len);
  if (!out) return NULL;

  // Try Metal first
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  if (device) {
    @autoreleasepool {
      NSError* err = nil;
      id<MTLLibrary> lib = [device newDefaultLibrary];
      id<MTLFunction> fn = [lib newFunctionWithName:@"bh_kernel"];
      if (fn) {
        id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:fn error:&err];
        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];

        id<MTLBuffer> outBuf = [device newBufferWithLength:len options:MTLResourceStorageModeShared];

        struct CameraUniforms {
          simd_float3 camPos;
          simd_float3 forward;
          simd_float3 right;
          simd_float3 up;
          float w;
          float hhalf;
          float rS;
          float cubeHalfSize;
          int   maxSteps;
          float dLambda;
          int   width;
          int   height;
          int   bgW;
          int   bgH;
          int   hasBg;
        } U;

        const bh::Vec3 camPos(camPos3[0], camPos3[1], camPos3[2]);
        const bh::Vec3 camTarget(camTarget3[0], camTarget3[1], camTarget3[2]);
        const bh::Vec3 camUp(camUp3[0], camUp3[1], camUp3[2]);
        bh::Vec3 forward = (camTarget - camPos).normalized();
        bh::Vec3 right   = forward.cross(camUp).normalized();
        bh::Vec3 up      = right.cross(forward);
        float aspect = (float)width / (float)height;
        float hhalf = tanf((float)fovY / 2.0f);
        float w = aspect * hhalf;

        U.camPos = { (float)camPos.x, (float)camPos.y, (float)camPos.z };
        U.forward= { (float)forward.x, (float)forward.y, (float)forward.z };
        U.right  = { (float)right.x, (float)right.y, (float)right.z };
        U.up     = { (float)up.x, (float)up.y, (float)up.z };
        U.w = w; U.hhalf = hhalf; U.rS = (float)rS; U.cubeHalfSize = (float)cubeHalfSize;
        U.maxSteps = maxSteps; U.dLambda = (float)dLambda; U.width = width; U.height = height;
        U.bgW = bgW; U.bgH = bgH; U.hasBg = (bgRgba && bgW > 0 && bgH > 0) ? 1 : 0;

        id<MTLBuffer> ubo = [device newBufferWithBytes:&U length:sizeof(U) options:MTLResourceStorageModeShared];

  id<MTLTexture> bgTex = nil;
        if (U.hasBg) {
          MTLTextureDescriptor* td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:bgW height:bgH mipmapped:NO];
          bgTex = [device newTextureWithDescriptor:td];
          MTLRegion region = {
            {0,0,0}, { (NSUInteger)bgW, (NSUInteger)bgH, 1 }
          };
          [bgTex replaceRegion:region mipmapLevel:0 withBytes:bgRgba bytesPerRow:bgW * 4];
        }

  [enc setComputePipelineState:pso];
        [enc setBuffer:outBuf offset:0 atIndex:0];
        [enc setBuffer:ubo offset:0 atIndex:1];
        if (bgTex) {
          [enc setTexture:bgTex atIndex:0];
        }
  // Default linear sampler
  MTLSamplerDescriptor* sd = [MTLSamplerDescriptor new];
  sd.minFilter = MTLSamplerMinMagFilterLinear;
  sd.magFilter = MTLSamplerMinMagFilterLinear;
  sd.sAddressMode = MTLSamplerAddressModeRepeat;
  sd.tAddressMode = MTLSamplerAddressModeRepeat;
  id<MTLSamplerState> samp = [device newSamplerStateWithDescriptor:sd];
  [enc setSamplerState:samp atIndex:0];
        MTLSize grid = MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1);
        NSUInteger wgs = pso.maxTotalThreadsPerThreadgroup;
        NSUInteger tx = 16, ty = MAX(1, wgs / 16);
        MTLSize tg = MTLSizeMake(tx, ty, 1);
        [enc dispatchThreads:grid threadsPerThreadgroup:tg];
        [enc endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];

        memcpy(out, [outBuf contents], len);
        return out;
      }
    }
  }

  // CPU fallback
  const bh::Vec3 camPos(camPos3[0], camPos3[1], camPos3[2]);
  const bh::Vec3 camTarget(camTarget3[0], camTarget3[1], camTarget3[2]);
  const bh::Vec3 camUp(camUp3[0], camUp3[1], camUp3[2]);

  bh::Vec3 forward = (camTarget - camPos).normalized();
  bh::Vec3 right   = forward.cross(camUp).normalized();
  bh::Vec3 up      = right.cross(forward);

  double aspect = width / (double)height;
  double theta = fovY;
  double hhalf = tan(theta / 2.0);
  double w = aspect * hhalf;

  dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
  dispatch_apply((size_t)height, q, ^(size_t py) {
    for (int px = 0; px < width; ++px) {
      unsigned char rgba[4];
      bh::tracePixel(px, (int)py, width, height,
                     camPos, forward, right, up,
                     w, hhalf,
                     rS, cubeHalfSize, maxSteps, dLambda,
                     bgW, bgH, bgRgba,
                     rgba);
      size_t i = ((size_t)py * (size_t)width + (size_t)px) * 4;
      out[i+0] = rgba[0];
      out[i+1] = rgba[1];
      out[i+2] = rgba[2];
      out[i+3] = rgba[3];
    }
  });

  return out;
}

__attribute__((used, visibility("default"))) void bh_free(void* ptr) {
  if (ptr) free(ptr);
}
}

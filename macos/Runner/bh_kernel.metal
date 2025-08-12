#include <metal_stdlib>
using namespace metal;

constant float C_LIGHT = 299792458.0f;

struct CameraUniforms {
  float3 camPos;
  float3 forward;
  float3 right;
  float3 up;
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
};

inline float3 v_cross(float3 a, float3 b) { return cross(a, b); }
inline float3 v_norm(float3 a) { return normalize(a); }
inline float v_dot(float3 a, float3 b) { return dot(a, b); }

inline float maxAbs3(float3 v) {
  float ax = fabs(v.x), ay = fabs(v.y), az = fabs(v.z);
  return ax > ay ? (ax > az ? ax : az) : (ay > az ? ay : az);
}

inline void geodesicRHS(float r, float dr, float dphi, float E, float rS, thread float out[4]) {
  float rr = (r == 0.0f ? 1e-12f : r);
  float f = 1.0f - rS / rr;
  float ff = (f == 0.0f ? 1e-12f : f);
  out[0] = dr;
  out[1] = dphi;
  float dtDLambda = E / ff;
  out[2] = -(rS / (2.0f * rr * rr)) * f * (dtDLambda * dtDLambda)
         + (rS / (2.0f * rr * rr * ff)) * (dr * dr)
         + (rr - rS) * (dphi * dphi);
  out[3] = -2.0f * dr * dphi / rr;
}

inline void addState(const thread float a[4], const thread float b[4], float f, thread float out[4]) {
  out[0] = a[0] + b[0] * f;
  out[1] = a[1] + b[1] * f;
  out[2] = a[2] + b[2] * f;
  out[3] = a[3] + b[3] * f;
}

kernel void bh_kernel(
  device uchar*              outBytes [[buffer(0)]],
  constant CameraUniforms&   U        [[buffer(1)]],
  texture2d<float, access::sample> bgTex [[texture(0)]],
  sampler                    bgSamp   [[sampler(0)]],
  uint2 gid [[thread_position_in_grid]])
{
  if (gid.x >= (uint)U.width || gid.y >= (uint)U.height) return;

  int px = (int)gid.x;
  int py = (int)gid.y;

  float nx = (2.0f * ((px + 0.5f) / (float)U.width) - 1.0f) * U.w;
  float ny = (1.0f - 2.0f * ((py + 0.5f) / (float)U.height)) * U.hhalf;
  float3 dir = normalize(U.forward + U.right * nx + U.up * ny);
  float3 origin = U.camPos;

  float3 planeNormal = cross(origin, dir);
  if (dot(planeNormal, planeNormal) < 1e-24f) {
    planeNormal = cross(dir, float3(0,0,1));
    if (dot(planeNormal, planeNormal) < 1e-24f) {
      planeNormal = cross(dir, float3(0,1,0));
      if (dot(planeNormal, planeNormal) < 1e-24f) {
        planeNormal = cross(dir, float3(1,0,0));
      }
    }
  }
  planeNormal = normalize(planeNormal);
  float3 xAxis = dir;
  float3 yAxis = normalize(cross(planeNormal, xAxis));

  float x = dot(origin, xAxis);
  float y = dot(origin, yAxis);
  float r = sqrt(x*x + y*y);
  float phi = atan2(y, x);

  float vx = dot(dir, xAxis) * C_LIGHT;
  float vy = dot(dir, yAxis) * C_LIGHT;
  float dr = vx * cos(phi) + vy * sin(phi);
  float denom = (r == 0.0f ? 1e-12f : r);
  float dphi = (-vx * sin(phi) + vy * cos(phi)) / denom;

  float rr = (r == 0.0f ? 1e-12f : r);
  float f0 = 1.0f - U.rS / rr;
  float dtDLambda = sqrt((dr*dr) / (f0*f0) + (r*r * dphi * dphi) / f0);
  float E = f0 * dtDLambda;

  uchar4 outc = uchar4(0, 0, 0, 255);

  for (int step = 0; step < U.maxSteps; ++step) {
    float y0[4] = { r, phi, dr, dphi };
    float k1[4], k2[4], k3[4], k4[4], tmp[4];
    geodesicRHS(r, dr, dphi, E, U.rS, k1);
    addState(y0, k1, U.dLambda / 2.0f, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, U.rS, k2);
    addState(y0, k2, U.dLambda / 2.0f, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, U.rS, k3);
    addState(y0, k3, U.dLambda, tmp);
    geodesicRHS(tmp[0], tmp[2], tmp[3], E, U.rS, k4);

    r   += (U.dLambda / 6.0f) * (k1[0] + 2.0f*k2[0] + 2.0f*k3[0] + k4[0]);
    phi += (U.dLambda / 6.0f) * (k1[1] + 2.0f*k2[1] + 2.0f*k3[1] + k4[1]);
    dr  += (U.dLambda / 6.0f) * (k1[2] + 2.0f*k2[2] + 2.0f*k3[2] + k4[2]);
    dphi+= (U.dLambda / 6.0f) * (k1[3] + 2.0f*k2[3] + 2.0f*k3[3] + k4[3]);

    float px3 = r * cos(phi);
    float py3 = r * sin(phi);
    float3 pos3d = xAxis * px3 + yAxis * py3;

    if (r <= U.rS) {
      outc = uchar4(0,0,0,255);
      break;
    }
    if (maxAbs3(pos3d) > U.cubeHalfSize) {
      float3 escapeDir = normalize(pos3d);
      if (U.hasBg != 0) {
        float lon = atan2(escapeDir.y, escapeDir.x);
        float lat = asin(escapeDir.z);
        float u = (lon + M_PI_F) / (2.0f * M_PI_F);
        float v = (lat + (M_PI_F * 0.5f)) / M_PI_F;
        float2 uv = float2(u, 1.0f - v);
        float4 s = bgTex.sample(bgSamp, uv);
        outc = uchar4((uchar)(s.x * 255.0f), (uchar)(s.y * 255.0f), (uchar)(s.z * 255.0f), (uchar)(s.w * 255.0f));
      } else {
        int R = (int)((escapeDir.x + 1.0f) * 127.0f);
        int G = (int)((escapeDir.y + 1.0f) * 127.0f);
        int B = (int)((escapeDir.z + 1.0f) * 127.0f);
        outc = uchar4((uchar)clamp(R,0,255), (uchar)clamp(G,0,255), (uchar)clamp(B,0,255), 255);
      }
      break;
    }
  }

  size_t idx = ((size_t)py * (size_t)U.width + (size_t)px) * 4;
  outBytes[idx + 0] = outc.x;
  outBytes[idx + 1] = outc.y;
  outBytes[idx + 2] = outc.z;
  outBytes[idx + 3] = outc.w;
}

#include <metal_stdlib>
using namespace metal;

struct RayStateF {
    float r;
    float phi;
    float dr;
    float dphi;
    float E;
    float L;
};

inline void geodesic_rhs(thread const RayStateF& ray, thread float out_rhs[4], float rS) {
    const float r = ray.r;
    const float dr = ray.dr;
    const float dphi = ray.dphi;
    const float E = ray.E;
    const float f = 1.0f - rS / r;
    out_rhs[0] = dr;
    out_rhs[1] = dphi;
    const float dtDLambda = E / f;
    out_rhs[2] = -(rS / (2.0f * r * r)) * f * (dtDLambda * dtDLambda)
               +  (rS / (2.0f * r * r * f)) * (dr * dr)
               +  (r - rS) * (dphi * dphi);
    out_rhs[3] = -2.0f * dr * dphi / r;
}

kernel void stepRays(
    device RayStateF* rays [[buffer(0)]],
    constant float& dLambda [[buffer(1)]],
    constant float& rS [[buffer(2)]],
    constant int& steps [[buffer(3)]],
    constant int& count [[buffer(4)]],
    uint gid [[thread_position_in_grid]]) {
  if ((int)gid >= count) return;
  RayStateF ray = rays[gid];

  for (int s = 0; s < steps; ++s) {
    if (ray.r <= rS) break;

    float y0[4] = { ray.r, ray.phi, ray.dr, ray.dphi };
    float k1[4], k2[4], k3[4], k4[4], tmp[4];

    geodesic_rhs(ray, k1, rS);
    // y0 + k1 * dL/2
    for (int i = 0; i < 4; ++i) tmp[i] = y0[i] + k1[i] * (dLambda * 0.5f);
    RayStateF r2 = { tmp[0], tmp[1], tmp[2], tmp[3], ray.E, ray.L };
    geodesic_rhs(r2, k2, rS);

    for (int i = 0; i < 4; ++i) tmp[i] = y0[i] + k2[i] * (dLambda * 0.5f);
    RayStateF r3 = { tmp[0], tmp[1], tmp[2], tmp[3], ray.E, ray.L };
    geodesic_rhs(r3, k3, rS);

    for (int i = 0; i < 4; ++i) tmp[i] = y0[i] + k3[i] * dLambda;
    RayStateF r4 = { tmp[0], tmp[1], tmp[2], tmp[3], ray.E, ray.L };
    geodesic_rhs(r4, k4, rS);

    ray.r    += (dLambda / 6.0f) * (k1[0] + 2*k2[0] + 2*k3[0] + k4[0]);
    ray.phi  += (dLambda / 6.0f) * (k1[1] + 2*k2[1] + 2*k3[1] + k4[1]);
    ray.dr   += (dLambda / 6.0f) * (k1[2] + 2*k2[2] + 2*k3[2] + k4[2]);
    ray.dphi += (dLambda / 6.0f) * (k1[3] + 2*k2[3] + 2*k3[3] + k4[3]);
  }

  rays[gid] = ray;
}

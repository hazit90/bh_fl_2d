#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>

extern "C" {
__attribute__((visibility("default"))) unsigned char* bh_render_frame(
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
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      size_t i = ((size_t)y * (size_t)width + (size_t)x) * 4;
      out[i+0] = (unsigned char)((x * 255) / (width > 0 ? width : 1));
      out[i+1] = (unsigned char)((y * 255) / (height > 0 ? height : 1));
      out[i+2] = 128;
      out[i+3] = 255;
    }
  }
  return out;
}

__attribute__((visibility("default"))) void bh_free(void* ptr) {
  if (ptr) free(ptr);
}
}

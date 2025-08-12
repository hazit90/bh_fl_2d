#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double r;
    double phi;
    double dr;
    double dphi;
    double E;
    double L;
} RayState;

// Returns 1 if a Metal device is available, 0 otherwise
int metal_is_available(void);

// Steps `count` rays in-place by `steps` RK4 iterations of size dLambda with Schwarzschild radius rS.
void metal_step_rays(RayState* rays, int count, double dLambda, double rS, int steps);

#ifdef __cplusplus
}
#endif

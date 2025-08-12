#import <Metal/Metal.h>
#import "MetalCompute.h"

static id<MTLDevice> sDevice = nil;
static id<MTLCommandQueue> sQueue = nil;
static id<MTLLibrary> sLibrary = nil;
static id<MTLComputePipelineState> sPipeline = nil;

static void ensure_metal()
{
    if (sDevice) return;
    sDevice = MTLCreateSystemDefaultDevice();
    if (!sDevice) return;
    sQueue = [sDevice newCommandQueue];
    NSError* err = nil;
    sLibrary = [sDevice newDefaultLibrary];
    if (!sLibrary) {
        sDevice = nil; sQueue = nil; return;
    }
    id<MTLFunction> fn = [sLibrary newFunctionWithName:@"stepRays"];
    if (!fn) {
        sDevice = nil; sQueue = nil; sLibrary = nil; return;
    }
    sPipeline = [sDevice newComputePipelineStateWithFunction:fn error:&err];
    if (!sPipeline) {
        sDevice = nil; sQueue = nil; sLibrary = nil; return;
    }
}

extern "C" int metal_is_available(void)
{
    ensure_metal();
    return sDevice != nil ? 1 : 0;
}

extern "C" void metal_step_rays(RayState* rays, int count, double dLambda, double rS, int steps)
{
    ensure_metal();
    if (!sDevice || !sQueue || !sPipeline || count <= 0) return;

    // Convert to float buffers for GPU
    typedef struct { float r, phi, dr, dphi, E, L; } RayStateF;
    NSMutableData* data = [NSMutableData dataWithLength:sizeof(RayStateF) * count];
    RayStateF* out = (RayStateF*)data.mutableBytes;
    for (int i = 0; i < count; ++i) {
        out[i].r = (float)rays[i].r;
        out[i].phi = (float)rays[i].phi;
        out[i].dr = (float)rays[i].dr;
        out[i].dphi = (float)rays[i].dphi;
        out[i].E = (float)rays[i].E;
        out[i].L = (float)rays[i].L;
    }

    id<MTLBuffer> raysBuf = [sDevice newBufferWithBytes:data.bytes length:data.length options:MTLResourceStorageModeShared];
    float dLambdaF = (float)dLambda;
    float rSF = (float)rS;

    id<MTLBuffer> dLambdaBuf = [sDevice newBufferWithBytes:&dLambdaF length:sizeof(float) options:MTLResourceStorageModeShared];
    id<MTLBuffer> rSBuf = [sDevice newBufferWithBytes:&rSF length:sizeof(float) options:MTLResourceStorageModeShared];
    id<MTLBuffer> stepsBuf = [sDevice newBufferWithBytes:&steps length:sizeof(int) options:MTLResourceStorageModeShared];
    id<MTLBuffer> countBuf = [sDevice newBufferWithBytes:&count length:sizeof(int) options:MTLResourceStorageModeShared];

    id<MTLCommandBuffer> cb = [sQueue commandBuffer];
    id<MTLComputeCommandEncoder> enc = [cb computeCommandEncoder];
    [enc setComputePipelineState:sPipeline];
    [enc setBuffer:raysBuf offset:0 atIndex:0];
    [enc setBuffer:dLambdaBuf offset:0 atIndex:1];
    [enc setBuffer:rSBuf offset:0 atIndex:2];
    [enc setBuffer:stepsBuf offset:0 atIndex:3];
    [enc setBuffer:countBuf offset:0 atIndex:4];

    MTLSize grid = MTLSizeMake((NSUInteger)count, 1, 1);
    NSUInteger w = sPipeline.maxTotalThreadsPerThreadgroup;
    if (w > 256) w = 256;
    MTLSize tg = MTLSizeMake(w, 1, 1);
    [enc dispatchThreads:grid threadsPerThreadgroup:tg];
    [enc endEncoding];
    [cb commit];
    [cb waitUntilCompleted];

    // Read back and convert to double
    RayStateF* res = (RayStateF*)raysBuf.contents;
    for (int i = 0; i < count; ++i) {
        rays[i].r = res[i].r;
        rays[i].phi = res[i].phi;
        rays[i].dr = res[i].dr;
        rays[i].dphi = res[i].dphi;
        // E and L are conserved, no need to update
    }
}

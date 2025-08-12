#import "BHMetalTexture.h"
#import <FlutterMacOS/FlutterMacOS.h>
#import <IOSurface/IOSurface.h>

@interface BHMetalTexture () {
  CVPixelBufferRef _pixelBuffer;
}
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> queue;
@property(nonatomic, strong) id<MTLComputePipelineState> pso;
@property(nonatomic, strong) id<MTLTexture> texture;
@end

@implementation BHMetalTexture

- (instancetype)initWithDevice:(id<MTLDevice>)device {
  if ((self = [super init])) {
    _device = device;
    _queue = [device newCommandQueue];
    NSError* err = nil;
    id<MTLLibrary> lib = [device newDefaultLibrary];
    id<MTLFunction> fn = [lib newFunctionWithName:@"bh_kernel_tex"];
    _pso = [device newComputePipelineStateWithFunction:fn error:&err];
  }
  return self;
}

- (BOOL)resize:(int)width height:(int)height {
  if (_pixelBuffer) {
    CVBufferRelease(_pixelBuffer);
    _pixelBuffer = nil;
  }
  NSDictionary* attrs = @{
    (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
    (id)kCVPixelBufferWidthKey: @(width),
    (id)kCVPixelBufferHeightKey: @(height)
  };
  CVReturn r = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &_pixelBuffer);
  if (r != kCVReturnSuccess) return NO;

  CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
  IOSurfaceRef io = CVPixelBufferGetIOSurface(_pixelBuffer);
  MTLTextureDescriptor* td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
  _texture = [_device newTextureWithDescriptor:td iosurface:io plane:0];
  CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);
  _width = width; _height = height;
  return YES;
}

- (void)renderWithUniforms:(const void*)bytes length:(size_t)len {
  if (!_texture) return;
  id<MTLCommandBuffer> cmd = [_queue commandBuffer];
  id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
  [enc setComputePipelineState:_pso];

  id<MTLBuffer> ubo = [_device newBufferWithBytes:bytes length:len options:MTLResourceStorageModeShared];
  [enc setTexture:_texture atIndex:0];
  [enc setBuffer:ubo offset:0 atIndex:0];

  MTLSize grid = MTLSizeMake((NSUInteger)_width, (NSUInteger)_height, 1);
  NSUInteger wgs = _pso.maxTotalThreadsPerThreadgroup;
  NSUInteger tx = 16, ty = MAX(1, wgs / 16);
  MTLSize tg = MTLSizeMake(tx, ty, 1);
  [enc dispatchThreads:grid threadsPerThreadgroup:tg];
  [enc endEncoding];
  [cmd commit];
  [cmd waitUntilCompleted];
}

- (CVPixelBufferRef)copyPixelBuffer {
  if (_pixelBuffer) CFRetain(_pixelBuffer);
  return _pixelBuffer;
}

- (CVPixelBufferRef)pixelBuffer { return _pixelBuffer; }

@end

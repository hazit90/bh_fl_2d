#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
@protocol FlutterTexture;
#ifdef __cplusplus
}
#endif
#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>

@interface BHMetalTexture : NSObject<FlutterTexture>

@property(nonatomic, readonly) id<MTLDevice> device;
@property(nonatomic, readonly) id<MTLCommandQueue> queue;
@property(nonatomic, readonly) id<MTLComputePipelineState> pso;
@property(nonatomic, readonly) CVPixelBufferRef pixelBuffer;
@property(nonatomic, readonly) id<MTLTexture> texture;
@property(nonatomic, assign) int width;
@property(nonatomic, assign) int height;

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (BOOL)resize:(int)width height:(int)height;
- (void)renderWithUniforms:(const void*)bytes length:(size_t)len;

@end

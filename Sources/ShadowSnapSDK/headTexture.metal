//
//  headTexture.metal
//  ShadowSnap
//
//  Created by Harry He on 24/04/23.
//

#include <metal_stdlib>
using namespace metal;

#include <SceneKit/scn_metal>

constant const float4x4 ycbcrToRGBTransformHead = float4x4(
    float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
);

struct HeadNodeBuffer {
    float4x4 modelViewProjectionTransform;
    float4x4 modelViewTransform;
};

inline float2 toScreenSpaceCoordinatesHead(
    const float4x4 displayTransform,
    const float4x4 projectionTransform,
    const float4 vertexCamera)
{
    // Camera projection and perspective divide to get normalized viewport coordinates (clip space).
    float4 vertexClipSpace = projectionTransform * vertexCamera;
    vertexClipSpace /= vertexClipSpace.w;
    
    // XY in clip space is [-1,1]x[-1,1], so adjust to UV texture coordinates: [0,1]x[0,1].
    // Image coordinates are Y-flipped (upper-left origin).
    float4 vertexImageSpace = float4(vertexClipSpace.xy * 0.5 + 0.5, 0.0, 1.0);
    vertexImageSpace.y = 1.0 - vertexImageSpace.y;
    
    // Apply ARKit's display transform (device orientation * front-facing camera flip).
    return (displayTransform * vertexImageSpace).xy;
}

struct HeadTextureState {
    float4x4 displayTransform;
    float4x4 modelViewTransform;
    float4x4 projectionTransform;
};

struct HeadTextureInOut {
    float4 position [[position]];
    float3 normal;
    float2 screenSpaceTexCoord;
};

vertex HeadTextureInOut headTextureVertex(const device float3* positionArray [[buffer(0)]],
                                          const device float3* normalArray [[buffer(1)]],
                                          const device float2* uvArray [[buffer(2)]],
                                          constant HeadTextureState& state [[buffer(3)]],
                                          unsigned int vid [[vertex_id]])
{
    HeadTextureInOut out;

    // Compute the position in the screen texture
    const float4 actualPos = state.modelViewTransform * float4(positionArray[vid], 1);
    out.screenSpaceTexCoord = toScreenSpaceCoordinatesHead(state.displayTransform, state.projectionTransform, actualPos);
    
    // Now write out the texture space position
    // This is the position used for drawing
    const float2 uv = uvArray[vid];
    out.position = float4(float2(uv.x, 1 - uv.y) * 2 - 1, 0, 1); // Convert to normalized device coordinates (i.e. -1 to 1)

    // Write out normal of the vertex
    const float4 normal = state.projectionTransform * (state.modelViewTransform * float4(normalArray[vid], 1.0));
    out.normal = normalize(normal.xyz);
    return out;
}

float3 gammaCorrectionHead(float3 color) {
//brightness adjustment
color = color * 1.2;

return float3(
( color.r > 0.04045 ) ? pow((color.r + 0.055) / 1.055, 2.4) : color.r / 12.92,
( color.g > 0.04045 ) ? pow((color.g + 0.055) / 1.055, 2.4) : color.g / 12.92,
( color.b > 0.04045 ) ? pow((color.b + 0.055) / 1.055, 2.4) : color.b / 12.92);
}

fragment float4 headTextureFragment(HeadTextureInOut in [[stage_in]],
                                    texture2d<float, access::sample> capturedImageTextureY [[texture(0)]],
                                    texture2d<float, access::sample> capturedImageTextureCbCr [[texture(1)]])
{
    constexpr sampler textureSampler(filter::bicubic, address::clamp_to_edge);
    
    // Sample screen space texture
    const float4 ycbcr = float4(capturedImageTextureY.sample(textureSampler, in.screenSpaceTexCoord).r,
                                capturedImageTextureCbCr.sample(textureSampler, in.screenSpaceTexCoord).rg, 1.0);
    
    // Convert to RGB
    const float3 rgbColor = (ycbcrToRGBTransformHead * ycbcr).rgb;
    return float4(gammaCorrectionHead(rgbColor), 1);
}

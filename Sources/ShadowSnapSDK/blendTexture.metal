//  blendTexture.metal

#include <metal_stdlib>
using namespace metal;

kernel void computeMeanColor(
    texture2d<float, access::read> headTexture [[ texture(0) ]],
    texture2d<float, access::sample> sampleMask [[ texture(1) ]],
    device atomic_uint* colorSumX [[ buffer(0) ]],
    device atomic_uint* colorSumY [[ buffer(1) ]],
    device atomic_uint* colorSumZ [[ buffer(2) ]],
    device atomic_uint* colorSumW [[ buffer(3) ]],
    device atomic_uint* count [[ buffer(4) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    //sampler
    constexpr sampler samplerState(filter::linear, address::clamp_to_edge);

    // Convert gid to texture coordinates
    float2 gidNormalized = float2(gid) / float2(headTexture.get_width(), headTexture.get_height());
    
    // Sample color from headTexture
    float4 color = headTexture.read(gid);

    // Sample mask value
    float4 mask = sampleMask.sample(samplerState, gidNormalized);

    // Only add color to accumulator if mask value is not zero
    if (mask.a > 0) {
        atomic_fetch_add_explicit(colorSumX, uint(color.x * 255.0), memory_order_relaxed);
        atomic_fetch_add_explicit(colorSumY, uint(color.y * 255.0), memory_order_relaxed);
        atomic_fetch_add_explicit(colorSumZ, uint(color.z * 255.0), memory_order_relaxed);
        atomic_fetch_add_explicit(colorSumW, uint(color.w * 255.0), memory_order_relaxed);
        atomic_fetch_add_explicit(count, 1, memory_order_relaxed);
    }
}


// Rename the function to blendWithMeanColor
kernel void blendWithMeanColor(
    texture2d<float, access::read> headTexture [[ texture(0) ]],
    texture2d<float, access::sample> maskTexture [[ texture(1) ]],
    constant float4* meanColor [[ buffer(0) ]],
    texture2d<float, access::write> outTexture [[ texture(2) ]],
    uint2 gid [[ thread_position_in_grid ]]
) {
    //sampler
    constexpr sampler samplerState(filter::linear, address::clamp_to_edge);

    // Convert gid to texture coordinates
    float2 gidNormalized = float2(gid) / float2(headTexture.get_width(), headTexture.get_height());
    
    
    // Sample color from headTexture
    float4 headColor = headTexture.read(gid);

    // Sample mask value
    float4 mask = maskTexture.sample(samplerState, gidNormalized);

    // Define the brightness factor directly in the shader
    float brightness = 0.38;

    // Lighten up the mean color using the brightness value
    float4 lightenedMeanColor = (*meanColor) * (1 + brightness);

    // Define the color balance factors for each channel
    float3 balanceFactors = float3(1.0, 1.0, 1.0); // adjust these values to get the desired color balance

    // Apply the color balance to the mean color
    lightenedMeanColor.rgb *= balanceFactors;

    // Clamp the color values between 0 and 1
    lightenedMeanColor.rgb = clamp(lightenedMeanColor.rgb, 0.0, 1.0);

    // Blend the result with the head texture, using the mask texture's red channel
    float4 finalColor = headColor * (1.0 - mask.a) + lightenedMeanColor * mask.a;

    // Write the final color to the output texture
    outTexture.write(finalColor, gid);
}






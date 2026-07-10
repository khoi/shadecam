#include <metal_stdlib>
using namespace metal;

struct VertexOutput {
    float4 position [[position]];
    float2 uv;
};

struct DisplayUniforms {
    float2 viewSize;
    float2 cameraSize;
};

vertex VertexOutput fullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0),
    };
    const float2 coordinates[] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0),
    };

    VertexOutput output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.uv = coordinates[vertexID];
    return output;
}

fragment float4 cameraConversionFragment(
    VertexOutput input [[stage_in]],
    texture2d<float> luma [[texture(0)]],
    texture2d<float> chroma [[texture(1)]],
    sampler textureSampler [[sampler(0)]])
{
    const float y = luma.sample(textureSampler, input.uv).r;
    const float2 cbcr = chroma.sample(textureSampler, input.uv).rg - 0.5;
    const float3 rgb = float3(
        y + 1.5748 * cbcr.y,
        y - 0.1873 * cbcr.x - 0.4681 * cbcr.y,
        y + 1.8556 * cbcr.x
    );
    return float4(rgb, 1.0);
}

fragment float4 cameraDisplayFragment(
    VertexOutput input [[stage_in]],
    constant DisplayUniforms& uniforms [[buffer(0)]],
    texture2d<float> camera [[texture(0)]],
    sampler textureSampler [[sampler(0)]])
{
    const float viewAspect = uniforms.viewSize.x / uniforms.viewSize.y;
    const float cameraAspect = uniforms.cameraSize.x / uniforms.cameraSize.y;
    float2 uv = input.uv;

    if (viewAspect > cameraAspect) {
        const float width = cameraAspect / viewAspect;
        uv.x = (uv.x - (1.0 - width) * 0.5) / width;
    } else {
        const float height = viewAspect / cameraAspect;
        uv.y = (uv.y - (1.0 - height) * 0.5) / height;
    }

    if (any(uv < 0.0) || any(uv > 1.0)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return camera.sample(textureSampler, uv);
}

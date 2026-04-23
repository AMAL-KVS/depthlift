#include <metal_stdlib>
using namespace metal;

// ─── Uniform struct (must match MetalDepthRenderer.Uniforms layout) ───────

struct Uniforms {
    float4x4 mvp;
    float    depthScale;
    float    parallaxFactor;
    float2   tiltOffset;
    float    focusDepth;
    float    bokehIntensity;
    int      bokehEnabled;
    int      _padding;
};

// ─── Vertex output ────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float  depth;
};

// ─── Vertex shader ────────────────────────────────────────────────────────
//
// Displaces a planar grid along Z by per-vertex depth and shifts XY
// by tilt offset × parallax factor × depth.

vertex VertexOut depth_vertex(uint vid [[vertex_id]],
                              const device float2 *positions [[buffer(0)]],
                              const device float2 *uvs       [[buffer(1)]],
                              const device float  *depths    [[buffer(2)]],
                              constant Uniforms   &u         [[buffer(3)]]) {
    VertexOut out;

    float2 pos = positions[vid];
    float2 uv  = uvs[vid];
    float  d   = depths[vid];

    // Depth displacement.
    float3 displaced = float3(pos, d * u.depthScale);

    // Tilt-driven parallax.
    displaced.xy += u.tiltOffset * u.parallaxFactor * d;

    out.position = u.mvp * float4(displaced, 1.0);
    out.uv       = uv;
    out.depth    = d;
    return out;
}

// ─── Fragment shader ──────────────────────────────────────────────────────
//
// Samples the RGB texture. When bokeh is enabled, applies a 9-tap
// Gaussian blur whose radius scales with |depth − focusDepth|.

fragment float4 depth_fragment(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear,
                        address::clamp_to_edge);

    float4 color = tex.sample(s, in.uv);

    if (u.bokehEnabled == 1) {
        float blurAmount = abs(in.depth - u.focusDepth) * u.bokehIntensity * 8.0;

        if (blurAmount > 0.1) {
            float2 texSize = float2(tex.get_width(), tex.get_height());
            float2 texel   = 1.0 / texSize;

            // 9-tap Gaussian weights (σ ≈ 2.0).
            const float weights[9] = {
                0.0279, 0.0659, 0.1210, 0.1747, 0.2010,
                0.1747, 0.1210, 0.0659, 0.0279
            };

            float4 blurred = float4(0.0);
            for (int i = 0; i < 9; i++) {
                float offset = float(i - 4) * blurAmount;

                // Horizontal tap.
                float2 hOff = float2(offset * texel.x, 0.0);
                blurred += tex.sample(s, in.uv + hOff) * weights[i] * 0.5;

                // Vertical tap.
                float2 vOff = float2(0.0, offset * texel.y);
                blurred += tex.sample(s, in.uv + vOff) * weights[i] * 0.5;
            }

            color = blurred;
        }
    }

    return color;
}

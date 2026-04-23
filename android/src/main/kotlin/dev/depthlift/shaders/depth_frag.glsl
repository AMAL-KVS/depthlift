#version 300 es
precision mediump float;

// ─── Fragment Shader: Texture sampling with optional bokeh blur ───────────
//
// Samples the RGB texture at v_uv. When bokeh is enabled, applies a
// separable Gaussian blur whose radius is driven by the distance between
// the fragment's depth and the focal plane.

in vec2  v_uv;
in float v_depth;

uniform sampler2D u_texture;
uniform float     u_focusDepth;
uniform float     u_bokehIntensity;
uniform int       u_bokehEnabled;       // 0 = off, 1 = on

out vec4 fragColor;

// ─── 9-tap Gaussian weights (σ ≈ 2.0) ────────────────────────────────────
const int   KERNEL_SIZE = 9;
const float weights[9] = float[](
    0.0279,  0.0659,  0.1210,  0.1747,  0.2010,
    0.1747,  0.1210,  0.0659,  0.0279
);

/// Single-pass approximation of a separable Gaussian blur.
/// For a true two-pass implementation, render the horizontal pass to an
/// FBO first and then run the vertical pass here.
vec4 gaussianBlur(sampler2D tex, vec2 uv, float radius) {
    vec2 texelSize = 1.0 / vec2(textureSize(tex, 0));
    vec4 result = vec4(0.0);

    // Horizontal + vertical combined (box approximation for single pass).
    for (int i = 0; i < KERNEL_SIZE; i++) {
        float offset = float(i - KERNEL_SIZE / 2) * radius;

        // Horizontal tap.
        vec2 hOffset = vec2(offset * texelSize.x, 0.0);
        result += texture(tex, uv + hOffset) * weights[i] * 0.5;

        // Vertical tap.
        vec2 vOffset = vec2(0.0, offset * texelSize.y);
        result += texture(tex, uv + vOffset) * weights[i] * 0.5;
    }

    return result;
}

void main() {
    vec4 color = texture(u_texture, v_uv);

    if (u_bokehEnabled == 1) {
        // Blur radius proportional to distance from focal plane.
        float blurAmount = abs(v_depth - u_focusDepth) * u_bokehIntensity * 8.0;

        if (blurAmount > 0.1) {
            color = gaussianBlur(u_texture, v_uv, blurAmount);
        }
    }

    fragColor = color;
}

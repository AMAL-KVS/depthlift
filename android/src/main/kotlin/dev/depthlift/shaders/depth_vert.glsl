#version 300 es

// ─── Vertex Shader: Depth-displaced parallax mesh ─────────────────────────
//
// Displaces a planar grid along Z by the per-vertex depth value and
// applies a tilt offset modulated by depth for parallax motion.

layout(location = 0) in vec2 a_position;   // NDC grid position [-1, 1]
layout(location = 1) in vec2 a_uv;         // texture coordinate [0, 1]
layout(location = 2) in float a_depth;     // normalised depth   [0, 1]

uniform mat4  u_mvp;
uniform float u_depthScale;
uniform vec2  u_tiltOffset;        // gyro / pointer offset [-1, 1]
uniform float u_parallaxFactor;

out vec2  v_uv;
out float v_depth;

void main() {
    // Displace Z by depth.
    vec3 pos = vec3(a_position, a_depth * u_depthScale);

    // Parallax: shift XY proportional to depth × tilt.
    pos.xy += u_tiltOffset * u_parallaxFactor * a_depth;

    gl_Position = u_mvp * vec4(pos, 1.0);

    v_uv    = a_uv;
    v_depth = a_depth;
}

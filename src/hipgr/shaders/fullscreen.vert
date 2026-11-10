// HiPGR full-screen vertex shader: one triangle covering the target, from the
// vertex index alone. No vertex buffer, no attributes.
//
// v_uv is (0, 0) at the top left of the target, which is also how the backend
// reads pixels back, so a chain of passes samples exactly what it wrote.
layout(location = 0) out vec2 v_uv;

void main() {
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    v_uv = p;
    gl_Position = vec4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
}

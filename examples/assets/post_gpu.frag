#version 450
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 out_color;
layout(set = 2, binding = 0) uniform sampler2D u_texture;
void main() {
   vec4 c = texture(u_texture, v_uv);
   float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
   vec2 d = v_uv - 0.5;
   float vignette = smoothstep(0.85, 0.15, length(d));
   out_color = vec4(mix(c.rgb, vec3(gray), 0.75) * vignette, 1.0);
}

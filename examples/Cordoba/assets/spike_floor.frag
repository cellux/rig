#version 330 core

in vec3 v_world;
in vec2 v_uv;

out vec4 frag_color;

uniform mat4 u_mvp;
uniform sampler2D u_texture;

vec3 camera_position()
{
   return (inverse(u_mvp) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void main()
{
   vec3 normal = vec3(0.0, 1.0, 0.0);
   vec3 view_dir = normalize(camera_position() - v_world);
   float fresnel = pow(1.0 - max(dot(normal, view_dir), 0.0), 2.2);

   float tile = texture(u_texture, v_uv * 18.0).r;
   vec3 stone = mix(vec3(0.30, 0.145, 0.085), vec3(0.52, 0.29, 0.17), tile);
   stone *= 0.88 + 0.12 * sin(v_world.x * 3.1) * sin(v_world.z * 2.7);

   vec3 reflected = reflect(-view_dir, normal);
   float up = clamp(reflected.y, 0.0, 1.0);
   vec3 env = mix(vec3(0.12, 0.075, 0.055), vec3(0.34, 0.27, 0.21), up);

   // A stylised reflection of the striped arcade: cream/red bands receding
   // with the reflection direction. This is the Phase 1 approximation, not a
   // true screen-space or planar reflection.
   float bands = sin((reflected.x * 4.0 + reflected.z * 2.0) * 6.28318);
   float red = smoothstep(0.25, 0.65, bands);
   vec3 arch = mix(vec3(0.62, 0.53, 0.42), vec3(0.46, 0.13, 0.09), red);
   arch *= 0.35 + 0.65 * up;
   env = mix(env, arch, 0.55);

   float daylight = 0.72 + 0.28 * max(dot(normal, normalize(vec3(-0.45, 1.0, 0.25))), 0.0);
   vec3 color = mix(stone * daylight, env, 0.18 + 0.55 * fresnel);

   color = color / (color + vec3(1.0));
   color = pow(color, vec3(1.0 / 2.2));
   frag_color = vec4(color, 1.0);
}

#version 330 core

in vec3 v_world;
in vec3 v_color;
in vec2 v_uv;

out vec4 frag_color;

uniform mat4 u_mvp;

vec3 camera_position()
{
   return (inverse(u_mvp) * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void main()
{
   vec3 normal = normalize(cross(dFdx(v_world), dFdy(v_world)));
   vec3 view_dir = normalize(camera_position() - v_world);
   if (dot(normal, view_dir) < 0.0) {
      normal = -normal;
   }

   vec3 daylight = normalize(vec3(-0.45, 1.0, 0.25));
   float diffuse = max(dot(normal, daylight), 0.0);
   float bounce = max(dot(normal, vec3(0.0, -1.0, 0.0)), 0.0) * 0.10;

   vec3 warm_a = vec3(2.0, 1.65, 1.05);
   vec3 warm_b = vec3(1.6, 1.1, 0.65);
   vec3 l0 = vec3(-9.0, 2.2, 4.0);
   vec3 l1 = vec3(10.0, 2.2, 14.0);
   float d0 = max(dot(normal, normalize(l0 - v_world)), 0.0);
   float d1 = max(dot(normal, normalize(l1 - v_world)), 0.0);
   float a0 = 5.0 / (1.0 + 0.10 * dot(l0 - v_world, l0 - v_world));
   float a1 = 4.0 / (1.0 + 0.10 * dot(l1 - v_world, l1 - v_world));

   vec3 albedo = v_color * (0.92 + 0.08 * sin(v_uv.x * 22.0 + v_uv.y * 7.0));
   vec3 color = albedo * (0.16 + 0.78 * diffuse + bounce);
   color += albedo * (warm_a * d0 * a0 + warm_b * d1 * a1) * 0.10;

   vec3 halfway = normalize(daylight + view_dir);
   float specular = pow(max(dot(normal, halfway), 0.0), 18.0) * 0.08;
   color += specular;

   color = color / (color + vec3(1.0));
   color = pow(color, vec3(1.0 / 2.2));
   frag_color = vec4(color, 1.0);
}

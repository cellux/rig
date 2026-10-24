#version 330 core
in vec3 v_color;
out vec4 frag_color;
uniform float u_time;
void main() {
   float pulse = 0.5 + 0.5 * sin(u_time);
   frag_color = vec4(v_color.gbr * pulse, 1.0);
}

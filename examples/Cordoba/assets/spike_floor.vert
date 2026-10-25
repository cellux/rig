#version 330 core

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_color;
layout(location = 2) in vec2 in_uv;

out vec3 v_world;
out vec2 v_uv;

uniform mat4 u_mvp;

void main()
{
   v_world = in_position;
   v_uv = in_uv;
   gl_Position = u_mvp * vec4(in_position, 1.0);
}

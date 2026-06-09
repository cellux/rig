# `mathx`

Small 3D math helpers built on LuaJIT FFI arrays.

## Conventions

- matrices are `float[16]` cdata arrays
- vectors are `float[3]` cdata arrays
- matrices use row-major storage
- matrix multiplication is `out = a * b`
- the current helpers are intended for row-vector transforms, matching the SDL GPU cube example and its `row_major float4x4` HLSL upload path
- handedness is encoded in function names only where it affects the result

## Constructors

- `mathx.mat4()`
  - Allocates a zeroed `float[16]`.
- `mathx.vec3(x?, y?, z?)`
  - Allocates a `float[3]`.

## Scalar API

- `mathx.clamp(value, low, high)`
- `mathx.clamp01(value)`
- `mathx.lerp(a, b, t)`

## Matrix API

- `mathx.mat4_identity(out)`
- `mathx.mat4_copy(out, src)`
- `mathx.mat4_multiply(out, a, b)`
- `mathx.mat4_translation(out, x, y, z)`
- `mathx.mat4_scale(out, x, y, z)`
- `mathx.mat4_rotation_x(out, angle)`
- `mathx.mat4_rotation_y(out, angle)`
- `mathx.mat4_rotation_z(out, angle)`
- `mathx.mat4_look_at_lh(out, eye, target, up)`
- `mathx.mat4_look_at_rh(out, eye, target, up)`
- `mathx.mat4_perspective_lh(out, fov_y, aspect, near_z, far_z)`
- `mathx.mat4_perspective_rh(out, fov_y, aspect, near_z, far_z)`

## Vector API

- `mathx.vec3_set(out, x, y, z)`
- `mathx.vec3_copy(out, src)`
- `mathx.vec3_dot(a, b)`
- `mathx.vec3_length_squared(v)`
- `mathx.vec3_length(v)`
- `mathx.vec3_subtract(out, a, b)`
- `mathx.vec3_cross(out, a, b)`
- `mathx.vec3_normalize(out, v)`

## Notes

- The API is intentionally procedural and uses explicit output parameters to avoid unnecessary allocation in render loops.
- This first version is intentionally small. More helpers should be added only after their conventions are clear.

# `math3d`

Small 3D math helpers built on LuaJIT FFI arrays.

## Conventions

- matrices are `float[16]` cdata arrays
- vectors are `float[3]` cdata arrays
- matrices use row-major storage
- matrix multiplication is `out = a * b`
- the current helpers are intended for row-vector transforms, matching the SDL GPU cube example and its `row_major float4x4` HLSL upload path
- handedness is encoded in function names only where it affects the result

## Constructors

- `math3d.mat4()`
  - Allocates a zeroed `float[16]`.
- `math3d.vec3(x?, y?, z?)`
  - Allocates a `float[3]`.

## Matrix API

- `math3d.mat4_identity(out)`
- `math3d.mat4_copy(out, src)`
- `math3d.mat4_multiply(out, a, b)`
- `math3d.mat4_translation(out, x, y, z)`
- `math3d.mat4_scale(out, x, y, z)`
- `math3d.mat4_rotation_x(out, angle)`
- `math3d.mat4_rotation_y(out, angle)`
- `math3d.mat4_rotation_z(out, angle)`
- `math3d.mat4_look_at_lh(out, eye, target, up)`
- `math3d.mat4_look_at_rh(out, eye, target, up)`
- `math3d.mat4_perspective_lh(out, fov_y, aspect, near_z, far_z)`
- `math3d.mat4_perspective_rh(out, fov_y, aspect, near_z, far_z)`

## Vector API

- `math3d.vec3_set(out, x, y, z)`
- `math3d.vec3_copy(out, src)`
- `math3d.vec3_dot(a, b)`
- `math3d.vec3_length_squared(v)`
- `math3d.vec3_length(v)`
- `math3d.vec3_subtract(out, a, b)`
- `math3d.vec3_cross(out, a, b)`
- `math3d.vec3_normalize(out, v)`

## Notes

- The API is intentionally procedural and uses explicit output parameters to avoid unnecessary allocation in render loops.
- This first version is intentionally small. More helpers should be added only after their conventions are clear.

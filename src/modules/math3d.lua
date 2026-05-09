local M = ... or {}
local ffi = ffi

ffi.cdef[[
typedef float rig_math3d_mat4[16];
typedef float rig_math3d_vec3[3];
]]

local function write_identity(out)
   out[0] = 1.0
   out[1] = 0.0
   out[2] = 0.0
   out[3] = 0.0
   out[4] = 0.0
   out[5] = 1.0
   out[6] = 0.0
   out[7] = 0.0
   out[8] = 0.0
   out[9] = 0.0
   out[10] = 1.0
   out[11] = 0.0
   out[12] = 0.0
   out[13] = 0.0
   out[14] = 0.0
   out[15] = 1.0
end

local function require_mat4(value, name)
   if type(value) ~= "cdata" then
      error(name .. " must be a float[16] cdata matrix", 0)
   end
end

local function require_vec3(value, name)
   if type(value) ~= "cdata" then
      error(name .. " must be a float[3] cdata vector", 0)
   end
end

local function vec3_length_components(x, y, z)
   return math.sqrt(x * x + y * y + z * z)
end

local function normalize_components(x, y, z, label)
   local length = vec3_length_components(x, y, z)
   if length == 0.0 then
      error(label .. " must not be a zero-length vector", 0)
   end
   local inv = 1.0 / length
   return x * inv, y * inv, z * inv
end

function M.mat4()
   return ffi.new("rig_math3d_mat4")
end

function M.vec3(x, y, z)
   local out = ffi.new("rig_math3d_vec3")
   out[0] = x or 0.0
   out[1] = y or 0.0
   out[2] = z or 0.0
   return out
end

function M.mat4_identity(out)
   require_mat4(out, "out")
   write_identity(out)
   return out
end

function M.mat4_copy(out, src)
   require_mat4(out, "out")
   require_mat4(src, "src")
   ffi.copy(out, src, ffi.sizeof("rig_math3d_mat4"))
   return out
end

function M.mat4_multiply(out, a, b)
   require_mat4(out, "out")
   require_mat4(a, "a")
   require_mat4(b, "b")

   local r0 = a[0] * b[0] + a[1] * b[4] + a[2] * b[8] + a[3] * b[12]
   local r1 = a[0] * b[1] + a[1] * b[5] + a[2] * b[9] + a[3] * b[13]
   local r2 = a[0] * b[2] + a[1] * b[6] + a[2] * b[10] + a[3] * b[14]
   local r3 = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3] * b[15]

   local r4 = a[4] * b[0] + a[5] * b[4] + a[6] * b[8] + a[7] * b[12]
   local r5 = a[4] * b[1] + a[5] * b[5] + a[6] * b[9] + a[7] * b[13]
   local r6 = a[4] * b[2] + a[5] * b[6] + a[6] * b[10] + a[7] * b[14]
   local r7 = a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7] * b[15]

   local r8 = a[8] * b[0] + a[9] * b[4] + a[10] * b[8] + a[11] * b[12]
   local r9 = a[8] * b[1] + a[9] * b[5] + a[10] * b[9] + a[11] * b[13]
   local r10 = a[8] * b[2] + a[9] * b[6] + a[10] * b[10] + a[11] * b[14]
   local r11 = a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11] * b[15]

   local r12 = a[12] * b[0] + a[13] * b[4] + a[14] * b[8] + a[15] * b[12]
   local r13 = a[12] * b[1] + a[13] * b[5] + a[14] * b[9] + a[15] * b[13]
   local r14 = a[12] * b[2] + a[13] * b[6] + a[14] * b[10] + a[15] * b[14]
   local r15 = a[12] * b[3] + a[13] * b[7] + a[14] * b[11] + a[15] * b[15]

   out[0] = r0
   out[1] = r1
   out[2] = r2
   out[3] = r3
   out[4] = r4
   out[5] = r5
   out[6] = r6
   out[7] = r7
   out[8] = r8
   out[9] = r9
   out[10] = r10
   out[11] = r11
   out[12] = r12
   out[13] = r13
   out[14] = r14
   out[15] = r15
   return out
end

function M.mat4_translation(out, x, y, z)
   require_mat4(out, "out")
   write_identity(out)
   out[12] = x or 0.0
   out[13] = y or 0.0
   out[14] = z or 0.0
   return out
end

function M.mat4_scale(out, x, y, z)
   require_mat4(out, "out")
   write_identity(out)
   out[0] = x or 1.0
   out[5] = y or 1.0
   out[10] = z or 1.0
   return out
end

function M.mat4_rotation_x(out, angle)
   require_mat4(out, "out")
   local c = math.cos(angle)
   local s = math.sin(angle)
   write_identity(out)
   out[5] = c
   out[6] = s
   out[9] = -s
   out[10] = c
   return out
end

function M.mat4_rotation_y(out, angle)
   require_mat4(out, "out")
   local c = math.cos(angle)
   local s = math.sin(angle)
   write_identity(out)
   out[0] = c
   out[2] = -s
   out[8] = s
   out[10] = c
   return out
end

function M.mat4_rotation_z(out, angle)
   require_mat4(out, "out")
   local c = math.cos(angle)
   local s = math.sin(angle)
   write_identity(out)
   out[0] = c
   out[1] = s
   out[4] = -s
   out[5] = c
   return out
end

function M.mat4_perspective_lh(out, fov_y, aspect, near_z, far_z)
   require_mat4(out, "out")
   local y_scale = 1.0 / math.tan(fov_y * 0.5)
   local x_scale = y_scale / aspect

   out[0] = x_scale
   out[1] = 0.0
   out[2] = 0.0
   out[3] = 0.0
   out[4] = 0.0
   out[5] = y_scale
   out[6] = 0.0
   out[7] = 0.0
   out[8] = 0.0
   out[9] = 0.0
   out[10] = far_z / (far_z - near_z)
   out[11] = 1.0
   out[12] = 0.0
   out[13] = 0.0
   out[14] = (-near_z * far_z) / (far_z - near_z)
   out[15] = 0.0
   return out
end

function M.mat4_perspective_rh(out, fov_y, aspect, near_z, far_z)
   require_mat4(out, "out")
   local y_scale = 1.0 / math.tan(fov_y * 0.5)
   local x_scale = y_scale / aspect

   out[0] = x_scale
   out[1] = 0.0
   out[2] = 0.0
   out[3] = 0.0
   out[4] = 0.0
   out[5] = y_scale
   out[6] = 0.0
   out[7] = 0.0
   out[8] = 0.0
   out[9] = 0.0
   out[10] = far_z / (near_z - far_z)
   out[11] = -1.0
   out[12] = 0.0
   out[13] = 0.0
   out[14] = (near_z * far_z) / (near_z - far_z)
   out[15] = 0.0
   return out
end

function M.mat4_look_at_lh(out, eye, target, up)
   require_mat4(out, "out")
   require_vec3(eye, "eye")
   require_vec3(target, "target")
   require_vec3(up, "up")

   local zx, zy, zz = normalize_components(
      target[0] - eye[0],
      target[1] - eye[1],
      target[2] - eye[2],
      "target - eye"
   )
   local xx, xy, xz = normalize_components(
      up[1] * zz - up[2] * zy,
      up[2] * zx - up[0] * zz,
      up[0] * zy - up[1] * zx,
      "cross(up, forward)"
   )
   local yx = zy * xz - zz * xy
   local yy = zz * xx - zx * xz
   local yz = zx * xy - zy * xx

   out[0] = xx
   out[1] = yx
   out[2] = zx
   out[3] = 0.0
   out[4] = xy
   out[5] = yy
   out[6] = zy
   out[7] = 0.0
   out[8] = xz
   out[9] = yz
   out[10] = zz
   out[11] = 0.0
   out[12] = -(xx * eye[0] + xy * eye[1] + xz * eye[2])
   out[13] = -(yx * eye[0] + yy * eye[1] + yz * eye[2])
   out[14] = -(zx * eye[0] + zy * eye[1] + zz * eye[2])
   out[15] = 1.0
   return out
end

function M.mat4_look_at_rh(out, eye, target, up)
   require_mat4(out, "out")
   require_vec3(eye, "eye")
   require_vec3(target, "target")
   require_vec3(up, "up")

   local zx, zy, zz = normalize_components(
      eye[0] - target[0],
      eye[1] - target[1],
      eye[2] - target[2],
      "eye - target"
   )
   local xx, xy, xz = normalize_components(
      up[1] * zz - up[2] * zy,
      up[2] * zx - up[0] * zz,
      up[0] * zy - up[1] * zx,
      "cross(up, forward)"
   )
   local yx = zy * xz - zz * xy
   local yy = zz * xx - zx * xz
   local yz = zx * xy - zy * xx

   out[0] = xx
   out[1] = yx
   out[2] = zx
   out[3] = 0.0
   out[4] = xy
   out[5] = yy
   out[6] = zy
   out[7] = 0.0
   out[8] = xz
   out[9] = yz
   out[10] = zz
   out[11] = 0.0
   out[12] = -(xx * eye[0] + xy * eye[1] + xz * eye[2])
   out[13] = -(yx * eye[0] + yy * eye[1] + yz * eye[2])
   out[14] = -(zx * eye[0] + zy * eye[1] + zz * eye[2])
   out[15] = 1.0
   return out
end

function M.vec3_set(out, x, y, z)
   require_vec3(out, "out")
   out[0] = x or 0.0
   out[1] = y or 0.0
   out[2] = z or 0.0
   return out
end

function M.vec3_copy(out, src)
   require_vec3(out, "out")
   require_vec3(src, "src")
   out[0] = src[0]
   out[1] = src[1]
   out[2] = src[2]
   return out
end

function M.vec3_dot(a, b)
   require_vec3(a, "a")
   require_vec3(b, "b")
   return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
end

function M.vec3_length_squared(v)
   require_vec3(v, "v")
   return M.vec3_dot(v, v)
end

function M.vec3_length(v)
   require_vec3(v, "v")
   return math.sqrt(M.vec3_length_squared(v))
end

function M.vec3_subtract(out, a, b)
   require_vec3(out, "out")
   require_vec3(a, "a")
   require_vec3(b, "b")
   out[0] = a[0] - b[0]
   out[1] = a[1] - b[1]
   out[2] = a[2] - b[2]
   return out
end

function M.vec3_cross(out, a, b)
   require_vec3(out, "out")
   require_vec3(a, "a")
   require_vec3(b, "b")
   local x = a[1] * b[2] - a[2] * b[1]
   local y = a[2] * b[0] - a[0] * b[2]
   local z = a[0] * b[1] - a[1] * b[0]
   out[0] = x
   out[1] = y
   out[2] = z
   return out
end

function M.vec3_normalize(out, v)
   require_vec3(out, "out")
   require_vec3(v, "v")
   local length = math.sqrt(M.vec3_dot(v, v))
   if length == 0.0 then
      out[0] = 0.0
      out[1] = 0.0
      out[2] = 0.0
      return out
   end
   local inv = 1.0 / length
   out[0] = v[0] * inv
   out[1] = v[1] * inv
   out[2] = v[2] * inv
   return out
end

return M

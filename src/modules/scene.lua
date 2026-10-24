local M = ... or {}

local animator = require("animator")
local app = require("app")
local mathx = require("mathx")
local rig = require("rig")
local runtime = require("runtime")

-- A scene node is a node in a transform tree. Children inherit the world
-- transform computed by combining their local matrix with their parent's world
-- matrix, so nested entities follow their parents.
local Node = rig.Class()
M.Node = Node

function Node:init()
   self.parent = nil
   self.children = {}
   self.motions = {}

   self.local_transform = mathx.mat4()
   self.local_matrix = mathx.mat4()
   mathx.mat4_identity(self.local_matrix)
   self.world_matrix = mathx.mat4()
   mathx.mat4_identity(self.world_matrix)
end

function Node:add_child(child)
   if child == nil then
      rig.raise("Node:add_child requires a child")
   end
   if child == self then
      rig.raise("Node:add_child cannot add a node to itself")
   end

   child.parent = self
   self.children[#self.children + 1] = child
   return child
end

function Node:remove_child(child)
   for i = #self.children, 1, -1 do
      if self.children[i] == child then
         table.remove(self.children, i)
         child.parent = nil
         return true
      end
   end
   return false
end

function Node:set_local_matrix(matrix)
   if matrix == nil then
      rig.raise("Node:set_local_matrix requires a matrix")
   end
   mathx.mat4_copy(self.local_matrix, matrix)
   return self.local_matrix
end

-- Attaches a transform contributor. Motions compose after the stored local
-- matrix, in insertion order: base * m1 * m2 * ...
function Node:add_motion(motion)
   if motion == nil or type(motion.contribute) ~= "function" then
      rig.raise("Node:add_motion requires a motion with a contribute method")
   end
   self.motions[#self.motions + 1] = motion
   return motion
end

function Node:remove_motion(motion)
   for i = #self.motions, 1, -1 do
      if self.motions[i] == motion then
         table.remove(self.motions, i)
         return true
      end
   end
   return false
end

function Node:clear_motions()
   self.motions = {}
   return self.motions
end

-- Produces the node's local transform: the stored base matrix with each
-- motion pre-multiplied in list order, so `local = m1 * m2 * ... * base`.
-- `frame` carries `{ time, dt, scene, surface }` so closed-form motions can
-- sample time and stateful ones can read accumulated behavior.
function Node:build_local(out, frame)
   mathx.mat4_copy(out, self.local_matrix)
   for i = #self.motions, 1, -1 do
      out = self.motions[i]:contribute(out, self, frame)
   end
   return out
end

-- Per-frame hook, called before the node's transform is computed.
function Node:step(surface, frame)
end

-- Draws this node's own content in world space. Subclasses override it.
function Node:draw_node(surface, world, frame)
end

function Node:render_children(surface, frame)
   if surface == nil then
      rig.raise("Node:render_children requires a surface")
   end

   for i = 1, #self.children do
      local child = self.children[i]
      if type(child.render_tree) == "function" then
         child:render_tree(surface, self.world_matrix, frame)
      elseif type(child.draw) == "function" then
         child:draw(surface, frame)
      end
   end
end

-- Draws this subtree: the node's world matrix is its parent's world matrix
-- combined with its local transform, then each child recurses with it.
function Node:render_tree(surface, parent_world, frame)
   self:step(surface, frame)
   self:build_local(self.local_transform, frame)
   mathx.mat4_multiply(self.world_matrix, parent_world, self.local_transform)
   self:draw_node(surface, self.world_matrix, frame)
   self:render_children(surface, frame)
end

-- Interface for a render scene: the root node of a transform tree, with a
-- camera. It sequences a frame as `begin_frame`, updates the shared
-- view/projection, renders its children, then `end_frame`.
--
-- Concrete implementations (`render.scene.impl` providers) subclass RenderScene
-- and specialize the backend hooks. The runtime selects the implementation from
-- the assembled composition, so user code only names the interface.
local RenderScene = rig.Class(Node)
M.RenderScene = RenderScene

local DEFAULT_CAMERA = {
   eye = { 0.0, 0.0, -4.5 },
   target = { 0.0, 0.0, 0.0 },
   up = { 0.0, 1.0, 0.0 },
   fov_degrees = 60.0,
   near = 0.1,
   far = 100.0,
}

local function normalize_camera(camera)
   camera = camera or {}
   return {
      eye = camera.eye or DEFAULT_CAMERA.eye,
      target = camera.target or DEFAULT_CAMERA.target,
      up = camera.up or DEFAULT_CAMERA.up,
      fov_degrees = camera.fov_degrees or DEFAULT_CAMERA.fov_degrees,
      near = camera.near or DEFAULT_CAMERA.near,
      far = camera.far or DEFAULT_CAMERA.far,
   }
end

function RenderScene:init(options)
   self:super().init(self)
   options = options or {}

   self.name = options.name
   self.graphics = options.graphics
   self.background_color = options.background_color
   -- Runtime adoption hook for backend resources created lazily after startup.
   self.adopt = options.adopt

   -- Unified animation clock. The scene is the single source of frame time;
   -- motions and per-frame callbacks sample the same `time`/`dt`.
   self.clock = options.clock
   self.on_update = options.on_update
   self.on_draw = options.on_draw
   self.on_overlay = options.on_overlay
   self.time = 0.0
   self.dt = 0.0
   self._last_time = self.clock ~= nil and self.clock:monotonic() or nil

   self.width = 1
   self.height = 1
   self:set_camera(options.camera)

   self._view = mathx.mat4()
   self._projection = mathx.mat4()
   self._view_projection = mathx.mat4()

   -- Immediate drawing state. `mesh_factory` is supplied when the composition
   -- also provides `render.mesh`; draw_mesh lazily creates and caches backend
   -- drawables from it. `target_factory` is supplied when the composition
   -- provides `render.target` and lets passes render offscreen.
   self.mesh_factory = options.mesh_factory
   self.target_factory = options.target_factory
   self._drawables = setmetatable({}, { __mode = "k" })
   self.transform_stack = { mathx.mat4() }
   mathx.mat4_identity(self.transform_stack[1])
   self._draw_world = mathx.mat4()
   self._draw_mvp = mathx.mat4()

   self:update_view_projection()
end

-- Advances the frame clock and returns the new scene time in seconds. Without a
-- clock the scene stays frozen at time 0 (useful for stills and tests).
function RenderScene:advance_time()
   local clock = self.clock
   if clock == nil then
      self.dt = 0.0
      return self.time
   end

   local now = clock:monotonic()
   if self._last_time ~= nil then
      local dt = now - self._last_time
      if dt < 0.0 then
         dt = 0.0
      end
      self.dt = dt
   else
      self.dt = 0.0
   end
   self._last_time = now
   self.time = self.time + self.dt
   return self.time
end

-- The frame context handed to motions, behaviors, and callbacks.
function RenderScene:frame()
   return {
      scene = self,
      surface = self,
      time = self.time,
      dt = self.dt,
   }
end

function RenderScene:set_camera(camera)
   self.camera = normalize_camera(camera)
   self._eye = mathx.vec3(
      self.camera.eye[1],
      self.camera.eye[2],
      self.camera.eye[3]
   )
   self._target = mathx.vec3(
      self.camera.target[1],
      self.camera.target[2],
      self.camera.target[3]
   )
   self._up = mathx.vec3(
      self.camera.up[1],
      self.camera.up[2],
      self.camera.up[3]
   )
   return self.camera
end

-- Recomputes the shared view*projection matrix for the current viewport. The
-- scene calls this once per frame, after begin_frame has set width/height.
function RenderScene:update_view_projection()
   local width = self.width
   local height = self.height
   if width == nil or width <= 0 or height == nil or height <= 0 then
      width, height = 1, 1
   end

   mathx.mat4_look_at_lh(self._view, self._eye, self._target, self._up)
   mathx.mat4_perspective_lh(
      self._projection,
      math.rad(self.camera.fov_degrees),
      width / height,
      self.camera.near,
      self.camera.far
   )
   return mathx.mat4_multiply(self._view_projection, self._view, self._projection)
end

-- The view*projection matrix drawables combine with their world matrix.
function RenderScene:view_projection()
   return self._view_projection
end

-- Pushes a world transform for immediate draws. With a matrix argument the new
-- top is `current * matrix` (a child of the current transform); without one it
-- duplicates the current transform.
function RenderScene:push_transform(matrix)
   local current = self.transform_stack[#self.transform_stack]
   local next_transform = mathx.mat4()
   if matrix ~= nil then
      mathx.mat4_multiply(next_transform, current, matrix)
   else
      mathx.mat4_copy(next_transform, current)
   end
   self.transform_stack[#self.transform_stack + 1] = next_transform
   return next_transform
end

function RenderScene:pop_transform()
   if #self.transform_stack <= 1 then
      rig.raise("RenderScene:pop_transform underflow")
   end
   return table.remove(self.transform_stack)
end

-- The current world transform used by immediate draws.
function RenderScene:current_transform()
   return self.transform_stack[#self.transform_stack]
end

-- Lazily creates and caches the backend drawable for a mesh, keyed by mesh and
-- material (nil selects the backend's built-in material).
function RenderScene:mesh_drawable(mesh, material)
   if self.mesh_factory == nil then
      rig.raise("RenderScene:draw_mesh requires a render.mesh factory")
   end

   local by_material = self._drawables[mesh]
   if by_material == nil then
      by_material = {}
      self._drawables[mesh] = by_material
   end

   local key = material or false
   local drawable = by_material[key]
   if drawable == nil then
      drawable = self.mesh_factory.create(mesh, material)
      by_material[key] = drawable
   end
   return drawable
end

-- Immediately draws `mesh` with `world = current_transform * transform` and the
-- scene's view/projection. Must run while the backend frame is open, for example
-- from an `on_draw` hook. `transform` and `material` are optional.
function RenderScene:draw_mesh(mesh, transform, material)
   local drawable = self:mesh_drawable(mesh, material)
   local world = self.transform_stack[#self.transform_stack]
   if transform ~= nil then
      mathx.mat4_multiply(self._draw_world, world, transform)
      world = self._draw_world
   end
   mathx.mat4_multiply(self._draw_mvp, world, self:view_projection())
   drawable:draw(self, self._draw_mvp)
   return self
end

-- Flips the clip-space Y of a view/projection so a backend that stores
-- offscreen textures bottom-up (OpenGL) produces top-down results, matching how
-- imported images are sampled.
local function flip_clip_y(matrix)
   -- Row-vector points (`p * M`) read column 1 for clip-space Y.
   matrix[1] = -matrix[1]
   matrix[5] = -matrix[5]
   matrix[9] = -matrix[9]
   matrix[13] = -matrix[13]
   return matrix
end

-- Draws a material over the whole viewport, ignoring the camera. Used to feed a
-- render target into a shader as the final screen-space pass. `material` should
-- sample the optional target's texture (the built-in textured material does).
function RenderScene:draw_fullscreen(material)
   if self._fullscreen_quad == nil then
      local mesh = require("mesh")
      self._fullscreen_quad = mesh.make_fullscreen_quad()
   end

   local drawable = self:mesh_drawable(self._fullscreen_quad, material)
   mathx.mat4_identity(self._draw_mvp)
   drawable:draw(self, self._draw_mvp)
   return self
end

-- Maps a unit quad centered at the origin to the pixel rectangle
-- `(x, y, width, height)` (top-left origin, y down) and then to clip space. The
-- result lands at clip z = 0, so an overlay drawn last passes the depth test.
local function build_screen_matrix(out, x, y, width, height, view_width, view_height)
   local vx = view_width > 0 and view_width or 1
   local vy = view_height > 0 and view_height or 1
   mathx.mat4_identity(out)
   out[0] = width * (2.0 / vx)
   out[5] = height * (-2.0 / vy)
   out[12] = (x + width * 0.5) * (2.0 / vx) - 1.0
   out[13] = 1.0 - (y + height * 0.5) * (2.0 / vy)
   return out
end

-- Immediately draws `mesh` (typically a unit-sized `mesh.make_quad`) into a
-- screen-space rectangle. Use it for overlays and HUDs, ideally from an
-- `on_overlay` hook so it lands on top of the scene.
function RenderScene:draw_screen(mesh, x, y, width, height, material)
   local drawable = self:mesh_drawable(mesh, material)
   build_screen_matrix(self._draw_mvp, x, y, width, height, self.width, self.height)
   drawable:draw(self, self._draw_mvp)
   return self
end

-- Renders `draw(frame)` into `target` (a `render.target` value) as an offscreen
-- pass, then restores the window target and camera. The target's texture is
-- sampled afterwards, for example by `draw_fullscreen`. Backend scenes override
-- `enter_target`/`leave_target` to switch surfaces.
function RenderScene:render_to(target, draw)
   if self.target_factory == nil then
      rig.raise("RenderScene:render_to requires a render.target factory")
   end
   if type(draw) ~= "function" then
      rig.raise("RenderScene:render_to expects a draw function")
   end

   local handle = self.target_factory.create(target)
   local previous_width, previous_height = self.width, self.height

   self:enter_target(handle)
   self.width = handle.width
   self.height = handle.height
   self:update_view_projection()
   if handle.flip_v then
      flip_clip_y(self._view_projection)
   end

   local ok, err = pcall(draw, self:frame())

   self.width = previous_width
   self.height = previous_height
   self:update_view_projection()
   self:leave_target(handle)

   if not ok then
      error(err, 0)
   end
   return handle
end

-- Backend hooks for `render_to`; the base scene has no offscreen surface.
function RenderScene:enter_target(handle)
end

function RenderScene:leave_target(handle)
end

function RenderScene:begin_frame(...)
end

function RenderScene:end_frame(...)
end

function RenderScene:render(...)
   self:advance_time()
   local frame = self:frame()

   if self.on_update ~= nil then
      self.on_update(frame)
   end

   self:begin_frame(...)
   self:update_view_projection()

   if self.on_draw ~= nil then
      self.on_draw(frame)
   end
   self:render_children(self, frame)

   if self.on_overlay ~= nil then
      self.on_overlay(frame)
   end

   self:end_frame(...)
   return frame
end

M.plugin = function(spec)
   spec = spec or {}
   return runtime.plugin {
      id = spec.id or "scene",
      capabilities = {
         ["render.scene"] = {},
         ["render.scene.impl"] = {},
         ["render.mesh"] = {},
         ["render.target"] = {},
         ["sched.clock"] = {},
      },
   }
end

-- Composes a render scene from the assembled runtime.
--
-- Without `options.scene_class` the compiler resolves a `render.scene.impl`
-- provider (for example the implementation shipped beside the active graphics
-- backend) and instantiates it. Providing `scene_class` pins a specific class
-- and skips implementation resolution.
M.container_component = function(plugin, options)
   options = options or {}
   local scene_class = options.scene_class
   if scene_class ~= nil and not rig.is_class(scene_class) then
      rig.raise("scene.container_component options.scene_class must be a class")
   end

   local requires = {
      { capability = "graphics.context" },
      { capability = "sched.clock", optional = true },
   }
   if options.backend ~= nil then
      requires[1].properties = { backend = options.backend }
   end

   local mesh_requirement = { capability = "render.mesh", optional = true }
   if options.backend ~= nil then
      mesh_requirement.properties = { backend = options.backend }
   end
   requires[#requires + 1] = mesh_requirement

   local target_requirement = { capability = "render.target", optional = true }
   if options.backend ~= nil then
      target_requirement.properties = { backend = options.backend }
   end
   requires[#requires + 1] = target_requirement
   if scene_class == nil then
      local impl_requirement = { capability = "render.scene.impl" }
      if options.backend ~= nil then
         impl_requirement.properties = { backend = options.backend }
      end
      requires[#requires + 1] = impl_requirement
   end

   return runtime.descriptor(plugin, {
      name = options.name,
      provides = {
         { capability = "render.scene" },
      },
      requires = requires,
      create = function(context)
         local resolved = scene_class or context:capability("render.scene.impl")
         if not rig.is_class(resolved) then
            rig.raise(
               "render.scene.impl provider must be a RenderScene class"
            )
         end

         return resolved {
            name = options.name,
            graphics = context:capability("graphics.context"),
            background_color = options.background_color,
            camera = options.camera,
            clock = context:capability("sched.clock"),
            mesh_factory = context:capability("render.mesh"),
            target_factory = context:capability("render.target"),
            on_update = options.on_update,
            on_draw = options.on_draw,
            on_overlay = options.on_overlay,
            adopt = context.adopt,
         }
      end,
   })
end

--[ scene app ]--

-- `scene.SceneApp` is the scene-oriented application base. It composes the
-- generic application conveniences (`app.App`) with the scene animation
-- lifecycle (`animator.App`). It extends `app.App` and calls the `animator.App`
-- lifecycle methods directly so the single-inheritance chain stays rooted at
-- `app.App`.
local SceneApp = rig.Class(app.App)
M.SceneApp = SceneApp

SceneApp.app_name = "scene"
SceneApp.config_namespace = "app"
SceneApp.scope_label = "scene app resources"

SceneApp.create_scene_animator = animator.App.create_scene_animator
SceneApp.create_root = animator.App.create_root
SceneApp.release = animator.App.release

function SceneApp:init(context)
   animator.App.init(self, context)
   self:super().init(self, context)
end

function SceneApp:after_setup()
   animator.App.after_setup(self)
   self:super().after_setup(self)
end

function SceneApp:before_frame()
   animator.App.before_frame(self)
   self:super().before_frame(self)
end

function SceneApp:before_shutdown()
   local ok, err = pcall(function()
      animator.App.before_shutdown(self)
   end)
   self:super().before_shutdown(self)
   if not ok then
      rig.raise(err)
   end
end

return M
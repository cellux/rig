local rig, core = ...

rig.callbacks = rig.callbacks or {}

rig.print = core.print
rig.println = core.println
rig.clear = core.clear
rig.loop = core.loop

function rig.on_key(callback)
   rig.callbacks["key"] = callback
end

function rig.on_render(callback)
   rig.callbacks["render"] = callback
end

rig.on_render(function()
   rig.clear(0, 0, 0, 1)
end)

core.on_key = rig.on_key
core.on_render = rig.on_render

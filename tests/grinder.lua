-- Run from the mod root: lua tests/grinder.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}

local drawn, draws = nil, 0
rendering = {draw_animation = function(options)
  drawn = options
  draws = draws + 1
  local object = {valid = true, target = options.target, orientation = options.orientation, render_layer = options.render_layer, animation_speed = options.animation_speed}
  object.destroy = function() object.valid = false end
  return object
end}

local shared = require("shared")
-- The corridor must span from the nose (3.0) past the drill tip so no obstacle can hide in front of it.
assert(shared.layer.grinder_offset[2] == 3.0, "grinding corridor must start at the nose")
assert(shared.layer.grinder_offset[2] + shared.layer.grind_reach > shared.layer.grinder_visual_offset[2], "corridor must reach past the drill centre")
local animations = {}
data = {extend = function(_, entries) for _, entry in ipairs(entries) do animations[entry.name] = entry end end}
require("prototypes.overlays")
assert(animations[shared.grinder_animation].scale == 0.8, "drill must render at twice its original size")
local layer = require("lib.layer")
layer.on_init()
local loco = {valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0, surface = {}}
loco.train = {speed = 0.1, locomotives = {front_movers = {loco}}, passengers = {}}
layer.events[events.script_raised_built]{entity = loco}
local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

for _, case in ipairs{
  {orientation = 0, x = 0, y = -4.2, drill = 0.5},
  {orientation = 0.25, x = 4.2, y = 0, drill = 0.75},
  {orientation = 0.5, x = 0, y = 4.2, drill = 0},
  {orientation = 0.75, x = -4.2, y = 0, drill = 0.25}
} do
  loco.orientation = case.orientation
  layer.events[events.on_tick]{tick = 1}
  local object = storage.layer.locos[1].grinder
  assert(object.target.entity == loco)
  near(object.target.offset.x, case.x)
  near(object.target.offset.y, case.y)
  near(object.orientation, case.drill)
  assert(object.render_layer == "higher-object-above")
  assert(draws == 1, "turning should reuse the existing render object")
  -- A render object loaded from an older save must also acquire the new layer.
  object.render_layer = "object"
end
assert(drawn.orientation == 0.5, "new animations must start facing the nose")
local grinder = storage.layer.locos[1].grinder
assert(grinder.animation_speed == 0.5, "pushing spins the drill")
loco.train.speed = 0
layer.events[events.on_tick]{tick = 1}
assert(storage.layer.locos[1].grinder == grinder and grinder.valid, "stopping must not hide the drill")
assert(grinder.animation_speed == 0, "a stopped drill freezes instead of hiding")
loco.train.speed = 0.1
layer.events[events.on_tick]{tick = 1}
assert(draws == 1 and grinder.animation_speed == 0.5, "moving again must restart the same drill")
print("PASS: drill position, facing and layer in all cardinals, spin gating without hide/show")

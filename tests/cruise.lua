-- Run from the mod root: lua tests/cruise.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed", "on_train_created", "on_robot_pre_mined"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  riding = {acceleration = {nothing = 0, accelerating = 1, braking = 2, reversing = 3}},
  events = events
}
storage = {}
local handlers = {}
script = {
  get_event_id = function(name) return name end,
  on_event = function(id, handler) handlers[id] = handler end,
  register_on_object_destroyed = function() return 1 end
}
rendering = {draw_animation = function(options)
  local object = {valid = true, target = options.target, orientation = options.orientation, render_layer = options.render_layer, animation_speed = options.animation_speed}
  object.destroy = function() object.valid = false end
  return object
end}

local players = {}
game = {get_player = function(index) return players[index] end}

local shared = require("shared")

prototypes = {}
data = {extend = function(_, entries) for _, entry in ipairs(entries) do prototypes[entry.name] = entry end end}
require("settings")
assert(prototypes[shared.setting_cruise_speed].setting_type == "runtime-per-user", "cruise speed is a per-player runtime setting")
assert(prototypes[shared.setting_cruise_speed].default_value == shared.layer.cruise_speed, "setting default tracks the shared constant")
assert(prototypes[shared.setting_cruise_speed].minimum_value == 0.1)
assert(prototypes[shared.setting_cruise_speed].maximum_value == 0.6)
assert(shared.layer.cruise_speed == 0.3, "default cruise throttle doubled toward FARL parity")

settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}, get_player_settings = function() return {} end}
prototypes.item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}}
local layer = require("lib.layer")
layer.on_init()

local rider = {
  riding_state = {acceleration = defines.riding.acceleration.nothing},
  mod_settings = {[shared.setting_cruise_speed] = {value = 0.42}},
  create_local_flying_text = function() end
}
players[1] = rider

local function loco(unit_number, passengers)
  local entity = {
    valid = true, name = shared.layer_locomotive, unit_number = unit_number, orientation = 0,
    position = {x = 0, y = 0}, surface = {}, force = {print = function() end}
  }
  entity.train = {
    speed = 0, manual_mode = true,
    locomotives = {front_movers = {entity}},
    passengers = passengers,
    carriages = {entity}
  }
  return entity
end

local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

local tick = function() layer.events[events.on_tick]{tick = 1} end

-- A riding player's setting drives the throttle.
local engine = loco(1, {rider})
rider.vehicle = engine
layer.events[events.script_raised_built]{entity = engine}
handlers[shared.custom_input_cruise]{player_index = 1}
local record = storage.layer.locos[1]
assert(record.cruise and record.player_index == 1, "cruise on, toggler owns the driverless config")
tick()
near(engine.train.speed, 0.42)

-- Driverless, the player who toggled still owns the speed.
engine.train.passengers = {}
engine.train.speed = 0
tick()
near(engine.train.speed, 0.42)

-- Nobody ever did: the consist falls back to the shared default.
record.player_index = nil
engine.train.speed = 0
tick()
near(engine.train.speed, shared.layer.cruise_speed)

-- A passenger braking keeps the throttle for that tick.
engine.train.passengers = {{riding_state = {acceleration = defines.riding.acceleration.braking}, mod_settings = {}}}
engine.train.speed = 0
tick()
near(engine.train.speed, 0)

-- A builder's setting drives a consist that never saw a cruise toggle.
local placed = loco(2, {})
layer.events[events.on_built_entity]{entity = placed, player_index = 1}
storage.layer.locos[2].cruise = true
tick()
near(placed.train.speed, 0.42)

print("PASS: cruise throttle applies the rider's, the toggler's, the builder's, then the shared default speed")

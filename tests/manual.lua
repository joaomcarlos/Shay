-- Run from the mod root: lua tests/manual.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "on_train_created", "script_raised_destroy", "on_robot_pre_mined", "on_object_destroyed"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  events = events
}
storage = {}
local handlers = {}
script = {
  get_event_id = function(name) return name end,
  on_event = function(id, handler) handlers[id] = handler end,
  register_on_object_destroyed = function() return 1 end
}

local shared = require("shared")
local inputs = {}
data = {extend = function(_, entries) for _, entry in ipairs(entries) do inputs[entry.name] = entry end end}
require("prototypes.inputs")
assert(inputs[shared.custom_input_manual].key_sequence == "J", "manual toggle rides the J key")

settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {
  item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}},
  entity = {
    ["rail-signal"] = {collision_box = {left_top = {x = -0.2, y = -0.2}, right_bottom = {x = 0.2, y = 0.2}}},
    ["medium-electric-pole"] = {collision_box = {left_top = {x = -0.15, y = -0.15}, right_bottom = {x = 0.15, y = 0.15}}}
  }
}
local layer = require("lib.layer")
layer.on_init()
assert(handlers[shared.custom_input_manual], "the toggle handler must register on init")

local prints = {}
local force = {print = function(message) prints[#prints + 1] = message end}
local schedule = {group = "player-group", set_interrupts = function() end}
local train = {
  manual_mode = false,
  passengers = {},
  locomotives = {front_movers = {}},
  get_schedule = function() return schedule end
}
local loco = {valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0, position = {x = 0, y = 0}, force = force}
loco.train = train
train.carriages = {loco}
train.locomotives.front_movers = {loco}
layer.events[events.script_raised_built]{entity = loco}

local player = {vehicle = loco, force = force}
game = {get_player = function() return player end}
local press = function() handlers[shared.custom_input_manual]{player_index = 1} end

press()
assert(train.manual_mode == true, "J on an automatic Shay consist goes manual")
assert(prints[1][1] == "shay-message.manual-on", "going manual announces itself")
press()
assert(train.manual_mode == false, "J again hands the train back to the schedule")
assert(prints[2][1] == "shay-message.manual-off", "going automatic announces itself")

player.vehicle = {train = {manual_mode = false, carriages = {}}}
press()
assert(#prints == 2 and player.vehicle.train.manual_mode == false, "a non-Shay train ignores J")
player.vehicle = nil
press()
assert(#prints == 2, "on foot ignores J")

-- Mid-resupply the consist runs automatic on a parked schedule: J is a manual
-- takeover, so it cancels the trip instead of toggling the mode under it.
player.vehicle = loco
storage.layer.locos[1].resupply = {saved = {records = nil, current = 1, interrupts = {}, group = nil}}
press()
assert(storage.layer.locos[1].resupply == nil, "J during resupply cancels the trip")
assert(train.manual_mode == true, "cancel leaves the train in manual control")
assert(train.schedule == nil and schedule.group == nil, "cancel restores the parked schedule")
assert(prints[3][1] == "shay-message.resupply-cancelled", "cancel uses the takeover message")

print("PASS: J toggles manual mode on Shay consists only, and cancels an active resupply")

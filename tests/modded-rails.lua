-- Run from the mod root: lua tests/modded-rails.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "on_train_created", "script_raised_destroy", "on_object_destroyed",
  "on_robot_pre_mined"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = 1},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
local raised = {}
script.raise_event = function(id, data) raised[#raised + 1] = {id = id, data = data} end
local function clear(table_)
  for key in pairs(table_) do table_[key] = nil end
end
rendering = {draw_animation = function(options)
  local object = {valid = true}
  object.destroy = function() object.valid = false end
  return object
end}
helpers = {is_valid_sound_path = function() return false end}

local shared = require("shared")
settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {
  item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}},
  entity = {
    ["rail-signal"] = {collision_box = {left_top = {x = -0.2, y = -0.2}, right_bottom = {x = 0.2, y = 0.2}}},
    ["medium-electric-pole"] = {collision_box = {left_top = {x = -0.15, y = -0.15}, right_bottom = {x = 0.15, y = 0.15}}}
  }
}

-- Data-stage validation: the item must exist and place a straight-rail prototype.
local function check_setting(item_name)
  settings.startup[shared.rail_item_setting].value = item_name
  data = {raw = {
    item = {
      rail = {place_result = "straight-rail"},
      ["hl-rail"] = {place_result = "hl-straight-rail"},
      fake = {place_result = "stone-wall"}
    },
    ["straight-rail"] = {["straight-rail"] = {}, ["hl-straight-rail"] = {}}
  }}
  return pcall(dofile, "data-final-fixes.lua")
end
assert(check_setting("rail"), "vanilla rail must pass data-stage validation")
assert(check_setting("hl-rail"), "a modded item placing a straight rail must pass")
local ok, err = check_setting("bogus")
assert(not ok and err:find("straight rail"), "an unknown item must fail the mod load")
ok, err = check_setting("fake")
assert(not ok and err:find("straight rail"), "an item not placing a straight rail must fail")

local layer = require("lib.layer")

-- Runtime resolution fails the same way if data-stage validation is bypassed.
settings.startup[shared.rail_item_setting].value = "fake"
prototypes.item.fake = {place_result = {name = "stone-wall", type = "wall"}}
ok, err = pcall(layer.on_init)
assert(not ok and err:find("straight rail"), "a non-rail place_result must fail on_init")

-- A modded rail item resolves to its own entity: the consist consumes it and places that entity.
settings.startup[shared.rail_item_setting].value = "hl-rail"
prototypes.item["hl-rail"] = {place_result = {name = "hl-straight-rail", type = "straight-rail"}}
layer.on_init()

local loco = {
  valid = true, name = shared.layer_locomotive, unit_number = 1,
  orientation = 0, position = {x = 0, y = 0}, surface = {},
  force = {print = function() end}
}
local counts = {["hl-rail"] = 500, landfill = 500, ["cliff-explosives"] = 500, concrete = 500, ["rail-signal"] = 50, ["medium-electric-pole"] = 50}
local inventory = {
  remove = function(t) if (counts[t.name] or 0) >= t.count then counts[t.name] = counts[t.name] - t.count return t.count end return 0 end,
  insert = function(t) counts[t.name] = (counts[t.name] or 0) + t.count return t.count end,
  get_item_count = function(t) return counts[t.name] or 0 end
}
loco.train = {
  speed = 0.1, manual_mode = true, carriages = {loco},
  locomotives = {front_movers = {loco}}, passengers = {},
  cargo_wagons = {{get_inventory = function() return inventory end}}
}
layer.events[events.script_raised_built]{entity = loco}

local surface = loco.surface
local frontier = {position = {x = 0, y = -4}, direction = 0, valid = true}
local cell, placed, checked = {}, nil, {}
surface.get_tile = function() return {name = "grass-1"} end
surface.find_entities_filtered = function(args)
  if args.radius then return {frontier} end
  if args.area then return cell end
  return {}
end
surface.find_tiles_filtered = function() return {} end
local place_checks = 0
surface.set_tiles = function() end
surface.can_place_entity = function(args)
  checked[#checked + 1] = args.name
  place_checks = place_checks + 1
  return place_checks > 1
end
surface.play_sound = function() end
surface.create_entity = function(args)
  placed = args
  return {position = args.position, valid = true}
end
local function new_rock()
  local rock = {
    name = "big-rock", type = "rock", destructible = true, valid = true,
    position = {x = 0, y = -6}, prototype = {mineable_properties = {products = {}}}
  }
  rock.die = function() rock.valid = false rock.died = true end
  rock.destroy = function() rock.valid = false rock.destroyed = true end
  return rock
end

place_checks = 0
local rock = new_rock()
cell = {rock}
layer.events[events.on_tick]{tick = 5}
assert(placed and placed.name == "hl-straight-rail", "must place the modded rail's entity, not straight-rail")
assert(checked[1] == "hl-straight-rail", "collision checks must use the modded rail entity")
assert(counts["hl-rail"] == 497 and not counts.rail, "the modded rail item is what the consist consumes")
assert(rock.died and #raised == 0, "unregistered entities are ground without a pre-mined event")

-- remote.call("shay", "add_entity_to_trigger", name) marks names whose destruction raises on_robot_pre_mined.
assert(layer.remote.add_entity_to_trigger("big-rock") == nil, "unknown prototype names must not register")
prototypes.entity["big-rock"] = {}
assert(layer.remote.add_entity_to_trigger("big-rock") == true)
assert(layer.remote.get_trigger_list()["big-rock"], "list must report the registration")
place_checks = 0
clear(raised)
rock = new_rock()
cell = {rock}
layer.events[events.on_tick]{tick = 10}
assert(#raised == 1 and raised[1].id == events.on_robot_pre_mined, "grinding a registered entity raises pre-mined")
assert(raised[1].data.entity == rock)
assert(rock.died, "the raise must not skip the destruction")

-- Registrations survive on_load through storage.layer.triggers.
layer.on_load()
assert(layer.remote.get_trigger_list()["big-rock"], "on_load keeps the persisted trigger list")

assert(layer.remote.remove_entity_from_trigger("never-added") == nil, "removing a missing name is a no-op")
assert(layer.remote.remove_entity_from_trigger("big-rock") == true)
assert(layer.remote.get_trigger_list()["big-rock"] == nil, "removal clears the registration")

-- Loading a save from before triggers existed must not change storage.
storage.layer.triggers = nil
package.loaded["lib.layer"] = nil
layer = require("lib.layer")
layer.on_load()
assert(storage.layer.triggers == nil, "on_load must not create fields in storage")
assert(next(layer.remote.get_trigger_list()) == nil, "saves without a trigger list get an empty local one")
assert(layer.remote.add_entity_to_trigger("big-rock") == true)
local loaded_triggers = layer.remote.get_trigger_list()
assert(layer.remote.remove_entity_from_trigger("big-rock") == true)

place_checks = 0
clear(raised)
cell = {new_rock()}
layer.events[events.on_tick]{tick = 15}
assert(storage.layer.triggers == loaded_triggers, "the first tick persists the trigger list")
assert(#raised == 0, "a removed name stops raising pre-mined")

print("PASS: modded rail item resolves, is consumed and places its own straight rail")
print("PASS: trigger remote interface gates on_robot_pre_mined on the grinder")

-- Run from the mod root: lua tests/cliff.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_train_created", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = "cargo_wagon"},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
helpers = {is_valid_sound_path = function() return false end}
rendering = {draw_animation = function(options)
  local object = {valid = true, target = options.target, orientation = options.orientation, render_layer = options.render_layer, animation_speed = options.animation_speed}
  object.destroy = function() object.valid = false end
  return object
end}

local shared = require("shared")
settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {
  item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}},
  entity = {
    ["rail-signal"] = {collision_box = {left_top = {x = -0.2, y = -0.2}, right_bottom = {x = 0.2, y = 0.2}}},
    ["medium-electric-pole"] = {collision_box = {left_top = {x = -0.15, y = -0.15}, right_bottom = {x = 0.15, y = 0.15}}}
  }
}
local layer = require("lib.layer")

-- Northbound loco at the origin: the frontier rail sits at {0, -8}, so the next
-- 2x2 cell lands on {0, -10} where the cliff (and a grindable tree) stands.
local function make_world(items, with_tree)
  local world = {items = items, messages = {}, created = {}, schedule_reads = 0}
  local cliff = {valid = true, type = "cliff", name = "cliff", destructible = false, position = {x = 0, y = -10}}
  cliff.destroy = function(options)
    cliff.destroy_options = options
    cliff.valid = false
    return true
  end
  local tree = {valid = true, type = "tree", name = "tree-01", destructible = true, position = {x = 0, y = -10}, prototype = {mineable_properties = {products = {}}}}
  tree.die = function() tree.valid = false end
  world.cliff, world.tree = cliff, tree
  local footprint = with_tree and {tree, cliff} or {cliff}

  local inventory = {
    get_item_count = function(filter) return items[filter.name] or 0 end,
    insert = function(item) items[item.name] = (items[item.name] or 0) + item.count return item.count end,
    remove = function(item)
      if (items[item.name] or 0) < item.count then return 0 end
      items[item.name] = items[item.name] - item.count
      return item.count
    end
  }
  local wagon = {get_inventory = function(which) assert(which == "cargo_wagon") return inventory end}

  local loco = {valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0, position = {x = 0, y = 0}}
  loco.force = {print = function(message) world.messages[#world.messages + 1] = message end}
  loco.train = {speed = 0.1, passengers = {}, carriages = {loco}, locomotives = {front_movers = {loco}}, cargo_wagons = {wagon}}
  loco.train.get_schedule = function()
    world.schedule_reads = world.schedule_reads + 1
    return {group = nil, current = 1, get_records = function() return {} end, get_interrupts = function() return {} end}
  end
  loco.surface = {
    get_tile = function() return {name = "grass-1", valid = true} end,
    find_tiles_filtered = function() return {} end,
    find_entities_filtered = function(options)
      if options.area then return footprint end
      return {{valid = true, type = "straight-rail", direction = 0, position = {x = 0, y = -8}}}
    end,
    can_place_entity = function() return not cliff.valid end,
    create_entity = function(options)
      local entity = {valid = true, name = options.name, position = options.position}
      world.created[#world.created + 1] = entity
      return entity
    end,
    play_sound = function() end,
    set_tiles = function() end
  }
  world.loco = loco
  return world
end

local function run(world, ticks)
  layer.on_init()
  layer.events[events.script_raised_built]{entity = world.loco}
  for _, tick in ipairs(ticks) do layer.events[events.on_tick]{tick = tick} end
end

-- Stocked: the cliff goes down like a player charge took it out, and the rail lands.
local stocked = make_world({rail = 20, landfill = 20, ["cliff-explosives"] = 10, concrete = 50, ["rail-signal"] = 50, ["medium-electric-pole"] = 50}, true)
run(stocked, {5})
assert(stocked.items["cliff-explosives"] == 9, "laying through a cliff spends one charge")
assert(not stocked.cliff.valid, "the cliff was destroyed")
assert(stocked.cliff.destroy_options.do_cliff_correction == true, "neighbouring cliffs get corrected")
assert(not stocked.tree.valid, "grindables in the footprint still get eaten")
assert(stocked.created[1] and stocked.created[1].name == "straight-rail", "the rail was laid")
assert(stocked.created[1].position.y == -10, "the rail landed on the cliff's cell")
assert(stocked.items.rail == 19, "the rail came out of the consist's cargo")
assert(stocked.schedule_reads == 0, "nothing was low, so no resupply was attempted")
assert(#stocked.messages == 0, "stocked explosives warn nobody")

-- Empty: the layer complains once per warn interval and stands still.
local empty = make_world({rail = 20, landfill = 20, ["cliff-explosives"] = 0})
run(empty, {5, 10})
assert(empty.schedule_reads > 0, "running dry tried the auto-resupply")
assert(empty.cliff.valid, "no charge, no cliff removal")
assert(#empty.created == 0, "no rail was laid")
assert(empty.items.rail == 20, "no rail item was spent")
assert(empty.messages[1][1] == "shay-message.out-of-cliff-explosives", "warned about the missing charges")
assert(empty.messages[2][1] == "shay-message.no-supply-station", "auto-resupply is on but no station exists")
assert(#empty.messages == 2, "the warning repeats only after the interval")

print("PASS: cliff removal spends one charge per cliff, warns once and halts when dry")

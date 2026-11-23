-- Run from the mod root: lua tests/parallel.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_train_created", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed",
  "on_robot_pre_mined"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = 1},
  riding = {acceleration = {nothing = 0, accelerating = 1, braking = 2, reversing = 3}},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
rendering = {draw_animation = function(options)
  local object = {valid = true, target = options.target, orientation = options.orientation, render_layer = options.render_layer, animation_speed = options.animation_speed}
  object.destroy = function() object.valid = false end
  return object
end}
helpers = {is_valid_sound_path = function() return false end}

local players = {}
game = {get_player = function(index) return players[index] end}

local shared = require("shared")

settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}}}

local prototypes = {}
data = {extend = function(_, entries) for _, entry in ipairs(entries) do prototypes[entry.name] = entry end end}
require("settings")
assert(prototypes[shared.setting_lanes].setting_type == "runtime-per-user", "lane count is a per-player runtime setting")
assert(prototypes[shared.setting_lanes].default_value == shared.layer.lanes, "lane default stays a single track")
assert(prototypes[shared.setting_lanes].minimum_value == 1)
assert(prototypes[shared.setting_lane_spacing].default_value == shared.layer.lane_spacing)

local layer = require("lib.layer")

-- A flat world: entities the scenario planted plus whatever the layer creates.
local function make_world()
  local world = {entities = {}, placed = {}}
  local surface = {}
  local function occupied(position)
    for _, entity in ipairs(world.entities) do
      if entity.valid and math.abs(entity.position.x - position.x) < 1 and math.abs(entity.position.y - position.y) < 1 then
        return true
      end
    end
    return false
  end
  surface.can_place_entity = function(options) return not occupied(options.position) end
  surface.find_entities_filtered = function(filter)
    local found = {}
    for _, entity in ipairs(world.entities) do
      if entity.valid then
        local match = true
        if filter.type then
          match = false
          for _, entity_type in ipairs(type(filter.type) == "table" and filter.type or {filter.type}) do
            if entity.type == entity_type then match = true break end
          end
        end
        if match and filter.position then
          local dx, dy = entity.position.x - filter.position.x, entity.position.y - filter.position.y
          match = dx * dx + dy * dy <= filter.radius * filter.radius
        end
        if match and filter.area then
          match = entity.position.x >= filter.area[1][1] and entity.position.x <= filter.area[2][1]
              and entity.position.y >= filter.area[1][2] and entity.position.y <= filter.area[2][2]
        end
        if match then found[#found + 1] = entity end
      end
    end
    return found
  end
  surface.find_tiles_filtered = function() return {} end
  surface.get_tile = function() return {name = "grass-1"} end
  surface.set_tiles = function() end
  surface.play_sound = function() end
  surface.create_entity = function(options)
    local entity = {
      valid = true, name = options.name, type = options.name, position = options.position,
      direction = options.direction, destructible = true,
      prototype = {mineable_properties = {products = {}}}
    }
    entity.die = function() entity.valid = false end
    entity.destroy = function() entity.valid = false end
    world.entities[#world.entities + 1] = entity
    world.placed[#world.placed + 1] = options
    return entity
  end
  return surface, world
end

local function planted_rail(x, y, direction)
  local entity = {
    valid = true, name = "straight-rail", type = "straight-rail", direction = direction,
    position = {x = x, y = y}, destructible = true,
    prototype = {mineable_properties = {products = {}}}
  }
  entity.die = function() entity.valid = false end
  entity.destroy = function() entity.valid = false end
  return entity
end

local function tree(x, y)
  local entity = {
    valid = true, name = "tree-01", type = "tree", destructible = true,
    position = {x = x, y = y},
    prototype = {mineable_properties = {products = {{type = "item", name = "wood", amount = 2}}}}
  }
  entity.die = function() entity.valid = false end
  entity.destroy = function() entity.valid = false end
  return entity
end

local function wagon(items)
  local inventory = {}
  inventory.remove = function(options)
    local have = items[options.name] or 0
    local taken = math.min(have, options.count)
    items[options.name] = have - taken
    return taken
  end
  inventory.insert = function(options)
    items[options.name] = (items[options.name] or 0) + options.count
    return options.count
  end
  inventory.get_item_count = function(options) return items[options.name] or 0 end
  return {get_inventory = function() return inventory end}
end

local function rider(lanes, spacing)
  return {
    riding_state = {acceleration = defines.riding.acceleration.nothing},
    mod_settings = {
      [shared.setting_lanes] = {value = lanes},
      [shared.setting_lane_spacing] = {value = spacing}
    }
  }
end

-- The consist heads north out of (0,0) onto a frontier rail at (0,-4): three rows fit the
-- lookahead, centred on y = -6, -8, -10. One lay tick runs per scenario.
local function scenario(options)
  options = options or {}
  layer.on_init()
  local surface, world = make_world()
  world.entities[#world.entities + 1] = planted_rail(0, -4, 0)
  for _, entity in ipairs(options.entities or {}) do world.entities[#world.entities + 1] = entity end
  local items = options.items or {rail = 40, landfill = 40, ["cliff-explosives"] = 40, concrete = 300}
  local printed = {}
  local loco = {
    valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0,
    position = {x = 0, y = 0},
    surface = surface, force = {print = function(message) printed[#printed + 1] = message end}
  }
  loco.train = {
    speed = 0.1, manual_mode = true,
    locomotives = {front_movers = {loco}},
    passengers = options.passenger and {options.passenger} or {},
    carriages = {loco},
    cargo_wagons = {wagon(items)}
  }
  layer.events[events.script_raised_built]{entity = loco}
  local record = storage.layer.locos[1]
  record.auto_resupply_off = options.auto_resupply_off
  record.player_index = options.player_index
  layer.events[events.on_tick]{tick = shared.layer.rail_lay_interval}
  return {world = world, record = record, printed = printed, items = items}
end

local function cell_set(world)
  local set = {}
  for _, options in ipairs(world.placed) do
    set[string.format("%.0f,%.0f", options.position.x, options.position.y)] = options
  end
  return set
end

-- Default: a driverless, untouched consist keeps the single main line.
local single = scenario()
assert(#single.world.placed == 3, "one lane lays the same three rails as before")
for _, options in ipairs(single.world.placed) do
  assert(options.position.x == 0 and options.direction == 0 and options.raise_built)
end
assert(single.items.rail == 37, "each laid rail consumes one item")

-- Three lanes at spacing 4: rows lay main, then right (+x), then left (-x).
local triple = scenario{passenger = rider(3, 4)}
assert(#triple.world.placed == 9, "three lanes lay a full row per step")
local cells = cell_set(triple.world)
for _, y in ipairs{-6, -8, -10} do
  for _, x in ipairs{-4, 0, 4} do
    local options = cells[x .. "," .. y]
    assert(options, "missing rail at " .. x .. "," .. y)
    assert(options.direction == 0 and options.raise_built, "lane rails share the main lane's direction and raise_built")
  end
end
assert(triple.world.placed[1].position.x == 0 and triple.world.placed[2].position.x == 4 and triple.world.placed[3].position.x == -4,
  "a row lays main lane first, then alternating sides")
assert(triple.items.rail == 31, "consumption matches laid rails")
assert(triple.record.last_rail.position.x == 0 and triple.record.last_rail.position.y == -10,
  "last_rail stays the main-lane frontier marker")
-- A second tick reaches the lookahead and stops instead of double-laying a row.
layer.events[events.on_tick]{tick = 2 * shared.layer.rail_lay_interval}
assert(#triple.world.placed == 9, "the laid rows themselves block any repeat")

-- A crossing line eats only the lane cells it physically occupies; the main lane goes on.
local cross_a, cross_b = planted_rail(4, -6, 4), planted_rail(4, -8, 4)
local crossed = scenario{passenger = rider(3, 4), entities = {cross_a, cross_b}}
assert(#crossed.world.placed == 7, "blocked lane cells are skipped, the row's other lanes still lay")
local crossed_cells = cell_set(crossed.world)
assert(not crossed_cells["4,-6"] and not crossed_cells["4,-8"], "never lay a lane over perpendicular track")
assert(crossed_cells["4,-10"], "the lane resumes once the crossing is past")
assert(cross_a.valid and cross_b.valid, "rail infrastructure is never eaten")
assert(crossed.items.rail == 33)

-- Out of rail mid-batch: the second row needs 3 but only 1 remains, so nothing of it lays.
local dry = scenario{passenger = rider(3, 4), items = {rail = 4, landfill = 40, ["cliff-explosives"] = 40, concrete = 300}, auto_resupply_off = true}
assert(#dry.world.placed == 3, "a short batch stops whole rather than half-laying a row")
assert(dry.items.rail == 1)
assert(dry.printed[1][1] == "shay-message.out-of-rail", "the batch warns on the way out")
assert(dry.printed[2][1] == "shay-message.no-supply-station")

-- The drill eats a lane's blocker in its exact cell, never anything outside it.
local inside, beside, ahead = tree(4, -6), tree(6, -6), tree(4, -4)
local ground = scenario{passenger = rider(2, 4), entities = {inside, beside, ahead}}
assert(#ground.world.placed == 6)
assert(not inside.valid, "the blocker in the lane cell is eaten")
assert(beside.valid and ahead.valid, "trees outside the exact 2x2 cell are never touched")
assert(ground.items.wood == 2, "mined products are stored in the consist")

-- Odd spacings snap down to an even rail distance; spacing 5 behaves as 4.
local odd = scenario{passenger = rider(3, 5)}
assert(#odd.world.placed == 9)
for _, options in ipairs(odd.world.placed) do
  assert(options.position.x ~= 5 and options.position.x ~= -5, "odd spacing never lands off the rail grid")
end

-- Driverless, the consist follows the last player to toggle cruise, resolved by index.
players[7] = rider(2, 4)
local driverless = scenario{player_index = 7}
assert(#driverless.world.placed == 6, "a parked consist uses the toggling player's lane settings")
players[7] = nil

print("PASS: parallel lanes place on the rail grid, consume per rail, skip blocked cells and stop whole on empty")

-- Run from the mod root: lua tests/trackside.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_train_created", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = 1},
  riding = {acceleration = {accelerating = 1, nothing = 0}},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
rendering = {draw_animation = function(options)
  local object = {valid = true, target = options.target}
  object.destroy = function() object.valid = false end
  return object
end}
helpers = {is_valid_sound_path = function() return false end}

local shared = require("shared")
local box = {left_top = {x = -0.2, y = -0.2}, right_bottom = {x = 0.2, y = 0.2}}
settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {
  item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}},
  entity = {
    ["rail-signal"] = {collision_box = {left_top = {x = -0.2, y = -0.2}, right_bottom = {x = 0.2, y = 0.2}}},
    ["medium-electric-pole"] = {collision_box = {left_top = {x = -0.15, y = -0.15}, right_bottom = {x = 0.15, y = 0.15}}}
  }
}
for _, spec in pairs(shared.trackside) do prototypes.entity[spec.entity] = {collision_box = box} end

local layer = require("lib.layer")

-- A flat world: one anchor rail under the nose, stock in a single wagon, blockers
-- standing in build cells until something destroys them.
local created, prints, blockers, stock
local force = {name = "player", print = function(message) prints[#prints + 1] = message end}
local schedule_data = {records = {}}

local wagon = {get_inventory = function() return {
  remove = function(query)
    if (stock[query.name] or 0) >= query.count then stock[query.name] = stock[query.name] - query.count return query.count end
    return 0
  end,
  insert = function() return 0 end,
  get_item_count = function(query) return stock[query.name] or 0 end
} end}

local surface = {}
surface.find_tiles_filtered = function() return {} end
surface.set_tiles = function() end
surface.get_tile = function() return {name = "grass-1"} end
surface.find_tiles_filtered = function() return {} end
surface.play_sound = function() end
surface.find_entities_filtered = function(query)
  if query.type == "straight-rail" then
    local rails = {{valid = true, name = "straight-rail", position = {x = 0, y = -3}, direction = 0}}
    for _, entry in pairs(created) do
      if entry.name == "straight-rail" then rails[#rails + 1] = {valid = true, name = "straight-rail", position = entry.position, direction = entry.direction} end
    end
    return rails
  end
  local hits = {}
  for _, entity in pairs(blockers) do
    local p = entity.position
    if entity.valid and p.x >= query.area[1][1] and p.x < query.area[2][1] and p.y >= query.area[1][2] and p.y < query.area[2][2] then hits[#hits + 1] = entity end
  end
  return hits
end
surface.can_place_entity = function(options)
  for _, entity in pairs(blockers) do
    local p = entity.position
    if entity.valid and math.abs(p.x - options.position.x) < 1 and math.abs(p.y - options.position.y) < 1 then return false end
  end
  return true
end
surface.create_entity = function(options)
  created[#created + 1] = options
  return {valid = true, name = options.name, position = options.position}
end

local loco = {valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0, position = {x = 0, y = 0}, surface = surface, force = force}
loco.train = {
  speed = 0.1, manual_mode = true, state = 0,
  locomotives = {front_movers = {loco}, back_movers = {}},
  cargo_wagons = {wagon}, passengers = {}, carriages = {loco, wagon},
  get_schedule = function() return {
    group = nil, current = 1,
    get_records = function() return schedule_data.records end,
    get_interrupts = function() return {} end,
    set_interrupts = function() end,
    clear_interrupts = function() end
  } end
}

local function blocker(position, name, blocker_force)
  local entity = {valid = true, destructible = true, name = name, type = "electric-pole", position = position,
    force = blocker_force, die_called = false, prototype = {mineable_properties = {products = {}}}}
  entity.die = function() entity.die_called = true end
  entity.destroy = function() entity.valid = false end
  return entity
end

local function reset()
  layer.on_init()
  layer.events[events.script_raised_built]{entity = loco}
  created, prints, blockers = {}, {}, {}
  loco.position = {x = 0, y = 0}
end

local function run(ticks)
  for i = 1, ticks do
    layer.events[events.on_tick]{tick = i * shared.layer.rail_lay_interval}
    -- The consist follows its own track: each tick's three new rails put the nose on the frontier.
    loco.position.y = loco.position.y - 6
  end
end

local function placements(name)
  local out = {}
  for _, entry in pairs(created) do if entry.name == name then out[#out + 1] = entry end end
  return out
end

local function at(entries, x, y)
  for _, entry in pairs(entries) do
    if entry.position.x == x and entry.position.y == y then return entry end
  end
end

local function warned(message)
  for _, entry in pairs(prints) do if entry[1] == message then return entry end end
end

local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

-- Stocked consist: signals on the right every 16 tiles, poles on the left every 8.
stock = {rail = 200, landfill = 50, ["rail-signal"] = 50, ["medium-electric-pole"] = 50}
reset()
run(6)
assert(#placements("straight-rail") == 18, "six ticks lay eighteen rails")
local signals, poles = placements("rail-signal"), placements("medium-electric-pole")
assert(#signals == 3, "a signal every 16 tiles")
assert(#poles == 5, "a pole every 8 tiles")
for _, spot in ipairs{{-5}, {-21}, {-37}} do
  local signal = at(signals, 1.5, spot[1])
  assert(signal, "signal missing at 1.5," .. spot[1])
  assert(signal.direction == 8, "right-side signal faces back down the line")
  assert(signal.force == force and signal.raise_built)
end
for _, y in ipairs{-5, -13, -21, -29, -37} do assert(at(poles, -1.5, y), "pole missing at -1.5," .. y) end
assert(stock["rail"] == 182 and stock["rail-signal"] == 47 and stock["medium-electric-pole"] == 45, "cargo paid for every placement")
assert(not warned("shay-message.out-of-trackside"), "no shortage warnings while stocked")

-- Out of signals: warn once per interval, keep laying rails and poles, resume on restock.
stock["rail-signal"] = 0
reset()
run(2)
assert(#placements("straight-rail") == 6, "rails still lay without signals")
assert(#placements("rail-signal") == 0, "no signal without stock")
assert(#placements("medium-electric-pole") == 2, "poles unaffected by missing signals")
assert(warned("shay-message.out-of-trackside")[2][1] == "item-name.rail-signal", "warning names the missing item")
assert(warned("shay-message.no-supply-station"), "no station warning while auto-resupply is live")
stock["rail-signal"] = 50
run(1)
assert(#placements("rail-signal") == 1, "signal laying resumes at the next rail once restocked")

-- A player pole in the build cell is never eaten: the spot is skipped, the chain retries.
local own = blocker({x = -1.5, y = -5}, "medium-electric-pole", force)
reset()
blockers = {own}
run(1)
assert(own.valid and not own.die_called, "player builds are never ground")
assert(not at(placements("medium-electric-pole"), -1.5, -5), "blocked spot is skipped")
assert(at(placements("medium-electric-pole"), -1.5, -7), "the next rail retries the skipped spot")

-- A tree in the cell is ground, then the pole goes down.
local tree = blocker({x = -1.5, y = -5}, "tree-01", {name = "neutral"})
tree.type = "tree"
reset()
blockers = {tree}
run(1)
assert(tree.die_called and not tree.valid, "nature in the cell is ground")
assert(at(placements("medium-electric-pole"), -1.5, -5), "pole follows the cleared cell")

-- Low trackside stock counts toward the auto-resupply like rail and landfill do.
stock["rail-signal"], stock["medium-electric-pole"] = 5, 5
schedule_data.records = {{station = "depot"}}
reset()
run(1)
local resupply = storage.layer.locos[1].resupply
assert(resupply and loco.train.manual_mode == false, "low trackside stock trips the resupply")
local needs = {}
for _, name in pairs(resupply.needs) do needs[name] = true end
assert(needs["rail-signal"] and needs["medium-electric-pole"] and not needs["rail"], "trip asks for exactly what is low")
local conditions = loco.train.schedule.records[1].wait_conditions
local waiting = {}
for _, condition in pairs(conditions) do
  if condition.type == "item_count" then waiting[condition.condition.first_signal.name] = condition.condition.constant end
end
assert(waiting["rail-signal"] == shared.supply.trackside_full and waiting["medium-electric-pole"] == shared.supply.trackside_full,
  "the station wait checks the trackside full thresholds")

print("PASS: trackside layout, stock consumption, skipped and ground cells, resupply accounting")

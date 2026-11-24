-- Run from the mod root: lua tests/rails.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_train_created", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  riding = {acceleration = {accelerating = 1, nothing = 0}, direction = {left = 0, straight = 1, right = 2}},
  inventory = {cargo_wagon = "cargo_wagon"},
  train_state = {no_path = 1, destination_full = 2},
  events = events
}
storage = {}
script = {
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
rendering = {draw_animation = function() return {valid = true, destroy = function() end} end}
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
local layer = require("lib.layer")
layer.on_init()

local rails, placed = {}, {}
local can_place_default = function(options)
  for _, rail in pairs(rails) do
    if rail.valid and math.abs(rail.position.x - options.position.x) < 1e-9 and math.abs(rail.position.y - options.position.y) < 1e-9 then return false end
  end
  return true
end
local can_place = can_place_default
local surface = {
  find_entities_filtered = function(filter)
    local out = {}
    if filter.area then
      for _, rail in pairs(rails) do
        if rail.blocker and rail.position.x >= filter.area[1][1] and rail.position.y >= filter.area[1][2]
          and rail.position.x <= filter.area[2][1] and rail.position.y <= filter.area[2][2] then out[#out + 1] = rail end
      end
      return out
    end
    for _, rail in pairs(rails) do
      local dx, dy = rail.position.x - filter.position.x, rail.position.y - filter.position.y
      if dx * dx + dy * dy <= filter.radius * filter.radius and not rail.blocker then
        for _, t in pairs(filter.type) do if rail.type == t then out[#out + 1] = rail end end
      end
    end
    return out
  end,
  find_tiles_filtered = function() return {} end,
  get_tile = function() return {name = "grass-1"} end,
  set_tiles = function() end,
  can_place_entity = function(options) return can_place(options) end,
  create_entity = function(options)
    local rail = {valid = true, name = options.name, type = options.name, position = options.position, direction = options.direction}
    if options.name ~= "rail-signal" and options.name ~= "medium-electric-pole" then
      placed[#placed + 1] = rail
    end
    rails[#rails + 1] = rail
    return rail
  end,
  play_sound = function() end
}

local inventory = {
  remove = function() return 1 end,
  insert = function() return 0 end,
  get_item_count = function() return 200 end
}
local wagon = {get_inventory = function() return inventory end}
local passenger = {riding_state = {acceleration = defines.riding.acceleration.nothing, direction = defines.riding.direction.straight},
  mod_settings = {[shared.setting_lanes] = {value = 1}, [shared.setting_lane_spacing] = {value = 4}}}
local loco = {valid = true, name = shared.layer_locomotive, unit_number = 1, orientation = 0,
  position = {x = 0, y = 0}, surface = surface, force = {print = function() end}}
loco.train = {speed = 0.15, locomotives = {front_movers = {loco}}, passengers = {passenger},
  cargo_wagons = {wagon}, carriages = {loco}, manual_mode = true}
layer.events[events.script_raised_built]{entity = loco}
local record = storage.layer.locos[1]

local function seed(type, direction, x, y)
  local rail = {valid = true, name = type, type = type, position = {x = x, y = y}, direction = direction}
  rails[#rails + 1] = rail
  return rail
end

local function lay(tick)
  placed = {}
  layer.events[events.on_tick]{tick = tick * shared.layer.rail_lay_interval}
  return placed
end

local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

local function check(rail, name, direction, x, y)
  assert(rail, "expected a placed rail")
  assert(rail.name == name, rail.name .. " ~= " .. name)
  assert(rail.direction == direction, "direction " .. tostring(rail.direction) .. " ~= " .. direction)
  near(rail.position.x, x)
  near(rail.position.y, y)
end

-- Cardinal laying is unchanged: straights step two tiles north at direction 0.
seed("straight-rail", 0, 0, 0)
local laid = lay(1)
assert(#laid == 3, "first lay should place the full lookahead")
check(laid[1], "straight-rail", 0, 0, -2)
check(laid[3], "straight-rail", 0, 0, -6)
assert(record.last_rail == laid[3], "last_rail is the laid frontier")
assert(record.travel_dir == 0, "still travelling north")

laid = lay(2)
check(laid[1], "straight-rail", 0, 0, -8)

-- Steering right at a straight starts a curve-a once the train rides close enough; its forced curve-b waits for the nose.
passenger.riding_state.direction = defines.riding.direction.right
loco.position = {x = 0, y = -6}
laid = lay(3)
assert(#laid == 1, "the lookahead stops short of the curve-b")
check(laid[1], "curved-rail-a", 2, 0, -11)
assert(record.travel_dir == 0, "the curve-a has not turned the travel dir yet")

-- Riding onto the curve-a places its forced curve-b, which exits the chain northeast.
loco.position = {x = 0, y = -11}
laid = lay(4)
assert(#laid == 1, "only the curve-b is in reach")
check(laid[1], "curved-rail-b", 2, 2, -16)
assert(record.travel_dir == 1, "the curve pair exits northeast")

-- Diagonal track keeps chaining on its own: the old cardinal snap dead-ended here.
passenger.riding_state.direction = defines.riding.direction.straight
loco.position = {x = 2, y = -16}
laid = lay(5)
check(laid[1], "straight-rail", 2, 5, -19)
check(laid[2], "straight-rail", 2, 7, -21)

loco.position = {x = 7, y = -18}
loco.orientation = 0.125
laid = lay(6)
check(laid[1], "straight-rail", 2, 9, -23)
assert(record.travel_dir == 1, "a diagonal frontier keeps its travel dir")

-- A stale frontier reseeds onto the rail under the nose and keeps chaining northeast.
loco.position = {x = 9, y = -23}
record.last_rail = nil
laid = lay(7)
check(laid[1], "straight-rail", 2, 13, -27)

-- A mid-curve piece under the nose seeds the forced continuation.
loco.position = {x = 0, y = 30}
loco.orientation = 0.06
record.last_rail = nil
seed("curved-rail-a", 2, 0, 30)
laid = lay(8)
assert(#laid == 1, "the exit straight is out of reach")
check(laid[1], "curved-rail-b", 2, 2, 25)
assert(record.travel_dir == 1, "curve-a continues into curve-b")

-- Already-built continuation rail is walked forward, not treated as a blocker.
loco.position = {x = 0, y = 0}
loco.orientation = 0
record.last_rail = nil
record.travel_dir = nil
rails = {}
for y = 0, -12, -2 do seed("straight-rail", 0, 0, y) end
laid = lay(9)
assert(#laid == 0, "existing rail is only walked, never duplicated")
assert(record.last_rail and record.last_rail.position.y == -12, "the frontier walked to the end of the existing chain")
loco.position = {x = 0, y = -8}
laid = lay(10)
assert(#laid == 2, "the empty continuation inside lookahead lays after the walk")
check(laid[1], "straight-rail", 0, 0, -14)
check(laid[2], "straight-rail", 0, 0, -16)

-- A blocker inside the footprint gets eaten, then the piece places.
loco.position = {x = 0, y = 0}
loco.orientation = 0
record.last_rail = nil
rails = {}
seed("straight-rail", 0, 0, 0)
local blocker = {valid = true, blocker = true, name = "tree-01", type = "tree", destructible = true,
  position = {x = 0, y = -2}, prototype = {mineable_properties = {products = {}}}}
blocker.die = function() blocker.valid = false end
rails[#rails + 1] = blocker
local calls = 0
can_place = function() calls = calls + 1 return calls > 1 end
laid = lay(9)
check(laid[1], "straight-rail", 0, 0, -2)
assert(not blocker.valid, "the grindable blocker was eaten")
can_place = can_place_default

-- An unplaceable continuation stalls the lay instead of consuming rail.
can_place = function() return false end
local count = #rails
laid = lay(10)
assert(#laid == 0 and #rails == count, "nothing places and nothing is eaten")
can_place = can_place_default

print("PASS: cardinal straights, steered curve pair, diagonal chaining, mid-curve seed, existing-chain walk, footprint grind, stall")

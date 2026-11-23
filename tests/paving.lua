-- Run from the mod root: lua tests/paving.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed",
  "on_train_created", "on_robot_pre_mined"
} do events[name] = index end

defines =
{
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = 1},
  events = events
}
storage = {}
script =
{
  get_event_id = function() return 100 end,
  on_event = function() end,
  register_on_object_destroyed = function() return 1 end
}
rendering =
{
  draw_animation = function(options)
    local object = {valid = true, target = options.target, orientation = options.orientation, render_layer = options.render_layer, animation_speed = options.animation_speed}
    object.destroy = function() object.valid = false end
    return object
  end
}

local shared = require("shared")
settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}}}
local layer = require("lib.layer")

local function key(x, y) return x .. "," .. y end

-- A flat grass world plus the stubs lay_rail touches: tile grid, entity list, one cargo wagon.
local function new_world(setup)
  local grid, water, entities = {}, {}, {}
  for _, tile in ipairs(setup.water or {}) do
    grid[key(tile[1], tile[2])] = "water"
    water[key(tile[1], tile[2])] = true
  end
  for _, tile in ipairs(setup.tiles or {}) do grid[key(tile[1], tile[2])] = tile[3] end
  for _, entity in ipairs(setup.entities or {}) do entities[#entities + 1] = entity end
  local created, set_log, prints = {}, {}, {}
  local surface = {}
  surface.get_tile = function(position)
    return {name = grid[key(position.x, position.y)] or "grass-1", position = {x = position.x, y = position.y}}
  end
  surface.set_tiles = function(tiles)
    set_log[#set_log + 1] = tiles
    for _, tile in ipairs(tiles) do
      local k = key(tile.position.x, tile.position.y)
      grid[k] = tile.name
      water[k] = nil
    end
  end
  surface.find_tiles_filtered = function(options)
    local found, area = {}, options.area
    for k in pairs(water) do
      local x, y = k:match("(-?%d+),(-?%d+)")
      x, y = tonumber(x), tonumber(y)
      if x >= area[1][1] and x < area[2][1] and y >= area[1][2] and y < area[2][2] then
        found[#found + 1] = {name = "water", position = {x = x, y = y}}
      end
    end
    return found
  end
  surface.find_entities_filtered = function(options)
    local found = {}
    for _, entity in ipairs(entities) do
      local match = not options.type or entity.type == options.type
      if match and options.position then
        local dx, dy = entity.position.x - options.position.x, entity.position.y - options.position.y
        match = dx * dx + dy * dy <= options.radius * options.radius
      end
      if match and options.area then
        local area = options.area
        match = entity.position.x > area[1][1] and entity.position.x < area[2][1] and entity.position.y > area[1][2] and entity.position.y < area[2][2]
      end
      if match then found[#found + 1] = entity end
    end
    return found
  end
  surface.can_place_entity = function(options)
    for _, entity in ipairs(entities) do
      if entity.type == "straight-rail" and entity.position.x == options.position.x and entity.position.y == options.position.y then return false end
    end
    return true
  end
  surface.create_entity = function(options)
    local entity = {valid = true, type = "straight-rail", name = options.name, position = options.position, direction = options.direction}
    created[#created + 1] = entity
    entities[#entities + 1] = entity
    return entity
  end
  surface.play_sound = function() end
  local counts = {}
  for name, count in pairs(setup.cargo) do counts[name] = count end
  local inventory =
  {
    remove = function(item)
      if (counts[item.name] or 0) >= item.count then
        counts[item.name] = counts[item.name] - item.count
        return item.count
      end
      return 0
    end,
    insert = function(item)
      counts[item.name] = (counts[item.name] or 0) + item.count
      return item.count
    end,
    get_item_count = function(item) return counts[item.name] or 0 end
  }
  local wagon = {get_inventory = function() return inventory end}
  local schedule =
  {
    group = nil,
    current = 1,
    get_records = function() return setup.records or {} end,
    get_interrupts = function() return {} end
  }
  local loco =
  {
    valid = true, name = shared.layer_locomotive, unit_number = 1,
    orientation = 0, position = {x = 0, y = 0}, surface = surface,
    force = {print = function(message) prints[#prints + 1] = message end}
  }
  local train =
  {
    speed = 0.1, manual_mode = true,
    locomotives = {front_movers = {loco}, back_movers = {}},
    passengers = {}, cargo_wagons = {wagon}, carriages = {loco, wagon},
    get_schedule = function() return schedule end
  }
  loco.train = train
  layer.on_init()
  layer.events[events.script_raised_built]{entity = loco}
  return {loco = loco, counts = counts, grid = grid, created = created, set_log = set_log, prints = prints}
end

-- The loco faces north, so new rail grows to -y: a seeded rail at -6 and lookahead 9 lay two
-- more per lay tick, at -8 and -10, each paving a 4x4 square around its 2x2 footprint.
local function seeded_rail()
  return {{type = "straight-rail", name = "straight-rail", position = {x = 0, y = -6}, direction = 0}}
end

local world = new_world{cargo = {rail = 100, landfill = 100, concrete = 100}, entities = seeded_rail()}
layer.events[events.on_tick]{tick = 5}
assert(#world.created == 2, "two rails laid ahead of the seeded one")
assert(world.counts.rail == 98, "one rail item per laid rail")
local paved = 0
for x = -2, 1 do
  for y = -12, -7 do
    assert(world.grid[key(x, y)] == "concrete", "footprint plus pave_width margin all paved")
    paved = paved + 1
  end
end
for _, name in pairs(world.grid) do assert(name == "concrete", "nothing paved outside the margin") end
assert(world.counts.concrete == 100 - paved, "one concrete item per paved tile: " .. world.counts.concrete)
for _, batch in ipairs(world.set_log) do
  for _, tile in ipairs(batch) do assert(tile.name == "concrete") end
end
assert(#world.prints == 0, "stocked cargo stays silent")
print("PASS: each laid rail paves its footprint plus margin, one item per tile")

world = new_world{cargo = {rail = 100, landfill = 100, concrete = 5}, entities = seeded_rail()}
layer.events[events.on_tick]{tick = 5}
assert(#world.created == 2, "empty concrete never blocks laying")
assert(world.counts.concrete == 0, "paving drains the last items")
local paved_count = 0
for _, name in pairs(world.grid) do if name == "concrete" then paved_count = paved_count + 1 end end
assert(paved_count == 5, "only what cargo paid for got paved")
assert(world.prints[1][1] == "shay-message.out-of-concrete")
assert(world.prints[2][1] == "shay-message.no-supply-station")
assert(#world.prints == 2, "both starving rails warned only once")
world.loco.position = {x = 0, y = -8}
layer.events[events.on_tick]{tick = 305}
assert(#world.created == 5, "train keeps laying unpaved after running dry")
assert(world.prints[3][1] == "shay-message.out-of-concrete" and #world.prints == 4, "warns again once warn_interval lapses")
assert(world.counts.concrete == 0)
print("PASS: out of concrete lays unpaved and warns once per interval")

world = new_world
{
  cargo = {rail = 100, landfill = 100, concrete = 100},
  entities = seeded_rail(),
  tiles =
  {
    {-2, -8, "refined-concrete"}, {-1, -8, "refined-concrete"}, {0, -8, "refined-concrete"}, {1, -8, "refined-concrete"},
    {-2, -7, "hazard-concrete-left"}, {-1, -7, "hazard-concrete-left"}, {0, -7, "hazard-concrete-left"}, {1, -7, "hazard-concrete-left"}
  },
  water = {{-2, -11}, {-1, -11}, {0, -11}, {1, -11}}
}
layer.events[events.on_tick]{tick = 5}
local expected =
{
  ["-2,-11"] = "water", ["1,-11"] = "water",
  ["-2,-8"] = "refined-concrete", ["-1,-8"] = "refined-concrete", ["0,-8"] = "refined-concrete", ["1,-8"] = "refined-concrete",
  ["-2,-7"] = "hazard-concrete-left", ["-1,-7"] = "hazard-concrete-left", ["0,-7"] = "hazard-concrete-left", ["1,-7"] = "hazard-concrete-left"
}
for x = -2, 1 do
  for y = -12, -7 do
    local k = key(x, y)
    local want = expected[k] or "concrete"
    assert(world.grid[k] == want, k .. " is " .. tostring(world.grid[k]) .. ", want " .. want)
  end
end
assert(world.counts.concrete == 86, "no item spent on kept or water tiles: " .. world.counts.concrete)
assert(world.counts.landfill == 98, "footprint water landfilled before paving")
assert(#world.prints == 0)
print("PASS: better tiles and margin water untouched, footprint water landfilled then paved")

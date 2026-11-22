-- Run from the mod root: lua tests/demolition.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_train_changed_state", "on_built_entity", "on_robot_built_entity",
  "script_raised_built", "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed", "on_train_created", "on_robot_pre_mined"
} do events[name] = index end

defines = {
  direction = {north = 0, east = 4, south = 8, west = 12},
  train_state = {no_path = 1, destination_full = 2},
  inventory = {cargo_wagon = 1},
  riding = {acceleration = {accelerating = 1, nothing = 2}},
  events = events
}
storage = {}
local input_names, custom_handler = {}, {}
script = {
  get_event_id = function(name) input_names[#input_names + 1] = name; return #input_names end,
  on_event = function(id, handler) custom_handler[input_names[id]] = handler end,
  register_on_object_destroyed = function() return 1 end
}
rendering = {draw_animation = function()
  local object = {valid = true}
  object.destroy = function() object.valid = false end
  return object
end}
helpers = {is_valid_sound_path = function() return false end}
player = {}
game = {get_player = function() return player end}

local shared = require("shared")
settings = {startup = {[shared.rail_item_setting] = {value = "rail"}}}
prototypes = {item = {rail = {place_result = {name = "straight-rail", type = "straight-rail"}}}}
local layer = require("lib.layer")

local world, next_unit, prints, texts, surface

-- Corners come in both Factorio forms: {x=,y=} points and {x,y} pairs.
local function point(p) return p.x or p[1], p.y or p[2] end

local function bounds(e)
  if e.bounding_box then
    local x1, y1 = point(e.bounding_box.left_top or e.bounding_box[1])
    local x2, y2 = point(e.bounding_box.right_bottom or e.bounding_box[2])
    return x1, y1, x2, y2
  end
  return e.position.x - e.half, e.position.y - e.half, e.position.x + e.half, e.position.y + e.half
end

local function area_corners(area)
  local x1, y1 = point(area.left_top or area[1])
  local x2, y2 = point(area.right_bottom or area[2])
  return x1, y1, x2, y2
end

local function spawn(fields)
  next_unit = next_unit + 1
  local e = {
    valid = true, surface = surface,
    name = fields.name or fields.type,
    type = fields.type,
    position = fields.position,
    direction = fields.direction or 0,
    orientation = fields.orientation or 0,
    destructible = fields.destructible ~= false,
    force = fields.force,
    unit_number = fields.unit_number or next_unit,
    half = fields.half or 0.5,
    bounding_box = fields.bounding_box,
    solid = fields.solid ~= false,
    prototype = {mineable_properties = {products = fields.products or {}}}
  }
  e.die = function() e.valid = false end
  e.destroy = function() e.valid = false end
  world[#world + 1] = e
  return e
end

local function find(opts)
  local results = {}
  for _, e in ipairs(world) do
    if e.valid then
      local ok = true
      if opts.type then
        if type(opts.type) == "table" then
          ok = false
          for _, t in ipairs(opts.type) do ok = ok or e.type == t end
        else ok = e.type == opts.type end
      end
      if ok and opts.area then
        local x1, y1, x2, y2 = bounds(e)
        local ax1, ay1, ax2, ay2 = area_corners(opts.area)
        ok = x1 < ax2 and x2 > ax1 and y1 < ay2 and y2 > ay1
      end
      if ok and opts.position then
        local r = opts.radius or 0.5
        local dx, dy = e.position.x - opts.position.x, e.position.y - opts.position.y
        ok = dx * dx + dy * dy <= r * r
      end
      if ok then results[#results + 1] = e end
    end
  end
  return results
end

local function rail_at(x, y)
  for _, e in ipairs(world) do
    if e.valid and e.type == "straight-rail" and e.position.x == x and e.position.y == y then return e end
  end
end

-- One north-facing consist: layer loco at the origin, a cargo wagon trailing at +y.
local function setup(room)
  world, next_unit, prints, texts = {}, 0, {}, {}
  surface = {
    find_entities_filtered = find,
    find_tiles_filtered = function() return {} end,
    can_place_entity = function(opts)
      for _, e in ipairs(world) do
        if e.valid and e.solid then
          local x1, y1, x2, y2 = bounds(e)
          if opts.position.x - 1 < x2 and opts.position.x + 1 > x1 and opts.position.y - 1 < y2 and opts.position.y + 1 > y1 then return false end
        end
      end
      return true
    end,
    create_entity = function(opts)
      return spawn{type = opts.name, position = opts.position, direction = opts.direction, force = opts.force, half = 1,
        products = {{type = "item", name = "rail", amount = 1}}}
    end,
    set_tiles = function() end,
    play_sound = function() end
  }
  local force = {name = "player", print = function(msg) prints[#prints + 1] = msg[1] end}
  local items = {}
  local inventory
  inventory = {
    get_item_count = function(filter) return items[filter.name] or 0 end,
    get_insertable_count = function(name)
      local cap = (room or {})[name]
      if cap then return math.max(0, cap - (items[name] or 0)) end
      return 1000000
    end,
    remove = function(stack)
      local have = items[stack.name] or 0
      local taken = math.min(have, stack.count)
      items[stack.name] = have - taken
      return taken
    end,
    insert = function(stack)
      local put = math.min(stack.count, inventory.get_insertable_count(stack.name))
      items[stack.name] = (items[stack.name] or 0) + put
      return put
    end
  }
  -- Rolling stock never blocks rail placement: it lives on a different collision layer.
  local loco = spawn{type = "locomotive", name = shared.layer_locomotive, position = {x = 0, y = 0},
    bounding_box = {{-1, -3}, {1, 3}}, force = force, unit_number = 1, solid = false}
  local wagon = spawn{type = "cargo-wagon", name = "cargo-wagon", position = {x = 0, y = 7},
    bounding_box = {{-1, 4}, {1, 10}}, force = force, solid = false}
  wagon.get_inventory = function() return inventory end
  loco.train = {
    carriages = {loco, wagon}, cargo_wagons = {wagon},
    locomotives = {front_movers = {loco}, back_movers = {}},
    passengers = {}, speed = 0.1, manual_mode = true, state = 1
  }
  player.vehicle, player.force = loco, force
  player.create_local_flying_text = function(options) texts[#texts + 1] = options.text end
  layer.on_init()
  layer.events[events.script_raised_built]{entity = loco}
  return {
    loco = loco, wagon = wagon, train = loco.train, force = force,
    enemy = {name = "enemy"}, record = storage.layer.locos[1], items = items
  }
end

local function rail(s, x, y, fields)
  fields = fields or {}
  fields.type, fields.position, fields.direction, fields.half = "straight-rail", {x = x, y = y}, 0, 1
  fields.products = fields.products or {{type = "item", name = "rail", amount = 1}}
  fields.force = fields.force or s.force
  return spawn(fields)
end

local function furniture(s, kind, x, y, fields)
  fields = fields or {}
  fields.type, fields.position = kind, {x = x, y = y}
  fields.force = fields.force or s.force
  fields.products = fields.products or {{type = "item", name = kind, amount = 1}}
  return spawn(fields)
end

local tick = function() layer.events[events.on_tick]{tick = 5} end

-- Bulldozer: the consist tears up its own line behind it and stores the take.
local s = setup()
s.items.rail, s.items.landfill, s.items["cliff-explosives"] = 50, 50, 50
rail(s, 0, 0)      -- under the loco
rail(s, 0, 10.5)   -- straddles the wagon's tail: inside the protection radius and the sweep
local eaten = {
  rail(s, 0, 13.5), rail(s, 0, 15),
  furniture(s, "rail-signal", 2, 12),
  furniture(s, "electric-pole", 3, 14),
  furniture(s, "lamp", -2, 16),
  furniture(s, "wall", 3.5, 18)
}
local kept = {
  rail(s, 0, -8),                                   -- ahead of the consist: bulldozer only works behind
  rail(s, 3, 12),                                   -- a parallel line: only the consist's own line is torn up
  furniture(s, "wall", 6, 12),                      -- outside the corridor
  furniture(s, "train-stop", 2, 15),                -- infrastructure the mod cannot rebuild
  furniture(s, "curved-rail-a", 0.5, 13),
  furniture(s, "rail-signal", -2, 12, {force = s.enemy}),
  furniture(s, "wall", 1, 19, {name = shared.mg_turret}), -- support entities are never targets
  rail(s, 0, 14, {destructible = false})
}
local off_rail = rail(s, 0, 19.5)
local stopped_rail = rail(s, 0, 20.25)

s.record.mode = "off"
tick()
assert(off_rail.valid and stopped_rail.valid, "mode off must not demolish")
s.record.mode = "bulldozer"
s.train.speed = 0
tick()
assert(off_rail.valid and stopped_rail.valid, "a standing consist does not demolish")
s.train.speed = 0.1
tick()
for _, e in ipairs(eaten) do assert(not e.valid, "bulldozer removes " .. e.type .. " behind") end
assert(not off_rail.valid and not stopped_rail.valid)
for _, e in ipairs(kept) do assert(e.valid, "bulldozer must spare " .. e.type) end
assert(s.items.rail == 54, "four torn-up rails came aboard")
assert(s.items["rail-signal"] == 1 and s.items["electric-pole"] == 1)
assert(s.items.lamp == 1 and s.items.wall == 1)
assert(#prints == 0)

-- Full cargo: what cannot be stored is left standing, and the warning is throttled.
s = setup({rail = 50})
s.items.rail, s.items.landfill, s.items["cliff-explosives"] = 50, 50, 50
rail(s, 0, 0)
local jammed = rail(s, 0, 12)
local fits = furniture(s, "electric-pole", 3, 14)
s.record.mode = "bulldozer"
tick()
assert(jammed.valid, "a rail that cannot be stored is left standing")
assert(not fits.valid, "entities whose products do fit are still taken")
assert(prints[1] == "shay-message.demolish-cargo-full")
tick()
assert(#prints == 1, "the full-cargo warning waits out warn_interval before repeating")

-- Maintenance: the old line ahead is pulled up and relaid on the same heading.
s = setup()
s.items.rail, s.items.landfill, s.items["cliff-explosives"] = 50, 50, 50
rail(s, 0, 0)
local old = {
  rail(s, 0, -5), rail(s, 0, -7), rail(s, 0, -9),
  furniture(s, "rail-signal", 2, -6),
  furniture(s, "electric-pole", 3, -9)
}
local survivors = {
  rail(s, 0, -16),                                    -- beyond the sweep span
  furniture(s, "curved-rail-a", 0.5, -17),
  furniture(s, "electric-pole", 2, -8, {force = s.enemy})
}
s.record.mode = "maintenance"
tick()
for _, e in ipairs(old) do assert(not e.valid, "maintenance removes " .. e.type .. " ahead") end
for _, e in ipairs(survivors) do assert(e.valid, "maintenance must spare " .. e.type) end
local fresh = {rail_at(0, -2), rail_at(0, -4), rail_at(0, -6)}
assert(fresh[1] and fresh[2] and fresh[3], "the torn-up line is relaid on the same heading")
assert(s.record.relaid[fresh[3].unit_number] == fresh[3], "relaid rails are marked")
assert(s.items.rail == 50, "three old rails came in, three fresh rails went out")
tick()
assert(fresh[1].valid and fresh[2].valid and fresh[3].valid, "relaid rails are not torn up again")
assert(rail_at(0, -8) and rail_at(0, -10), "laying keeps extending the fresh line")
assert(s.items.rail == 48)
assert(survivors[1].valid, "the old line outside the window is left alone")

-- CTRL+ALT+G cycles lay -> bulldozer -> maintenance -> off -> lay, printing each mode.
s = setup()
local cycle = function() custom_handler[shared.custom_input_demolition]{player_index = 1} end
for i, case in ipairs{
  {"bulldozer", "mode-bulldozer"}, {"maintenance", "mode-maintenance"},
  {"off", "mode-off"}, {nil, "mode-lay"}
} do
  cycle()
  assert(s.record.mode == case[1], "cycle step " .. i)
  assert(prints[#prints] == "shay-message." .. case[2])
end
assert(#prints == 4)
player.vehicle = spawn{type = "car", name = "car", position = {x = 0, y = 0}, force = s.force}
cycle()
assert(s.record.mode == nil and #prints == 4, "the hotkey does nothing outside a train")

print("PASS: bulldozer behind removal with cargo and protections, cargo-full throttle, maintenance ahead removal and relaid marks, mode cycling")

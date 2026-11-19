-- Run from the mod root: lua tests/refill.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_built_entity", "on_robot_built_entity", "script_raised_built",
  "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  inventory = {turret_ammo = "turret_ammo"},
  events = events
}
storage = {}
local next_registration = 0
script = {
  register_on_object_destroyed = function() next_registration = next_registration + 1 return next_registration end
}

local shared = require("shared")
local frame = require("lib.frame")
local turrets = require("lib.turrets")
turrets.on_init()

local checks_this_tick = 0
local function make_turret(name)
  local turret = {valid = true, name = name, checks = 0, inserted = 0, empty = false, teleported = nil}
  turret.get_inventory = function()
    turret.checks = turret.checks + 1
    checks_this_tick = checks_this_tick + 1
    return {
      is_empty = function() return turret.empty end,
      insert = function(item) turret.inserted = turret.inserted + item.count turret.empty = false return item.count end
    }
  end
  turret.teleport = function(position) turret.teleported = position end
  return turret
end

local made = {}
local stock = {valid = true, name = shared.mg_wagon, unit_number = 7, speed = 0, orientation = 0, position = {x = 0, y = 0}, force = {}}
stock.surface = {create_entity = function(options)
  local turret = make_turret(options.name)
  made[#made + 1] = turret
  return turret
end}

turrets.events[events.script_raised_built]{entity = stock}
assert(#made == 3, "mg wagon arms three hardpoint turrets")
assert(made[1].inserted == 10, "arm seeds each turret with ammo")

-- The sweep checks a bounded slice per tick: three entries means one check a tick.
local function run_ticks(n)
  for _ = 1, n do
    checks_this_tick = 0
    turrets.events[events.on_tick]()
    assert(checks_this_tick <= 1, "more than the slice budget ran in one tick")
  end
end
run_ticks(60)
for _, turret in ipairs(made) do assert(turret.checks > 0, "a sweep never reached a queued turret") end

-- An empty turret tops back up when the sweep reaches it.
made[1].empty = true
run_ticks(60)
assert(made[1].inserted > 10, "the sweep refilled the empty turret")
assert(not made[1].empty, "insert restocked the turret")

-- Destroyed turrets leave the queue instead of being swept forever.
made[2].valid = false
local checks_before = made[2].checks
run_ticks(60)
assert(made[2].checks == checks_before, "destroyed turret was still checked")
local live_checks = made[1].checks + made[3].checks
run_ticks(60)
assert(made[1].checks + made[3].checks > live_checks, "live turrets kept being swept")

-- Teleports ride the per-tick path with the scratch-position helper.
stock.speed = 0.1
turrets.events[events.on_tick]()
for _, turret in ipairs(made) do
  if turret.valid then
    assert(turret.teleported, "moving stock never teleported a turret")
    assert(math.abs(turret.teleported.x) < 10 and math.abs(turret.teleported.y) < 10, "teleport target out of range")
  end
end
local out = {}
frame.place_into(stock, {0, 1.8}, out)
local expected = frame.place(stock, {0, 1.8})
assert(out.x == expected.x and out.y == expected.y, "place_into disagrees with place")

-- on_load rebuilds the sweep from the records: every turret gets reached again.
storage.turrets = {stock = {[7] = {entity = stock, turrets = {made[1], made[2], made[3]}}}, registrations = {}}
for _, turret in ipairs(made) do turret.checks = 0 end
turrets.on_load()
stock.speed = 0
checks_this_tick = 0
for _ = 1, 60 do turrets.events[events.on_tick]() end
for _, turret in ipairs(made) do assert(not turret.valid or turret.checks > 0, "on_load rebuild missed a turret") end

print("PASS: refill sweeps a bounded slice per tick, refills empties, drops dead turrets, rebuilds on load")

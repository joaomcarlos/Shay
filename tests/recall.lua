-- Run from the mod root: lua tests/recall.lua
local events = {}
for index, name in ipairs{
  "on_tick", "on_built_entity", "on_robot_built_entity", "script_raised_built",
  "script_raised_revive", "on_entity_cloned", "on_player_mined_entity",
  "on_robot_mined_entity", "on_entity_died", "script_raised_destroy", "on_object_destroyed"
} do events[name] = index end

defines = {
  command = {go_to_location = "go_to_location"},
  distraction = {by_enemy = "by_enemy", none = "none"},
  events = events
}
storage = {}
local next_registration = 0
script = {
  register_on_object_destroyed = function() next_registration = next_registration + 1 return next_registration end
}
rendering = {draw_sprite = function()
  local object = {valid = true}
  object.destroy = function() object.valid = false end
  return object
end}

local shared = require("shared")
shared.ramp.bots_per_side = 1 -- a two-bot escort keeps the assertions readable
local ramp = require("lib.ramp")
ramp.on_init()

local made = {}
local function make_bot(unit_number, position)
  local bot = {valid = true, unit_number = unit_number, position = position, commands = {}}
  bot.commandable = {set_command = function(command)
    bot.commands[#bot.commands + 1] = command
    bot.last_command = command
  end}
  bot.destroy = function() bot.valid = false end
  return bot
end

local wagon = {valid = true, name = shared.ramp_wagon, unit_number = 1, orientation = 0, position = {x = 0, y = 0}, force = {}}
wagon.train = {speed = 0}
wagon.surface = {
  find_non_colliding_position = function(_, position) return position end,
  create_entity = function(options)
    local bot = make_bot(100 + #made, {x = options.position.x, y = options.position.y})
    made[#made + 1] = bot
    return bot
  end
}

ramp.events[events.script_raised_built]{entity = wagon}
local tick = function(n) ramp.on_nth_tick[10]{tick = n} end
local function near(actual, expected)
  assert(math.abs(actual - expected) < 1e-9, tostring(actual) .. " ~= " .. tostring(expected))
end

-- A stopped train parks the wagon and puts both bots on the ring.
tick(1)
local record = storage.ramp.wagons[1]
assert(record.state == "deployed", "stopped train deploys the escort")
assert(#made == 2, "one bot per flank")
for _, bot in ipairs(made) do
  assert(bot.last_command.type == defines.command.go_to_location)
  assert(bot.last_command.distraction == defines.distraction.by_enemy, "bots leave on patrol")
end

-- Past shared.ramp.straggle_distance the bot is ordered back to the wagon...
local straggler, neighbour = made[1], made[2]
straggler.position.x = shared.ramp.straggle_distance + 10
tick(11)
near(straggler.last_command.destination.x, wagon.position.x)
near(straggler.last_command.destination.y, wagon.position.y)
assert(straggler.last_command.distraction == defines.distraction.none, "a straggler ignores enemies on the way home")

-- ...while a bot inside the distance is left on patrol.
assert(#neighbour.commands == 1, "a bot inside the straggle distance keeps its patrol order")
assert(not record.bots[neighbour.unit_number].recalling)

-- A straggler that reaches the wagon rejoins the ring instead of despawning.
straggler.position.x, straggler.position.y = 0.5, 0
tick(21)
assert(straggler.valid, "a returned straggler is not despawned while the wagon is deployed")
assert(record.bots[straggler.unit_number], "a returned straggler stays on the roster")
assert(not record.bots[straggler.unit_number].recalling)
assert(straggler.last_command.distraction == defines.distraction.by_enemy, "a returned straggler resumes patrol")
near(straggler.last_command.destination.x, shared.ramp.patrol_radius)

-- Once the train pulls away the whole escort is called in, whatever the distance.
neighbour.position.x = 80
wagon.train.speed = 1
tick(31)
assert(not straggler.valid, "a bot already home boards the wagon on the spot")
assert(record.bots[neighbour.unit_number], "a far bot is still homeward bound")
near(neighbour.last_command.destination.x, wagon.position.x)
near(neighbour.last_command.destination.y, wagon.position.y)
assert(neighbour.last_command.distraction == defines.distraction.none, "a leaving wagon recalls without distractions")

-- Bots that reach a leaving wagon despawn into it and the wagon re-parks.
neighbour.position.x, neighbour.position.y = 0.4, 0
tick(41)
assert(not neighbour.valid, "an arrived bot boards the wagon")
assert(next(record.bots) == nil, "the escort is fully home")
assert(record.state == "parked", "an empty escort re-parks the wagon")

-- The next stop deploys a fresh escort.
wagon.train.speed = 0
tick(51)
assert(record.state == "deployed", "a stopped train redeploys the escort")
assert(#made == 4, "parked bots are replaced on redeploy")
for _, bot in ipairs{made[3], made[4]} do
  assert(bot.last_command.distraction == defines.distraction.by_enemy, "the new escort patrols")
end

print("PASS: bots past straggle_distance are recalled, nearer bots untouched, returnees rejoin the ring or re-park")

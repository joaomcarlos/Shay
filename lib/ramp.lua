local shared = require("shared")
local frame = require("lib.frame")

local update_interval = 10
local recall_reissue_ticks = 60
local flank_offset = 1.2
local track_clearance = 2
local straggle_distance = 20
local patrol_arrive = 1

local states =
{
  parked = "parked",
  deployed = "deployed",
  recalling = "recalling"
}

local script_data

local bot_count = function()
  return shared.ramp.bots_per_side * 2
end

local add = function(wagon)
  if script_data.wagons[wagon.unit_number] then return end
  script_data.wagons[wagon.unit_number] = {entity = wagon, state = states.parked, bots = {}, next_patrol = 0}
  script_data.registrations[script.register_on_object_destroyed(wagon)] = {wagon = wagon.unit_number}
end

local hide_ramps = function(record)
  for _, ramp in pairs(record.ramps or {}) do
    if ramp.valid then ramp.destroy() end
  end
  record.ramps = nil
end

local remove = function(unit_number)
  local record = script_data.wagons[unit_number]
  if not record then return end
  script_data.wagons[unit_number] = nil
  hide_ramps(record)
  for _, bot in pairs(record.bots) do
    if bot.entity.valid then bot.entity.destroy() end
  end
end

-- Slot k parks on the flank: odd slots right, even left, front to back.
local park_offset = function(slot)
  local side = slot % 2 == 1 and 1 or -1
  local index = math.ceil(slot / 2)
  local along = ((shared.ramp.bots_per_side + 1) / 2 - index) * shared.ramp.bot_spacing
  return {side * flank_offset, along}
end

-- Ring points are pushed off the track axis so the train never runs its own patrol over.
local ring_offset = function(slot)
  local angle = 2 * math.pi * (slot - 1) / bot_count()
  local side, along = shared.ramp.patrol_radius * math.cos(angle), shared.ramp.patrol_radius * math.sin(angle)
  if math.abs(side) < track_clearance then side = side < 0 and -track_clearance or track_clearance end
  return {side, along}
end

local patrol = function(record, bot)
  bot.entity.commandable.set_command
  {
    type = defines.command.go_to_location,
    destination = frame.place(record.entity, ring_offset(bot.ring)),
    radius = patrol_arrive,
    distraction = defines.distraction.by_enemy
  }
end

local recall = function(record, bot)
  bot.recalling = true
  bot.entity.commandable.set_command
  {
    type = defines.command.go_to_location,
    destination = record.entity.position,
    radius = shared.ramp.recall_arrive / 2,
    distraction = defines.distraction.none
  }
end

local deploy = function(record, tick)
  local wagon = record.entity
  local surface = wagon.surface
  local taken = {}
  for _, bot in pairs(record.bots) do taken[bot.slot] = true end
  for slot = 1, bot_count() do
    if not taken[slot] then
      local position = surface.find_non_colliding_position(shared.sentry_bot, frame.place(wagon, park_offset(slot)), 2, 0.1)
      if position then
        local entity = surface.create_entity{name = shared.sentry_bot, position = position, force = wagon.force}
        record.bots[entity.unit_number] = {entity = entity, slot = slot, ring = slot}
        script_data.registrations[script.register_on_object_destroyed(entity)] = {wagon = wagon.unit_number, bot = entity.unit_number}
      end
    end
  end
  for _, bot in pairs(record.bots) do
    bot.recalling = false
    patrol(record, bot)
  end
  -- Ramps down on both flanks while the bots are out; destroyed on recall.
  record.ramps = {}
  for _, side in pairs{flank_offset, -flank_offset} do
    record.ramps[#record.ramps + 1] = rendering.draw_sprite
    {
      sprite = shared.ramp_sprite,
      target = {entity = wagon, offset = {side, 0}},
      surface = wagon.surface,
      render_layer = "floor"
    }
  end
  record.state = states.deployed
  record.next_patrol = tick + shared.ramp.repatrol_ticks
end

local update_deployed = function(record, tick)
  local wagon = record.entity
  local repatrol = tick >= record.next_patrol
  if repatrol then record.next_patrol = tick + shared.ramp.repatrol_ticks end
  for _, bot in pairs(record.bots) do
    if bot.entity.valid and not bot.recalling then
      if frame.distance(bot.entity.position, wagon.position) > straggle_distance then
        recall(record, bot)
      elseif repatrol then
        bot.ring = bot.ring % bot_count() + 1
        patrol(record, bot)
      end
    end
  end
end

local update_recalling = function(record, tick)
  local wagon = record.entity
  local reissue = tick % recall_reissue_ticks < update_interval
  for unit_number, bot in pairs(record.bots) do
    if bot.entity.valid and (bot.recalling or record.state == states.recalling) then
      if frame.distance(bot.entity.position, wagon.position) <= shared.ramp.recall_arrive then
        record.bots[unit_number] = nil
        bot.entity.destroy()
      elseif reissue or not bot.recalling then
        recall(record, bot)
      end
    end
  end
  if record.state == states.recalling and next(record.bots) == nil then record.state = states.parked end
end

local update = function(record, tick)
  local slow = math.abs(record.entity.train.speed) < shared.ramp.deploy_speed
  if slow and record.state ~= states.deployed then
    deploy(record, tick)
  elseif not slow and record.state == states.deployed then
    hide_ramps(record)
    record.state = states.recalling
  end
  if record.state == states.deployed then update_deployed(record, tick) end
  update_recalling(record, tick)
end

local on_built = function(event)
  local entity = event.entity
  if entity.valid and entity.name == shared.ramp_wagon then add(entity) end
end

local on_entity_cloned = function(event)
  local entity = event.destination
  if not entity.valid then return end
  if entity.name == shared.ramp_wagon then
    add(entity)
  elseif entity.name == shared.sentry_bot then
    entity.destroy()
  end
end

local on_removed = function(event)
  local entity = event.entity
  if entity.name == shared.ramp_wagon then remove(entity.unit_number) end
end

local on_object_destroyed = function(event)
  local registration = script_data.registrations[event.registration_number]
  if not registration then return end
  script_data.registrations[event.registration_number] = nil
  if registration.bot then
    local record = script_data.wagons[registration.wagon]
    if record then record.bots[registration.bot] = nil end
    return
  end
  remove(registration.wagon)
end

local on_update = function(event)
  for _, record in pairs(script_data.wagons) do
    if record.entity.valid then update(record, event.tick) end
  end
end

local ramp = {}

ramp.on_init = function()
  storage.ramp = {wagons = {}, registrations = {}}
  script_data = storage.ramp
end

ramp.on_load = function()
  script_data = storage.ramp
end

ramp.on_nth_tick =
{
  [update_interval] = on_update
}

ramp.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_entity_cloned,
  [defines.events.on_player_mined_entity] = on_removed,
  [defines.events.on_robot_mined_entity] = on_removed,
  [defines.events.on_entity_died] = on_removed,
  [defines.events.script_raised_destroy] = on_removed,
  [defines.events.on_object_destroyed] = on_object_destroyed
}

return ramp

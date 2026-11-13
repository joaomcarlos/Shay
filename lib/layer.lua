local shared = require("shared")
local frame = require("lib.frame")

local rail_entity = "straight-rail"
local rail_item = "rail"
local rail_length = 2
local nose_reach = 3
local rail_search_radius = 6
local lookahead = nose_reach + 6
local max_rails_per_lay = 3
local grind_width = 1.2
local warn_interval = 300

local cardinals =
{
  [0] = {vector = {x = 0, y = -1}, direction = defines.direction.north},
  [1] = {vector = {x = 1, y = 0}, direction = defines.direction.east},
  [2] = {vector = {x = 0, y = 1}, direction = defines.direction.south},
  [3] = {vector = {x = -1, y = 0}, direction = defines.direction.west}
}

local script_data

local add = function(loco)
  if script_data.locos[loco.unit_number] then return end
  script_data.locos[loco.unit_number] = {entity = loco, cruise = false, next_warn = 0}
  script_data.registrations[script.register_on_object_destroyed(loco)] = loco.unit_number
end

local remove = function(unit_number)
  local record = script_data.locos[unit_number]
  if not record then return end
  script_data.locos[unit_number] = nil
  if record.grinder and record.grinder.valid then record.grinder.destroy() end
end

-- +1 when positive train speed carries this loco nose-first.
local heading = function(loco)
  for _, front_mover in pairs(loco.train.locomotives.front_movers) do
    if front_mover.unit_number == loco.unit_number then return 1 end
  end
  return -1
end

-- A passenger braking or reversing gets the throttle back for that tick.
local overridden = function(train)
  for _, player in pairs(train.passengers) do
    if player.riding_state.acceleration ~= defines.riding.acceleration.accelerating and player.riding_state.acceleration ~= defines.riding.acceleration.nothing then
      return true
    end
  end
  return false
end

local take_rail = function(train)
  for _, wagon in pairs(train.cargo_wagons) do
    if wagon.get_inventory(defines.inventory.cargo_wagon).remove{name = rail_item, count = 1} == 1 then return true end
  end
  return false
end

local store = function(train, name, count)
  for _, wagon in pairs(train.cargo_wagons) do
    count = count - wagon.get_inventory(defines.inventory.cargo_wagon).insert{name = name, count = count}
    if count == 0 then return end
  end
end

local rail_count = function(train)
  local count = 0
  for _, wagon in pairs(train.cargo_wagons) do
    count = count + wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count{name = rail_item}
  end
  return count
end

local train_records = function(train)
  local records = {}
  for _, carriage in pairs(train.carriages) do
    local record = script_data.locos[carriage.unit_number]
    if record then records[#records + 1] = record end
  end
  return records
end

-- The player's schedule (group, records, interrupts) is parked while the resupply schedule runs and put back afterwards.
local save_schedule = function(train)
  local schedule = train.get_schedule()
  return {group = schedule.group, records = schedule.get_records(), current = schedule.current, interrupts = schedule.get_interrupts()}
end

-- Records go back before the group: a group left empty by the detach is gone, and rejoining recreates it from the train's own schedule.
local restore_schedule = function(train, saved)
  local schedule = train.get_schedule()
  train.schedule = saved.records and {current = saved.current, records = saved.records} or nil
  schedule.set_interrupts(saved.interrupts)
  schedule.group = saved.group
end

local supply_station = function(saved)
  for _, schedule_record in pairs(saved.records or {}) do
    if schedule_record.station then return schedule_record.station end
  end
end

local resupply_schedule = function(station, last_rail)
  local records =
  {
    {
      station = station,
      wait_conditions =
      {
        {type = "item_count", compare_type = "and", condition = {first_signal = {type = "item", name = rail_item}, comparator = ">=", constant = shared.supply.rail_full}},
        {type = "time", compare_type = "or", ticks = shared.supply.wait_ticks}
      }
    }
  }
  -- The return leg's own wait outlasts arrive_wait so the script finishes the trip before the schedule loops back to the station.
  if last_rail then records[2] = {rail = last_rail, temporary = true, wait_conditions = {{type = "time", compare_type = "and", ticks = shared.supply.arrive_wait * 2}}} end
  return {current = 1, records = records}
end

-- Hands the train back to the player: manual, own schedule restored, cruise as it was.
local end_resupply = function(record, cruise)
  local resupply = record.resupply
  local train = record.entity.train
  for _, train_record in pairs(train_records(train)) do train_record.resupply = nil end
  train.manual_mode = true
  restore_schedule(train, resupply.saved)
  if cruise then
    record.cruise = true
    record.restore_manual = resupply.restore_manual
  end
end

local begin_resupply = function(record)
  local loco = record.entity
  local train = loco.train
  local saved = save_schedule(train)
  local station = supply_station(saved)
  if not station then return false end
  local last_rail = record.last_rail and record.last_rail.valid and record.last_rail or nil
  local records = train_records(train)
  local resupply =
  {
    phase = "outbound",
    station = station,
    last_rail = last_rail,
    resume_cruise = false,
    restore_manual = train.manual_mode,
    saved = saved
  }
  for _, train_record in pairs(records) do
    if train_record.cruise then
      resupply.resume_cruise = true
      resupply.restore_manual = train_record.restore_manual
    end
    train_record.cruise = false
    train_record.restore_manual = nil
    train_record.resupply = resupply
    if train_record.grinder and train_record.grinder.valid then train_record.grinder.destroy() end
    train_record.grinder = nil
  end
  if not last_rail then loco.force.print({"shay-message.resupply-no-return", station}) end
  local schedule = train.get_schedule()
  schedule.group = nil
  schedule.clear_interrupts()
  train.schedule = resupply_schedule(station, last_rail)
  train.manual_mode = false
  return true
end

local finish_resupply = function(record)
  local resupply = record.resupply
  local loco = record.entity
  local cruise = resupply.resume_cruise
  local last_rail = resupply.last_rail
  if cruise and last_rail and last_rail.valid then
    local forward, position, target = frame.forward(loco.orientation), loco.position, last_rail.position
    if (target.x - position.x) * forward.x + (target.y - position.y) * forward.y < 0 then
      cruise = false
      loco.force.print({"shay-message.resupply-facing-away"})
    end
  end
  end_resupply(record, cruise)
  loco.force.print({"shay-message.resupply-done"})
end

local abort_resupply = function(record, message, cruise)
  end_resupply(record, cruise)
  record.entity.force.print(message)
end

-- Phase tracking runs every tick; on_train_changed_state only handles the failure exits.
local step_resupply = function(record, tick)
  local resupply = record.resupply
  local train = record.entity.train
  local state = train.state
  local current = train.get_schedule().current
  if resupply.phase == "outbound" and state == defines.train_state.wait_station and current == 1 then
    resupply.phase = "station"
    resupply.station_tick = tick
  end
  if resupply.last_rail then
    if resupply.phase ~= "returning" and current == 2 then resupply.phase = "returning" end
    if resupply.phase ~= "returning" or state ~= defines.train_state.wait_station then return end
    resupply.arrive_tick = resupply.arrive_tick or tick
    if tick >= resupply.arrive_tick + shared.supply.arrive_wait then finish_resupply(record) end
    return
  end
  -- No frontier to go back to: the trip ends once the station has stocked the train or the wait times out.
  if resupply.phase == "station" and (rail_count(train) >= shared.supply.rail_full or tick >= resupply.station_tick + shared.supply.wait_ticks) then
    resupply.resume_cruise = false
    finish_resupply(record)
  end
end

local lay_rail = function(record, tick)
  local loco = record.entity
  local surface, position = loco.surface, loco.position
  local cardinal = cardinals[math.floor(loco.orientation * 4 + 0.5) % 4]
  local vector = cardinal.vector
  local best, best_reach
  for _, rail in pairs(surface.find_entities_filtered
  {
    type = rail_entity,
    position = frame.place(loco, {0, nose_reach}),
    radius = rail_search_radius
  }) do
    if rail.direction % 8 == cardinal.direction % 8 then
      local dx, dy = rail.position.x - position.x, rail.position.y - position.y
      local reach, lateral = dx * vector.x + dy * vector.y, dx * vector.y - dy * vector.x
      if math.abs(lateral) < 1 and (not best or reach > best_reach) then
        best, best_reach = rail, reach
      end
    end
  end
  if not best then return end
  local end_position = best.position
  -- Laying stays ahead of the train at any speed: once its nose overhangs the last rail, the next one can't be placed.
  for _ = 1, max_rails_per_lay do
    if best_reach >= lookahead then return end
    local next_position = {x = end_position.x + vector.x * rail_length, y = end_position.y + vector.y * rail_length}
    if not surface.can_place_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force} then return end
    if not take_rail(loco.train) then
      local resupply = not record.auto_resupply_off and rail_count(loco.train) < shared.supply.rail_low
      if resupply and begin_resupply(record) then return end
      if tick >= record.next_warn then
        record.next_warn = tick + warn_interval
        loco.force.print({"shay-message.out-of-rail"})
        if resupply then loco.force.print({"shay-message.no-supply-station"}) end
      end
      return
    end
    record.auto_resupply_off = nil
    record.last_rail = surface.create_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force, raise_built = true}
    end_position, best_reach = next_position, best_reach + rail_length
  end
end

local grind = function(record)
  local loco = record.entity
  local surface = loco.surface
  local from = frame.place(loco, shared.layer.grinder_offset)
  local forward = frame.forward(loco.orientation)
  local to = {x = from.x + forward.x * shared.layer.grind_reach, y = from.y + forward.y * shared.layer.grind_reach}
  local area =
  {
    {math.min(from.x, to.x) - grind_width, math.min(from.y, to.y) - grind_width},
    {math.max(from.x, to.x) + grind_width, math.max(from.y, to.y) + grind_width}
  }
  for _, rock in pairs(surface.find_entities_filtered{area = area, type = "simple-entity"}) do
    if rock.name:find("rock", 1, true) then
      local sound = "entity-mined/" .. rock.name
      if helpers.is_valid_sound_path(sound) then surface.play_sound{path = sound, position = rock.position} end
      for _, product in pairs(rock.prototype.mineable_properties.products or {}) do
        if product.type == "item" then store(loco.train, product.name, product.amount or product.amount_max) end
      end
      rock.die()
    end
  end
end

local show_grinder = function(record, moving)
  local loco = record.entity
  if not moving then
    if record.grinder and record.grinder.valid then record.grinder.destroy() end
    record.grinder = nil
    return
  end
  local target = {entity = loco, offset = frame.rotate(loco.orientation, shared.layer.grinder_offset)}
  if record.grinder and record.grinder.valid then
    record.grinder.target = target
    return
  end
  record.grinder = rendering.draw_animation
  {
    animation = shared.grinder_animation,
    target = target,
    surface = loco.surface,
    render_layer = "object",
    animation_speed = 0.5
  }
end

local update = function(record, tick)
  if record.resupply then
    step_resupply(record, tick)
    return
  end
  local loco = record.entity
  local train = loco.train
  local sign = heading(loco)
  if record.cruise and not overridden(train) then train.speed = shared.layer.cruise_speed * sign end
  show_grinder(record, train.speed ~= 0)
  if train.speed * sign <= 0 then return end
  if tick % shared.layer.rail_lay_interval == 0 then lay_rail(record, tick) end
  if tick % shared.layer.grind_interval == 0 then grind(record) end
end

local set_cruise = function(record, cruise)
  local train = record.entity.train
  if cruise then
    record.restore_manual = train.manual_mode
    train.manual_mode = true
  else
    train.manual_mode = record.restore_manual
    record.restore_manual = nil
  end
  record.cruise = cruise
end

local on_toggle_cruise = function(event)
  local player = game.get_player(event.player_index)
  local vehicle = player.vehicle
  if not (vehicle and vehicle.train) then return end
  local records = train_records(vehicle.train)
  if #records == 0 then return end
  local cruising = false
  for _, record in pairs(records) do
    if record.cruise then
      set_cruise(record, false)
      cruising = true
    end
  end
  if not cruising then set_cruise(records[1], true) end
  player.create_local_flying_text{text = {cruising and "shay-message.cruise-off" or "shay-message.cruise-on"}, create_at_cursor = true}
end

local on_resupply = function(event)
  local player = game.get_player(event.player_index)
  local vehicle = player.vehicle
  if not (vehicle and vehicle.train and vehicle.train.manual_mode) then return end
  local records = train_records(vehicle.train)
  if #records == 0 or records[1].resupply then return end
  local text = begin_resupply(records[1]) and {"shay-message.resupply-start"} or {"shay-message.no-supply-station"}
  player.create_local_flying_text{text = text, create_at_cursor = true}
end

local resupply_failed =
{
  [defines.train_state.no_path] = true,
  [defines.train_state.destination_full] = true
}

local check_resupply = function(train, record)
  local resupply = record.resupply
  if train.manual_mode then
    abort_resupply(record, {"shay-message.resupply-cancelled"}, false)
  elseif resupply_failed[train.state] then
    -- Automatic mode backs out of a dead end only with a locomotive facing the other way.
    local stuck = resupply.phase == "outbound" and #train.locomotives.back_movers == 0
    -- A failed trip won't fix itself, so the auto trigger stays off until rail is laid again; the hotkey still works.
    record.auto_resupply_off = true
    abort_resupply(record, stuck and {"shay-message.resupply-dead-end"} or {"shay-message.resupply-no-path", resupply.station}, resupply.resume_cruise)
  end
end

-- Switched to automatic (by the player or a schedule interrupt), the train is no longer ours to drive.
local on_train_changed_state = function(event)
  local train = event.train
  local records = train_records(train)
  if records[1] and records[1].resupply then
    check_resupply(train, records[1])
    return
  end
  if train.manual_mode then return end
  for _, record in pairs(records) do
    record.cruise = false
    record.restore_manual = nil
  end
end

local on_built = function(event)
  local entity = event.entity
  if entity.valid and entity.name == shared.layer_locomotive then add(entity) end
end

local on_entity_cloned = function(event)
  local entity = event.destination
  if entity.valid and entity.name == shared.layer_locomotive then add(entity) end
end

local on_removed = function(event)
  local entity = event.entity
  if entity.name == shared.layer_locomotive then remove(entity.unit_number) end
end

local on_object_destroyed = function(event)
  local unit_number = script_data.registrations[event.registration_number]
  if not unit_number then return end
  script_data.registrations[event.registration_number] = nil
  remove(unit_number)
end

local on_tick = function(event)
  for _, record in pairs(script_data.locos) do
    if record.entity.valid then update(record, event.tick) end
  end
end

local layer = {}

layer.on_init = function()
  storage.layer = {locos = {}, registrations = {}}
  script_data = storage.layer
end

layer.on_load = function()
  script_data = storage.layer
end

layer.events =
{
  [defines.events.on_tick] = on_tick,
  [shared.custom_input_cruise] = on_toggle_cruise,
  [shared.custom_input_resupply] = on_resupply,
  [defines.events.on_train_changed_state] = on_train_changed_state,
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

return layer

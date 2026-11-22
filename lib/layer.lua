local shared = require("shared")
local frame = require("lib.frame")

local rail_item, rail_entity, rail_type
local fill_item = "landfill"
local fill_tile = "landfill"
local rail_length = 2
local nose_reach = 3
local rail_search_radius = 6
local lookahead = nose_reach + 6
local max_rails_per_lay = 3
local warn_interval = 300

local cardinals =
{
  [0] = {vector = {x = 0, y = -1}, direction = defines.direction.north},
  [1] = {vector = {x = 1, y = 0}, direction = defines.direction.east},
  [2] = {vector = {x = 0, y = 1}, direction = defines.direction.south},
  [3] = {vector = {x = -1, y = 0}, direction = defines.direction.west}
}

local script_data

-- +1 when positive train speed carries this loco nose-first. Fixed by how the
-- loco sits in the consist, so it's cached per record and refreshed on train_created.
local heading = function(loco)
  for _, front_mover in pairs(loco.train.locomotives.front_movers) do
    if front_mover.unit_number == loco.unit_number then return 1 end
  end
  return -1
end

-- Entity names other mods asked about via remote.call("shay", "add_entity_to_trigger"):
-- the grinder raises on_robot_pre_mined before eating one. Lives in storage.layer too.
local triggers = {}

local add = function(loco)
  if script_data.locos[loco.unit_number] then return end
  script_data.locos[loco.unit_number] = {entity = loco, cruise = false, next_warn = 0, next_fill_warn = 0, heading = heading(loco)}
  script_data.registrations[script.register_on_object_destroyed(loco)] = loco.unit_number
end

local remove = function(unit_number)
  local record = script_data.locos[unit_number]
  if not record then return end
  script_data.locos[unit_number] = nil
  if record.grinder and record.grinder.valid then record.grinder.destroy() end
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

local take_item = function(train, name)
  for _, wagon in pairs(train.cargo_wagons) do
    if wagon.get_inventory(defines.inventory.cargo_wagon).remove{name = name, count = 1} == 1 then return true end
  end
  return false
end

local store = function(train, name, count)
  for _, wagon in pairs(train.cargo_wagons) do
    count = count - wagon.get_inventory(defines.inventory.cargo_wagon).insert{name = name, count = count}
    if count == 0 then return end
  end
end

-- Consumables the consist needs: low trips the auto-resupply, full is what the station waits for.
-- Built by resolve_rail once the configured rail item is known.
local supplies, supply_items

-- The rail item comes from the shay-rail-item startup setting; resolve it (and the
-- straight-rail entity it places) once per load so everything below stays item-agnostic.
local resolve_rail = function()
  local name = settings.startup[shared.rail_item_setting].value
  local item = prototypes.item[name]
  local result = item and item.place_result
  if not (result and result.type == "straight-rail") then
    error("Shay: " .. shared.rail_item_setting .. " '" .. name .. "' is not an item that places a straight rail")
  end
  rail_item, rail_entity, rail_type = name, result.name, result.type
  supplies =
  {
    [rail_item] = {low = shared.supply.rail_low, full = shared.supply.rail_full},
    [fill_item] = {low = shared.supply.fill_low, full = shared.supply.fill_full}
  }
  supply_items = {rail_item, fill_item}
end

local count_item = function(train, name)
  local count = 0
  for _, wagon in pairs(train.cargo_wagons) do
    count = count + wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count{name = name}
  end
  return count
end

-- Items under their auto-trip threshold, in supply_items order.
local low_supplies = function(train)
  local low = {}
  for _, name in pairs(supply_items) do
    if count_item(train, name) < supplies[name].low then low[#low + 1] = name end
  end
  return low
end

-- Everything the trip went for reached its stocked threshold.
local stocked = function(train, needs)
  for _, name in pairs(needs) do
    if count_item(train, name) < supplies[name].full then return false end
  end
  return true
end

-- Still under the stocked threshold: the station didn't fix what the trip went for.
local short = function(train, needs)
  for _, name in pairs(needs) do
    if count_item(train, name) < supplies[name].full then return true end
  end
  return false
end

local train_records = function(train)
  local records = {}
  for _, carriage in pairs(train.carriages) do
    local record = script_data.locos[carriage.unit_number]
    if record then records[#records + 1] = record end
  end
  return records
end

-- Auto-tripping is a consist decision: one record giving up (or resuming) applies to every Shay in the train.
local set_auto_resupply = function(train, off)
  for _, record in pairs(train_records(train)) do record.auto_resupply_off = off or nil end
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

local resupply_schedule = function(station, last_rail, needs)
  local wait_conditions = {}
  for _, name in pairs(needs) do
    wait_conditions[#wait_conditions + 1] = {type = "item_count", compare_type = "and", condition = {first_signal = {type = "item", name = name}, comparator = ">=", constant = supplies[name].full}}
  end
  wait_conditions[#wait_conditions + 1] = {type = "time", compare_type = "or", ticks = shared.supply.wait_ticks}
  local records =
  {
    {
      station = station,
      wait_conditions = wait_conditions
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
  -- A manual trigger restocks rail by default; the auto trigger asks only for what's low.
  local needs = low_supplies(train)
  if #needs == 0 then needs = {rail_item} end
  local resupply =
  {
    phase = "outbound",
    station = station,
    last_rail = last_rail,
    needs = needs,
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
  train.schedule = resupply_schedule(station, last_rail, needs)
  train.manual_mode = false
  return true
end

local finish_resupply = function(record)
  local resupply = record.resupply
  -- Came back still short of something it went for: the station can't fix this, so stop auto-tripping.
  local unfulfilled = short(record.entity.train, resupply.needs)
  if unfulfilled then set_auto_resupply(record.entity.train, true) end
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
  loco.force.print(unfulfilled and {"shay-message.resupply-unfulfilled"} or {"shay-message.resupply-done"})
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
  if resupply.phase == "station" and (stocked(train, resupply.needs) or tick >= resupply.station_tick + shared.supply.wait_ticks) then
    resupply.resume_cruise = false
    finish_resupply(record)
  end
end

-- Rail infrastructure is off the menu: the train needs the track it stands on, and a crossing line is a real "can't build through".
local rail_infrastructure =
{
  ["straight-rail"] = true, ["half-diagonal-rail"] = true,
  ["curved-rail-a"] = true, ["curved-rail-b"] = true,
  ["elevated-straight-rail"] = true, ["elevated-half-diagonal-rail"] = true,
  ["elevated-curved-rail-a"] = true, ["elevated-curved-rail-b"] = true,
  ["rail-ramp"] = true, ["rail-support"] = true,
  ["legacy-straight-rail"] = true, ["legacy-curved-rail"] = true,
  ["rail-signal"] = true, ["rail-chain-signal"] = true, ["train-stop"] = true
}

local rolling_stock = {locomotive = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true}
local support_entities = {[shared.cannon_turret] = true, [shared.mg_turret] = true, [shared.sentry_bot] = true}

-- The drill eats anything destructible — including our own poles and builds — except rail
-- infrastructure, our own consist, and the mod's script-driven support entities.
local grindable = function(record, entity)
  if not entity.destructible or rail_infrastructure[entity.type] or support_entities[entity.name] then return false end
  return not (rolling_stock[entity.type] and entity.train == record.entity.train)
end

local destroy_obstacle = function(record, entity)
  local loco = record.entity
  local surface = loco.surface
  local sound = "entity-mined/" .. entity.name
  if helpers.is_valid_sound_path(sound) then surface.play_sound{path = sound, position = entity.position} end
  for _, product in pairs(entity.prototype.mineable_properties.products or {}) do
    if product.type == "item" then store(loco.train, product.name, product.amount or product.amount_max) end
  end
  if triggers[entity.name] then script.raise_event(defines.events.on_robot_pre_mined, {entity = entity}) end
  entity.die()
  -- die() is a no-op on things without health (cliffs, resources): pull them out of the ground instead.
  if entity.valid then entity.destroy() end
end

-- Water under the next rail's 2x2 footprint gets landfill first; returns false while water is left unfilled.
local fill_water = function(record, tick, position)
  local loco = record.entity
  local water = loco.surface.find_tiles_filtered
  {
    area = {{position.x - 1, position.y - 1}, {position.x + 1, position.y + 1}},
    collision_mask = "water_tile"
  }
  if #water == 0 then return true end
  local tiles = {}
  for index, tile in pairs(water) do
    if not take_item(loco.train, fill_item) then break end
    set_auto_resupply(loco.train)
    tiles[index] = {name = fill_tile, position = tile.position}
  end
  if #tiles > 0 then loco.surface.set_tiles(tiles) end
  if #tiles == #water then return true end
  if tick >= record.next_fill_warn then
    record.next_fill_warn = tick + warn_interval
    loco.force.print({"shay-message.out-of-landfill"})
    if not record.auto_resupply_off then loco.force.print({"shay-message.no-supply-station"}) end
  end
  return false
end

local lay_rail = function(record, tick)
  local loco = record.entity
  -- About to run out of something it needs: head back to the supply station while there's still some in the cargo.
  if not record.auto_resupply_off and #low_supplies(loco.train) > 0 and begin_resupply(record) then return end
  local surface, position = loco.surface, loco.position
  local cardinal = cardinals[math.floor(loco.orientation * 4 + 0.5) % 4]
  local vector = cardinal.vector
  local best, best_reach
  for _, rail in pairs(surface.find_entities_filtered
  {
    type = rail_type,
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
    if not fill_water(record, tick, next_position) then return end
    if not surface.can_place_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force} then
      -- Only eat what the rail would actually collide with: the exact 2x2 cell, so trackside builds are never touched.
      local area = {{next_position.x - 1, next_position.y - 1}, {next_position.x + 1, next_position.y + 1}}
      for _, entity in pairs(surface.find_entities_filtered{area = area}) do
        if grindable(record, entity) then destroy_obstacle(record, entity) end
      end
      if not surface.can_place_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force} then return end
    end
    if not take_item(loco.train, rail_item) then
      if tick >= record.next_warn then
        record.next_warn = tick + warn_interval
        loco.force.print({"shay-message.out-of-rail"})
        if not record.auto_resupply_off then loco.force.print({"shay-message.no-supply-station"}) end
      end
      return
    end
    set_auto_resupply(loco.train)
    record.last_rail = surface.create_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force, raise_built = true}
    end_position, best_reach = next_position, best_reach + rail_length
  end
end

-- The drill is bolted to the nose: always drawn while the loco has a record, spinning only when pushing.
-- An entity-bound target follows the stock on its own, so the render object only
-- hears about real orientation changes — a parked or straight-running train writes nothing.
local show_grinder = function(record, moving)
  local loco = record.entity
  if record.grinder and record.grinder.valid then
    if loco.orientation ~= record.grinder_orientation then
      record.grinder_orientation = loco.orientation
      record.grinder.target = {entity = loco, offset = frame.rotate(loco.orientation, shared.layer.grinder_visual_offset)}
      -- The drill art points south; rotate it to face away from the locomotive nose.
      record.grinder.orientation = (loco.orientation + 0.5) % 1
    end
    local spin = moving and 0.5 or 0
    if record.grinder.animation_speed ~= spin then record.grinder.animation_speed = spin end
    if record.grinder.render_layer ~= "higher-object-above" then record.grinder.render_layer = "higher-object-above" end
    return
  end
  record.grinder_orientation = loco.orientation
  record.grinder = rendering.draw_animation
  {
    animation = shared.grinder_animation,
    target = {entity = loco, offset = frame.rotate(loco.orientation, shared.layer.grinder_visual_offset)},
    surface = loco.surface,
    render_layer = "higher-object-above",
    orientation = (loco.orientation + 0.5) % 1,
    animation_speed = moving and 0.5 or 0
  }
end

-- Moving forward, or trying to: cruise pushes, or a passenger holds accelerate into an obstacle.
-- A train pressed against a tree reads ~0 speed, so gating the grinder on speed alone deadlocks it.
local pushing_forward = function(record, sign)
  local train = record.entity.train
  local speed = train.speed * sign
  if speed ~= 0 then return speed > 0 end
  if record.cruise then return true end
  for _, player in pairs(train.passengers) do
    if player.riding_state.acceleration == defines.riding.acceleration.accelerating then return true end
  end
  return false
end

local update = function(record, tick)
  if record.resupply then
    step_resupply(record, tick)
    return
  end
  local loco = record.entity
  local train = loco.train
  -- Records from before the cache existed pick their sign up on the first tick.
  local sign = record.heading
  if not sign then sign = heading(loco); record.heading = sign end
  if record.cruise and not overridden(train) then train.speed = shared.layer.cruise_speed * sign end
  local pushing = pushing_forward(record, sign)
  show_grinder(record, pushing)
  if not pushing then return end
  if tick % shared.layer.rail_lay_interval == 0 then lay_rail(record, tick) end
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

local on_toggle_manual = function(event)
  local player = game.get_player(event.player_index)
  local vehicle = player.vehicle
  if not (vehicle and vehicle.train) then return end
  local records = train_records(vehicle.train)
  if #records == 0 then return end
  -- A resupply trip runs automatic on a parked schedule, so grabbing the wheel
  -- mid-trip is a takeover: cancel through the same path check_resupply uses
  -- for any other manual intervention instead of toggling under the trip.
  if records[1].resupply then
    abort_resupply(records[1], {"shay-message.resupply-cancelled"}, false)
    return
  end
  local train = vehicle.train
  train.manual_mode = not train.manual_mode
  player.force.print(train.manual_mode and {"shay-message.manual-on"} or {"shay-message.manual-off"})
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
    set_auto_resupply(train, true)
    abort_resupply(record, stuck and {"shay-message.resupply-dead-end"} or {"shay-message.resupply-no-path", resupply.station}, resupply.resume_cruise)
  end
end

-- Coupling or splitting rebuilds the consist: cached front-mover signs go stale.
local on_train_created = function(event)
  for _, record in pairs(train_records(event.train)) do record.heading = heading(record.entity) end
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

-- Custom inputs are prototypes: a Factorio process started before an input
-- existed never learns it, and get_event_id hard-errors. Resolve by id so a
-- stale process loses the hotkey instead of crashing the save load.
local custom_inputs =
{
  [shared.custom_input_cruise] = on_toggle_cruise,
  [shared.custom_input_resupply] = on_resupply,
  [shared.custom_input_manual] = on_toggle_manual
}

local register_inputs = function()
  for name, handler in pairs(custom_inputs) do
    local ok, id = pcall(script.get_event_id, name)
    if ok then script.on_event(id, handler) end
  end
end

layer.on_init = function()
  storage.layer = {locos = {}, registrations = {}, triggers = triggers}
  script_data = storage.layer
  resolve_rail()
  register_inputs()
end

layer.on_load = function()
  script_data = storage.layer
  -- Registrations made before this on_load and ones recovered from storage merge here.
  script_data.triggers = script_data.triggers or {}
  for name in pairs(triggers) do script_data.triggers[name] = true end
  triggers = script_data.triggers
  resolve_rail()
  register_inputs()
end

-- FARL parity: other mods register entity names so the grinder raises
-- on_robot_pre_mined before destroying them. control.lua exposes this as remote "shay".
layer.remote =
{
  add_entity_to_trigger = function(name)
    if not prototypes.entity[name] then return end
    triggers[name] = true
    return true
  end,

  remove_entity_from_trigger = function(name)
    if not triggers[name] then return end
    triggers[name] = nil
    return true
  end,

  get_trigger_list = function()
    return triggers
  end
}

layer.events =
{
  [defines.events.on_tick] = on_tick,
  [defines.events.on_train_changed_state] = on_train_changed_state,
  [defines.events.on_train_created] = on_train_created,
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

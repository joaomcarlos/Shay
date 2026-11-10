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
      if tick >= record.next_warn then
        record.next_warn = tick + warn_interval
        loco.force.print({"shay-message.out-of-rail"})
      end
      return
    end
    surface.create_entity{name = rail_entity, position = next_position, direction = cardinal.direction, force = loco.force, raise_built = true}
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

local train_records = function(train)
  local records = {}
  for _, carriage in pairs(train.carriages) do
    local record = script_data.locos[carriage.unit_number]
    if record then records[#records + 1] = record end
  end
  return records
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

-- Switched to automatic (by the player or a schedule interrupt), the train is no longer ours to drive.
local on_train_changed_state = function(event)
  local train = event.train
  if train.manual_mode then return end
  for _, record in pairs(train_records(train)) do
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

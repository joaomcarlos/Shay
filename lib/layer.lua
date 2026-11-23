local shared = require("shared")
local frame = require("lib.frame")

local rail_item, rail_entity, rail_type
local fill_item = "landfill"
local cliff_item = "cliff-explosives"
local fill_tile = "landfill"
local pave_item = "concrete"
local pave_tile = "concrete"
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

local add = function(loco, player_index)
  if script_data.locos[loco.unit_number] then return end
  script_data.locos[loco.unit_number] = {entity = loco, player_index = player_index, cruise = false, next_warn = 0, next_fill_warn = 0, next_demolish_warn = 0, next_cliff_warn = 0, next_pave_warn = 0, relaid = {}, heading = heading(loco)}
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

-- Cruise speed is per-player: a riding player's setting drives the consist, and driverless
-- the player who last toggled cruise does. Nobody ever did: the shared default.
local cruise_speed = function(record)
  local player = record.entity.train.passengers[1]
  if not player and record.player_index then player = game.get_player(record.player_index) end
  if not player then return shared.layer.cruise_speed end
  return player.mod_settings[shared.setting_cruise_speed].value
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
    [fill_item] = {low = shared.supply.fill_low, full = shared.supply.fill_full},
    [cliff_item] = {low = shared.supply.cliff_low, full = shared.supply.cliff_full},
    [pave_item] = {low = shared.supply.pave_low, full = shared.supply.pave_full}
  }
  supply_items = {rail_item, fill_item, cliff_item, pave_item}
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

local demolish_span = 10
local demolish_corridor = 4
local carriage_half = 3.5
local consist_rail_radius = 4.5

-- What demolition is allowed to pull up: the line itself plus its trackside furniture.
-- Everything else in rail_infrastructure (curves, elevated track, ramps, stations) stays:
-- the mod cannot rebuild it, so tearing it out would only strand the consist.
local demolishable_types =
{
  ["straight-rail"] = true,
  ["rail-signal"] = true, ["rail-chain-signal"] = true,
  ["electric-pole"] = true, ["lamp"] = true, ["wall"] = true
}
local demolish_scan = {}
for entity_type in pairs(demolishable_types) do demolish_scan[#demolish_scan + 1] = entity_type end

-- The rails the consist physically stands on are never demolition targets. A radius
-- sweep stays correct at any orientation; a bounding-box area would not.
local consist_rails = function(record)
  local protected = {}
  for _, carriage in pairs(record.entity.train.carriages) do
    for _, rail in pairs(record.entity.surface.find_entities_filtered{position = carriage.position, radius = consist_rail_radius, type = rail_entity}) do
      protected[rail] = true
    end
  end
  return protected
end

local can_demolish = function(record, entity, protected)
  if not entity.destructible or not demolishable_types[entity.type] or support_entities[entity.name] then return false end
  if entity.force ~= record.entity.force then return false end
  return not protected[entity]
end

-- Every product of one entity must fit before it is touched: a torn-up rail that
-- cannot come aboard leaves a gap the train cannot cross.
local can_store = function(train, products)
  local needed = {}
  for _, product in pairs(products or {}) do
    if product.type == "item" then needed[product.name] = (needed[product.name] or 0) + (product.amount or product.amount_max or 1) end
  end
  for name, count in pairs(needed) do
    for _, wagon in pairs(train.cargo_wagons) do
      count = count - wagon.get_inventory(defines.inventory.cargo_wagon).get_insertable_count(name)
      if count <= 0 then break end
    end
    if count > 0 then return false end
  end
  return true
end

-- One teardown pass shared by both demolition modes: direction 1 sweeps the corridor
-- ahead of the consist along its heading, -1 sweeps behind it. Rails are taken only
-- from the consist's own line; everything else goes from the trackside corridor.
local demolish = function(record, tick, direction)
  local loco = record.entity
  local train = loco.train
  local forward = frame.forward(loco.orientation)
  local sign = heading(loco)
  local dir = {x = forward.x * sign, y = forward.y * sign}
  local right = {x = -dir.y, y = dir.x}
  local project = function(position)
    local dx, dy = position.x - loco.position.x, position.y - loco.position.y
    return dx * dir.x + dy * dir.y, dx * right.x + dy * right.y
  end
  local front, rear = -math.huge, math.huge
  for _, carriage in pairs(train.carriages) do
    local reach = project(carriage.position)
    front, rear = math.max(front, reach), math.min(rear, reach)
  end
  front, rear = front + carriage_half, rear - carriage_half

  -- Relaid rails are immune until the consist has rolled over them. Without the marks
  -- maintenance would eat its own fresh track and relay it again every pass forever.
  record.relaid = record.relaid or {}
  for id, rail in pairs(record.relaid) do
    if not (rail.valid and project(rail.position) >= rear) then record.relaid[id] = nil end
  end

  local protected = consist_rails(record)
  local near = direction > 0 and front or rear - demolish_span
  local far = direction > 0 and front + demolish_span or rear
  local left_top, right_bottom = {x = math.huge, y = math.huge}, {x = -math.huge, y = -math.huge}
  for _, reach in pairs{near, far} do
    for _, lateral in pairs{-demolish_corridor, demolish_corridor} do
      local corner = {x = loco.position.x + dir.x * reach + right.x * lateral, y = loco.position.y + dir.y * reach + right.y * lateral}
      left_top.x, left_top.y = math.min(left_top.x, corner.x), math.min(left_top.y, corner.y)
      right_bottom.x, right_bottom.y = math.max(right_bottom.x, corner.x), math.max(right_bottom.y, corner.y)
    end
  end
  local cargo_full = false
  for _, entity in pairs(loco.surface.find_entities_filtered{area = {left_top, right_bottom}, type = demolish_scan}) do
    local reach, lateral = project(entity.position)
    local on_line = entity.type == rail_entity and math.abs(lateral) < 1
    local trackside = entity.type ~= rail_entity and math.abs(lateral) <= demolish_corridor
    if reach >= near and reach <= far and (on_line or trackside)
      and can_demolish(record, entity, protected) and not record.relaid[entity.unit_number] then
      if can_store(train, entity.prototype.mineable_properties.products) then
        destroy_obstacle(record, entity)
      else
        cargo_full = true
      end
    end
  end
  if cargo_full and tick >= record.next_demolish_warn then
    record.next_demolish_warn = tick + warn_interval
    loco.force.print({"shay-message.demolish-cargo-full"})
  end
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

-- Tiles already at least as good as concrete: paving never downgrades or rewrites them.
local keep_tile =
{
  ["concrete"] = true,
  ["hazard-concrete-left"] = true, ["hazard-concrete-right"] = true,
  ["refined-concrete"] = true,
  ["refined-hazard-concrete-left"] = true, ["refined-hazard-concrete-right"] = true,
  ["foundation"] = true, ["ice-platform"] = true, ["space-platform-foundation"] = true,
  ["artificial-yumako-soil"] = true, ["artificial-jellynut-soil"] = true,
  ["overgrowth-yumako-soil"] = true, ["overgrowth-jellynut-soil"] = true
}

-- Concrete under and around a just-laid rail: the 2x2 footprint plus pave_width on each side.
-- Short cargo leaves the rest unpaved and never stops laying; water cells outside the footprint
-- (fill_water already landfilled the footprint itself) are left alone.
local pave = function(record, tick, position)
  local loco = record.entity
  local surface = loco.surface
  local width = shared.layer.pave_width
  local left, right = position.x - 1 - width, position.x + width
  local top, bottom = position.y - 1 - width, position.y + width
  local water = {}
  for _, tile in pairs(surface.find_tiles_filtered{area = {{left, top}, {right + 1, bottom + 1}}, collision_mask = "water_tile"}) do
    water[tile.position.x .. "," .. tile.position.y] = true
  end
  local tiles, ran_out = {}, false
  for x = left, right do
    for y = top, bottom do
      if not water[x .. "," .. y] and not keep_tile[surface.get_tile{x = x, y = y}.name] then
        if take_item(loco.train, pave_item) then
          tiles[#tiles + 1] = {name = pave_tile, position = {x = x, y = y}}
        else
          ran_out = true
        end
      end
    end
  end
  if #tiles > 0 then surface.set_tiles(tiles) end
  if ran_out and tick >= record.next_pave_warn then
    record.next_pave_warn = tick + warn_interval
    loco.force.print({"shay-message.out-of-concrete"})
    if not record.auto_resupply_off then loco.force.print({"shay-message.no-supply-station"}) end
  end
end

-- A rail cell that fails placement gets only its exact 2x2 footprint eaten, then one retry —
-- trackside builds are never touched. Still blocked: perpendicular track or rail
-- infrastructure the drill won't take.
local cell_clear = function(record, tick, position, direction)
  local loco = record.entity
  local surface, force = loco.surface, loco.force
  if surface.can_place_entity{name = rail_entity, position = position, direction = direction, force = force} then return true end
  local area = {{position.x - 1, position.y - 1}, {position.x + 1, position.y + 1}}
  for _, entity in pairs(surface.find_entities_filtered{area = area}) do
    -- Cliffs are indestructible so the drill can't eat them: the layer burns
    -- an explosive per cliff, corrected like a player-thrown charge would.
    if entity.type == "cliff" then
      if not take_item(loco.train, cliff_item) then
        if tick >= record.next_cliff_warn then
          record.next_cliff_warn = tick + warn_interval
          loco.force.print({"shay-message.out-of-cliff-explosives"})
          if not record.auto_resupply_off then loco.force.print({"shay-message.no-supply-station"}) end
        end
        return false
      end
      set_auto_resupply(loco.train)
      entity.destroy{do_cliff_correction = true}
    elseif grindable(record, entity) then
      destroy_obstacle(record, entity)
    end
  end
  return surface.can_place_entity{name = rail_entity, position = position, direction = direction, force = force}
end

-- Lane config is per-player: a riding player's settings drive the consist, and driverless
-- the player who last toggled cruise does. Nobody ever did: a single track.
local lane_config = function(record)
  local player = record.entity.train.passengers[1]
  if not player and record.player_index then player = game.get_player(record.player_index) end
  if not player then return shared.layer.lanes, shared.layer.lane_spacing end
  local spacing = player.mod_settings[shared.setting_lane_spacing].value
  -- Rail centres tile every 2: odd spacings drop to the next even distance.
  return player.mod_settings[shared.setting_lanes].value, math.max(2, spacing - spacing % 2)
end

-- Lateral offset of lane n beside a step of the main lane, in stock-local {side, forward}
-- space: lane 1 sits `spacing` right of the centreline, lane 2 the same left, and the next
-- pair a spacing further out. The offset lands on the rail grid — cardinal steps need even
-- tiles, and diagonal steps (a straight with equal |dx|, |dy|) sit a whole number of (2,2)
-- cells off, so the perpendicular distance snaps to multiples of 2*sqrt(2). Taking the step
-- vector keeps this valid once the frontier travels the continuation table: a parallel
-- straight shares the main lane's direction.
local lane_offset = function(step_x, step_y, n, spacing)
  local side = n % 2 == 1 and 1 or -1
  local lanes_out = math.ceil(n / 2)
  if step_x ~= 0 and step_y ~= 0 then
    local grid = math.max(1, math.floor(lanes_out * spacing / (2 * math.sqrt(2)) + 0.5))
    local offset = 2 * grid * side
    return {x = -offset * (step_y > 0 and 1 or -1), y = offset * (step_x > 0 and 1 or -1)}
  end
  local length = math.sqrt(step_x * step_x + step_y * step_y)
  local distance = lanes_out * spacing * side
  return {x = -step_y / length * distance, y = step_x / length * distance}
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
  local lanes, spacing = lane_config(record)
  -- Laying stays ahead of the train at any speed: once its nose overhangs the last rail, the next one can't be placed.
  for _ = 1, max_rails_per_lay do
    if best_reach >= lookahead then return end
    local next_position = {x = end_position.x + vector.x * rail_length, y = end_position.y + vector.y * rail_length}
    -- The row resolves before a rail leaves the cargo: the main cell always, plus each offset
    -- lane cell that can take one. A lane still blocked after its footprint is eaten —
    -- a crossing line or rail infrastructure — is skipped while the main lane continues.
    if not fill_water(record, tick, next_position) then return end
    if not cell_clear(record, tick, next_position, cardinal.direction) then return end
    local cells = {next_position}
    for n = 1, lanes - 1 do
      local offset = lane_offset(vector.x * rail_length, vector.y * rail_length, n, spacing)
      local lane_position = {x = next_position.x + offset.x, y = next_position.y + offset.y}
      if not fill_water(record, tick, lane_position) then return end
      if cell_clear(record, tick, lane_position, cardinal.direction) then cells[#cells + 1] = lane_position end
    end
    -- Rows lay whole or not at all: short stock warns and stops the batch instead of
    -- leaving a gap in an offset lane that nothing comes back to fill.
    if count_item(loco.train, rail_item) < #cells then
      if tick >= record.next_warn then
        record.next_warn = tick + warn_interval
        loco.force.print({"shay-message.out-of-rail"})
        if not record.auto_resupply_off then loco.force.print({"shay-message.no-supply-station"}) end
      end
      return
    end
    for index, cell in ipairs(cells) do
      assert(take_item(loco.train, rail_item))
      local rail = surface.create_entity{name = rail_entity, position = cell, direction = cardinal.direction, force = loco.force, raise_built = true}
      -- The main lane stays the frontier marker the resupply trip returns to.
      if index == 1 then record.last_rail = rail end
      if record.mode == "maintenance" then record.relaid[rail.unit_number] = rail end
      pave(record, tick, cell)
    end
    set_auto_resupply(loco.train)
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
  if record.cruise and not overridden(train) then train.speed = cruise_speed(record) * sign end
  local pushing = pushing_forward(record, sign)
  show_grinder(record, pushing)
  if not pushing then return end
  if tick % shared.layer.rail_lay_interval ~= 0 then return end
  if record.mode == "off" then return end
  if record.mode == "bulldozer" then
    demolish(record, tick, -1)
  elseif record.mode == "maintenance" then
    demolish(record, tick, 1)
    lay_rail(record, tick)
  else
    lay_rail(record, tick)
  end
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
  records[1].player_index = event.player_index
  player.create_local_flying_text{text = {cruising and "shay-message.cruise-off" or "shay-message.cruise-on"}, create_at_cursor = true}
end

local demolition_modes = {"lay", "bulldozer", "maintenance", "off"}

local on_demolition_mode = function(event)
  local player = game.get_player(event.player_index)
  local vehicle = player.vehicle
  if not (vehicle and vehicle.train) then return end
  local records = train_records(vehicle.train)
  if #records == 0 then return end
  local next_index = 1
  for index, mode in ipairs(demolition_modes) do
    if mode == (records[1].mode or "lay") then next_index = index % #demolition_modes + 1 end
  end
  local mode = demolition_modes[next_index]
  for _, record in pairs(records) do record.mode = mode ~= "lay" and mode or nil end
  records[1].entity.force.print({"shay-message.mode-" .. mode})
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
  if entity.valid and entity.name == shared.layer_locomotive then add(entity, event.player_index) end
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
  -- Saves without a trigger list acquire it here, never during read-only on_load.
  if not script_data.triggers then script_data.triggers = triggers end
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
  [shared.custom_input_manual] = on_toggle_manual,
  [shared.custom_input_demolition] = on_demolition_mode
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
  triggers = script_data.triggers or {}
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

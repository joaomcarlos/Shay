local shared = require("shared")
local frame = require("lib.frame")

local refill_interval = 60
local refill_count = 10
local ammo =
{
  [shared.cannon_turret] = "cannon-shell",
  [shared.mg_turret] = "firearm-magazine"
}

local script_data

-- Sweep state is derived from the records, so it stays out of storage and is
-- rebuilt on every load; only the entities in it are persisted (via records).
local refill_queue = {}
local refill_index = 1

local arm = function(stock)
  if script_data.stock[stock.unit_number] then return end
  local record = {entity = stock, turrets = {}}
  for slot, hardpoint in pairs(shared.turrets[stock.name]) do
    local turret = stock.surface.create_entity
    {
      name = hardpoint.entity,
      position = frame.place(stock, hardpoint.offset),
      force = stock.force
    }
    turret.get_inventory(defines.inventory.turret_ammo).insert{name = ammo[hardpoint.entity], count = refill_count}
    record.turrets[slot] = turret
    refill_queue[#refill_queue + 1] = turret
    script_data.registrations[script.register_on_object_destroyed(turret)] = {stock = stock.unit_number, slot = slot}
  end
  script_data.stock[stock.unit_number] = record
  script_data.registrations[script.register_on_object_destroyed(stock)] = {stock = stock.unit_number}
end

local disarm = function(unit_number)
  local record = script_data.stock[unit_number]
  if not record then return end
  script_data.stock[unit_number] = nil
  for _, turret in pairs(record.turrets) do
    if turret.valid then turret.destroy() end
  end
end

local on_built = function(event)
  local entity = event.entity
  if entity.valid and shared.turrets[entity.name] then arm(entity) end
end

local on_entity_cloned = function(event)
  local entity = event.destination
  if not entity.valid then return end
  if shared.turrets[entity.name] then
    arm(entity)
  elseif ammo[entity.name] then
    entity.destroy()
  end
end

local on_removed = function(event)
  local entity = event.entity
  if shared.turrets[entity.name] then disarm(entity.unit_number) end
end

local on_object_destroyed = function(event)
  local registration = script_data.registrations[event.registration_number]
  if not registration then return end
  script_data.registrations[event.registration_number] = nil
  if registration.slot then
    local record = script_data.stock[registration.stock]
    if record then record.turrets[registration.slot] = nil end
    return
  end
  disarm(registration.stock)
end

-- One refill sweep takes refill_interval ticks: each tick checks a slice of the
-- queue, so the scan never lands on one tick no matter how many turrets exist.
local refill_step = function()
  local queue = refill_queue
  local count = #queue
  if count == 0 then return end
  local budget = math.ceil(count / refill_interval)
  local index = refill_index
  local processed = 0
  while processed < budget and count > 0 do
    if index > count then index = 1 end
    local turret = queue[index]
    if turret.valid then
      local inventory = turret.get_inventory(defines.inventory.turret_ammo)
      if inventory.is_empty() then inventory.insert{name = ammo[turret.name], count = refill_count} end
      index = index + 1
      processed = processed + 1
    else
      -- Dead turrets come out by swap-with-last so the sweep stays dense.
      queue[index] = queue[count]
      queue[count] = nil
      count = count - 1
    end
  end
  refill_index = index
end

local teleport_position = {x = 0, y = 0}

-- Turrets aim themselves; only their position follows the stock. A stock only turns while it moves.
local on_tick = function()
  for _, record in pairs(script_data.stock) do
    local stock = record.entity
    if stock.valid and stock.speed ~= 0 then
      local hardpoints = shared.turrets[stock.name]
      for slot, turret in pairs(record.turrets) do
        if turret.valid then turret.teleport(frame.place_into(stock, hardpoints[slot].offset, teleport_position)) end
      end
    end
  end
  refill_step()
end

local turrets = {}

turrets.on_init = function()
  storage.turrets = {stock = {}, registrations = {}}
  script_data = storage.turrets
  refill_queue = {}
  refill_index = 1
end

-- on_load may only read storage: the sweep queue is rebuilt from the records,
-- which also covers saves from before the queue existed.
turrets.on_load = function()
  script_data = storage.turrets
  refill_queue = {}
  for _, record in pairs(script_data.stock) do
    for _, turret in pairs(record.turrets) do
      refill_queue[#refill_queue + 1] = turret
    end
  end
  refill_index = 1
end

turrets.events =
{
  [defines.events.on_tick] = on_tick,
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

return turrets

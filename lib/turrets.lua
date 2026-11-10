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

-- Turrets aim themselves; only their position follows the stock. A stock only turns while it moves.
local on_tick = function()
  for _, record in pairs(script_data.stock) do
    local stock = record.entity
    if stock.valid and stock.speed ~= 0 then
      local hardpoints = shared.turrets[stock.name]
      for slot, turret in pairs(record.turrets) do
        if turret.valid then turret.teleport(frame.place(stock, hardpoints[slot].offset)) end
      end
    end
  end
end

local refill = function()
  for _, record in pairs(script_data.stock) do
    for _, turret in pairs(record.turrets) do
      if turret.valid then
        local inventory = turret.get_inventory(defines.inventory.turret_ammo)
        if inventory.is_empty() then inventory.insert{name = ammo[turret.name], count = refill_count} end
      end
    end
  end
end

local turrets = {}

turrets.on_init = function()
  storage.turrets = {stock = {}, registrations = {}}
  script_data = storage.turrets
end

turrets.on_load = function()
  script_data = storage.turrets
end

turrets.on_nth_tick =
{
  [refill_interval] = refill
}

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

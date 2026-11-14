local shared = require("shared")

-- Rolling-stock prototypes carry the thumbnail tint as their default colour, but nothing
-- copies it onto the entity at placement time — paint it here so every Shay rolls out coloured.
local paint = function(entity)
  local color = entity.valid and shared.colors[entity.name]
  if color then entity.color = color end
end

local on_built = function(event) paint(event.entity) end

local on_entity_cloned = function(event) paint(event.destination) end

local stock = {}

stock.events =
{
  [defines.events.on_built_entity] = on_built,
  [defines.events.on_robot_built_entity] = on_built,
  [defines.events.script_raised_built] = on_built,
  [defines.events.script_raised_revive] = on_built,
  [defines.events.on_entity_cloned] = on_entity_cloned
}

return stock

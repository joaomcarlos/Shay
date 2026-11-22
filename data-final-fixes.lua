local shared = require("shared")

-- Fail the mod load here if the chosen rail item can't place a straight rail, before a
-- save ships the mistake to on_init. Runs in final fixes so every mod's items exist.
local name = settings.startup[shared.rail_item_setting].value
local item
for _, protos in pairs(data.raw) do
  local prototype = protos[name]
  if type(prototype) == "table" and prototype.place_result then
    item = prototype
    break
  end
end
if not (item and data.raw["straight-rail"][item.place_result]) then
  error("Shay: " .. shared.rail_item_setting .. " '" .. name .. "' is not an item that places a straight rail")
end

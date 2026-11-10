local shared = require("shared")

-- Armor category, so personal roboports, batteries and solar panels fit.
data:extend
{
  {
    type = "equipment-grid",
    name = shared.layer.equipment_grid,
    width = 6,
    height = 4,
    equipment_categories = {"armor"}
  }
}

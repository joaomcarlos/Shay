local util = require("util")
local shared = require("shared")

local stock = {}

-- Body, train-colour mask and shadow, 16 directions, from graphics/entity/<name>/.
function stock.pictures(name)
  local path = shared.graphics_dir .. name .. "/" .. name
  local function layer(suffix, extra)
    local options =
    {
      priority = "very-low",
      allow_low_quality_rotation = true,
      direction_count = shared.direction_count,
      scale = 0.5,
      usage = "train"
    }
    for k, v in pairs(extra or {}) do options[k] = v end
    return util.sprite_load(path .. suffix, options)
  end
  return
  {
    rotated =
    {
      layers =
      {
        layer(""),
        layer("-mask", {flags = {"mask"}, apply_runtime_tint = true, tint_as_overlay = true}),
        layer("-shadow", {flags = {"shadow"}, draw_as_shadow = true})
      }
    }
  }
end

-- A vanilla rolling stock entity renamed, with its own item and recipe cloned from the vanilla ones.
function stock.clone(entity_type, vanilla, name)
  local entity = table.deepcopy(data.raw[entity_type][vanilla])
  entity.name = name
  entity.icon = "__Shay__/graphics/icons/" .. name .. ".png"
  entity.minable = {mining_time = 0.5, result = name}
  entity.pictures = stock.pictures(name)

  local item = table.deepcopy(data.raw["item-with-entity-data"][vanilla])
  item.name = name
  item.icon = entity.icon
  item.place_result = name

  local recipe = table.deepcopy(data.raw.recipe[vanilla])
  recipe.name = name
  recipe.results = {{type = "item", name = name, amount = 1}}
  recipe.enabled = true

  data:extend{entity, item, recipe}
  return entity
end

return stock

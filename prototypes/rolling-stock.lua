local util = require("util")
local shared = require("shared")

local stock = {}

-- Body, train-colour mask and shadow, 16 directions, from graphics/entity/<name>/.
function stock.pictures(name, back_equals_front)
  local path = shared.graphics_dir .. name .. "/" .. name
  local function layer(suffix, extra)
    local options =
    {
      priority = "very-low",
      allow_low_quality_rotation = true,
      direction_count = shared.direction_count,
      back_equals_front = back_equals_front,
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
  entity.color = shared.colors[name]
  -- Sampled wagon sheets cover half a turn, just like their vanilla source.
  entity.pictures = stock.pictures(name, entity.pictures.rotated.layers[1].back_equals_front)
  -- Shay locomotives run fuel-free: a void energy source drives them at full power with no inventory.
  if entity_type == "locomotive" then entity.energy_source = {type = "void"} end

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

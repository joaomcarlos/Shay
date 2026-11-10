local util = require("util")

local DIRECTIONS = 16
local graphics = "__Shay__/graphics/entity/shay-gun-locomotive/"

local loco = table.deepcopy(data.raw.locomotive["locomotive"])
loco.name = "shay-gun-locomotive"
loco.minable = {mining_time = 0.5, result = "shay-gun-locomotive"}
loco.pictures =
{
  rotated =
  {
    layers =
    {
      util.sprite_load(graphics .. "shay-gun-locomotive",
      {
        priority = "very-low",
        allow_low_quality_rotation = true,
        direction_count = DIRECTIONS,
        scale = 0.5,
        usage = "train"
      }),
      util.sprite_load(graphics .. "shay-gun-locomotive-mask",
      {
        priority = "very-low",
        flags = {"mask"},
        apply_runtime_tint = true,
        tint_as_overlay = true,
        allow_low_quality_rotation = true,
        direction_count = DIRECTIONS,
        scale = 0.5,
        usage = "train"
      }),
      util.sprite_load(graphics .. "shay-gun-locomotive-shadow",
      {
        priority = "very-low",
        flags = {"shadow"},
        draw_as_shadow = true,
        allow_low_quality_rotation = true,
        direction_count = DIRECTIONS,
        scale = 0.5,
        usage = "train"
      })
    }
  }
}
data:extend{loco}

local item = table.deepcopy(data.raw["item-with-entity-data"]["locomotive"])
item.name = "shay-gun-locomotive"
item.place_result = "shay-gun-locomotive"
data:extend{item}

local recipe = table.deepcopy(data.raw.recipe["locomotive"])
recipe.name = "shay-gun-locomotive"
recipe.results = {{type = "item", name = "shay-gun-locomotive", amount = 1}}
recipe.enabled = true
data:extend{recipe}

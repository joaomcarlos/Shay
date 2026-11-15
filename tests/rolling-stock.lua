-- Run from the mod root: lua tests/rolling-stock.lua
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

table.deepcopy = copy
package.preload.util = function()
  return {sprite_load = function(path, options)
    local sprite = copy(options)
    sprite.filename = path
    return sprite
  end}
end

local function source(back_equals_front)
  return {pictures = {rotated = {layers = {
    {back_equals_front = back_equals_front},
    {back_equals_front = back_equals_front},
    {back_equals_front = back_equals_front}
  }}}}
end

data = {
  raw = {
    ["cargo-wagon"] = {["cargo-wagon"] = source(true)},
    locomotive = {locomotive = source(nil)},
    ["item-with-entity-data"] = {["cargo-wagon"] = {}, locomotive = {}},
    recipe = {["cargo-wagon"] = {}, locomotive = {}}
  },
  extend = function() end
}

local stock = require("prototypes.rolling-stock")
local shared = require("shared")
for _, case in ipairs{
  {"cargo-wagon", "cargo-wagon", shared.mg_wagon, true},
  {"cargo-wagon", "cargo-wagon", shared.ramp_wagon, true},
  {"locomotive", "locomotive", shared.layer_locomotive},
  {"locomotive", "locomotive", shared.gun_locomotive}
} do
  local entity = stock.clone(case[1], case[2], case[3])
  for index, layer in ipairs(entity.pictures.rotated.layers) do
    assert(layer.back_equals_front == case[4], case[3] .. " layer " .. index .. " lost source symmetry")
    assert(layer.direction_count == shared.direction_count)
  end
  assert(data.raw[case[1]][case[2]].name == nil, "source prototype was mutated")
end
print("PASS: all four vehicles preserve source symmetry on body, mask and shadow")

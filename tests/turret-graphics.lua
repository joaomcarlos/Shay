-- Run from the mod root: lua tests/turret-graphics.lua
local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

table.deepcopy = copy
local source = {
  graphics_set = {base_visualisation = {animation = {layers = {
    {shift = {0.01, -0.03}}, {shift = {0, -0.14}}
  }}}},
  attack_parameters = {projectile_center = {0, -0.0875}, shell_particle = {center = {-0.0625, 0}}}
}
local states = {"folded_animation", "preparing_animation", "prepared_animation", "attacking_animation", "folding_animation"}
for _, state in ipairs(states) do
  source[state] = {layers = {{shift = {0, -0.8}}, {shift = {0.1, -1}}, {shift = {0.7, 0.1}, draw_as_shadow = true}}}
end
local prototypes = {}
data = {
  raw = {["ammo-turret"] = {["gun-turret"] = source}, ["damage-type"] = {physical = {}}},
  extend = function(_, entries) for _, entity in ipairs(entries) do prototypes[#prototypes + 1] = entity end end
}
require("prototypes.turrets")
local shared = require("shared")
local function near(a, b) assert(math.abs(a - b) < 1e-9) end
assert(#prototypes == 2)
local cooldowns = {[shared.mg_turret] = 1, [shared.cannon_turret] = 15}
for _, entity in ipairs(prototypes) do
  assert(entity.attack_parameters.cooldown == cooldowns[entity.name], entity.name .. " must fire at full rate")
  assert(entity.graphics_set.base_visualisation.render_layer == "higher-object-above")
  assert(entity.gun_animation_render_layer == "higher-object-above")
  assert(entity.gun_animation_secondary_draw_order == 1)
  local count = 0
  local function check(animation, original)
    for index, sprite in ipairs(animation.layers) do
      near(sprite.shift[1], original.layers[index].shift[1])
      near(sprite.shift[2], original.layers[index].shift[2] - shared.turret_lift)
      count = count + 1
    end
  end
  check(entity.graphics_set.base_visualisation.animation, source.graphics_set.base_visualisation.animation)
  for _, state in ipairs(states) do check(entity[state], source[state]) end
  assert(count == 17)
  near(entity.attack_parameters.projectile_center[2], source.attack_parameters.projectile_center[2] - shared.turret_lift)
  near(entity.attack_parameters.shell_particle.center[2], -shared.turret_lift)
end
assert(source.graphics_set.base_visualisation.render_layer == nil, "vanilla source was mutated")
near(source.prepared_animation.layers[1].shift[2], -0.8)
print("PASS: both turret prototypes lift all 17 graphics layers and muzzle/casing offsets without altering vanilla")
print("PASS: mounted MG/cannon cooldowns are 1/15 ticks (MG every tick, cannon at vanilla rate)")

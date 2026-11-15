local shared = require("shared")

local function lift_animation(animation)
  if animation.layers then
    for _, layer in pairs(animation.layers) do lift_animation(layer) end
  else
    local shift = animation.shift or {0, 0}
    animation.shift = {shift[1], shift[2] - shared.turret_lift}
  end
end

-- Script-placed turrets riding on rolling stock: the script teleports them to their hardpoints.
local function turret(name, attack)
  local entity = table.deepcopy(data.raw["ammo-turret"]["gun-turret"])
  entity.name = name
  entity.flags = {"placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable", "not-selectable-in-game", "not-repairable"}
  entity.minable = nil
  entity.collision_mask = {layers = {}}
  entity.selection_box = {{0, 0}, {0, 0}}
  entity.resistances = {}
  for damage_type in pairs(data.raw["damage-type"]) do
    entity.resistances[#entity.resistances + 1] = {type = damage_type, percent = 100}
  end
  entity.alert_when_attacking = false
  -- Keep the physical mount on the train, but draw its base and gun above the roof.
  local base = entity.graphics_set.base_visualisation
  base.render_layer = "higher-object-above"
  lift_animation(base.animation)
  for _, state in ipairs{"folded_animation", "preparing_animation", "prepared_animation", "attacking_animation", "folding_animation"} do
    lift_animation(entity[state])
  end
  entity.gun_animation_render_layer = "higher-object-above"
  entity.gun_animation_secondary_draw_order = 1
  entity.attack_parameters.projectile_center[2] = entity.attack_parameters.projectile_center[2] - shared.turret_lift
  entity.attack_parameters.shell_particle.center[2] = entity.attack_parameters.shell_particle.center[2] - shared.turret_lift
  for k, v in pairs(attack) do entity.attack_parameters[k] = v end
  return entity
end

data:extend
{
  turret(shared.cannon_turret, {range = 32, cooldown = 15, ammo_category = "cannon-shell", damage_modifier = 2}),
  turret(shared.mg_turret, {range = 18, cooldown = 1, ammo_category = "bullet"})
}

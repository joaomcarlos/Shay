local shared = require("shared")

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
  for k, v in pairs(attack) do entity.attack_parameters[k] = v end
  return entity
end

data:extend
{
  turret(shared.cannon_turret, {range = 32, cooldown = 120, ammo_category = "cannon-shell", damage_modifier = 2}),
  turret(shared.mg_turret, {range = 18, cooldown = 8, ammo_category = "bullet"})
}

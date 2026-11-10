local util = require("util")
local shared = require("shared")

local run_animation = util.sprite_load(shared.graphics_dir .. shared.sentry_bot .. "/" .. shared.sentry_bot,
{
  direction_count = 8,
  frame_count = 4,
  scale = 0.5,
  shift = {0, -0.1}
})

data:extend
{
  {
    type = "unit",
    name = shared.sentry_bot,
    icon = "__Shay__/graphics/icons/" .. shared.sentry_bot .. ".png",
    flags = {"placeable-off-grid", "not-in-kill-statistics", "not-on-map", "not-selectable-in-game"},
    hidden = true,
    max_health = 60,
    collision_box = {{-0.25, -0.25}, {0.25, 0.25}},
    selection_box = {{-0.45, -0.45}, {0.45, 0.45}},
    movement_speed = 0.2,
    distance_per_frame = 0.02,
    rotation_speed = 0.03,
    distraction_cooldown = 300,
    vision_distance = 15,
    ai_settings =
    {
      do_separation = false,
      destroy_when_commands_fail = false,
      allow_try_return_to_spawner = false,
      join_attacks = false
    },
    run_animation = run_animation,
    attack_parameters =
    {
      type = "projectile",
      ammo_category = "bullet",
      range = 12,
      cooldown = 30,
      animation = run_animation,
      ammo_type =
      {
        target_type = "entity",
        action =
        {
          type = "direct",
          action_delivery =
          {
            type = "instant",
            target_effects =
            {
              {type = "damage", damage = {type = "physical", amount = 8}}
            }
          }
        }
      }
    }
  }
}

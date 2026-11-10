local shared = {}

-- Rolling stock (each has a matching item + recipe)
shared.gun_locomotive = "shay-gun-locomotive"     -- engine, tank cannon nose, MG turret rear
shared.mg_wagon = "shay-mg-wagon"                  -- wagon with 3 MG turrets
shared.layer_locomotive = "shay-locomotive"        -- track layer, roboport grid, grinder nose, self-drive
shared.ramp_wagon = "shay-ramp-wagon"              -- deploys sentry bots from side ramps

-- Script-driven support entities (never in player inventory)
shared.cannon_turret = "shay-cannon-turret"
shared.mg_turret = "shay-mg-turret"
shared.sentry_bot = "shay-sentry-bot"

-- Animation + sprite prototype names
shared.grinder_animation = "shay-grinder"
shared.ramp_sprite = "shay-ramp"

-- Graphics
shared.direction_count = 16
shared.graphics_dir = "__Shay__/graphics/entity/"

-- Turret hardpoints: stock-local {side, forward} tile offsets, +forward = toward nose
shared.turrets =
{
  [shared.gun_locomotive] =
  {
    {entity = shared.cannon_turret, offset = {0, 1.8}},
    {entity = shared.mg_turret, offset = {0, -1.2}},
  },
  [shared.mg_wagon] =
  {
    {entity = shared.mg_turret, offset = {0, 1.2}},
    {entity = shared.mg_turret, offset = {0, 0}},
    {entity = shared.mg_turret, offset = {0, -1.2}},
  },
  [shared.layer_locomotive] =
  {
    {entity = shared.mg_turret, offset = {0, -1.0}},
  },
}

-- Track-layer locomotive tuning
shared.layer =
{
  cruise_speed = 0.15,         -- tiles/tick self-drive throttle (~32 km/h, vanilla max is 1.2)
  grind_interval = 15,         -- ticks between rock-grind checks while moving
  grind_reach = 1.8,           -- tiles ahead of the nose
  rail_lay_interval = 5,       -- ticks between rail extension attempts
  grinder_offset = {0, 2.4},   -- rotating nose position, stock-local
  equipment_grid = "shay-equipment-grid",
}

-- Ramp wagon / sentry bots
shared.ramp =
{
  deploy_speed = 0.3,          -- bots deploy only while the train is slower than this
  bots_per_side = 10,
  bot_spacing = 0.7,           -- tiles between parked bots along the flank
  patrol_radius = 6,           -- patrol ring radius around the wagon
  repatrol_ticks = 90,         -- ticks between patrol point re-issue
  recall_arrive = 1.2,         -- despawn within this distance of the wagon
}

shared.custom_input_cruise = "shay-toggle-cruise"

return shared

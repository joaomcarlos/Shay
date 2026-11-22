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

-- Visual roof height only; turret combat hardpoints remain on the stock's centreline.
shared.turret_lift = 0.9

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

-- Default body tint per stock — the colour shown on its item thumbnail.
shared.colors =
{
  [shared.layer_locomotive] = {r = 0.40, g = 0.66, b = 0.40},
  [shared.gun_locomotive] = {r = 0.62, g = 0.44, b = 0.26},
  [shared.mg_wagon] = {r = 0.31, g = 0.44, b = 0.58},
  [shared.ramp_wagon] = {r = 0.66, g = 0.36, b = 0.36},
}

-- Track-layer locomotive tuning
shared.layer =
{
  cruise_speed = 0.15,         -- tiles/tick self-drive throttle (~32 km/h, vanilla max is 1.2)
  rail_lay_interval = 5,       -- ticks between rail extension attempts
  grinder_visual_offset = {0, 4.2}, -- enlarged drill centre; its base stays at the nose
  equipment_grid = "shay-equipment-grid",
}

-- Trackside builds planted beside each freshly laid rail while the cargo holds their
-- items. offset is {side, forward} in the laid rail's frame — +side is right of
-- travel — and interval is tiles between placements.
shared.trackside =
{
  {entity = "rail-signal", item = "rail-signal", offset = {1.5, 0}, interval = 16},
  {entity = "medium-electric-pole", item = "medium-electric-pole", offset = {-1.5, 0}, interval = 8}
}

-- Resupply: run back to the schedule's first station when a needed item runs low, then return to the last laid rail.
shared.supply =
{
  rail_low = 20,           -- auto-resupply when the consist holds fewer than this many rail items
  rail_full = 200,         -- stocked threshold the wait condition checks for
  fill_low = 20,           -- same thresholds for landfill
  fill_full = 200,
  trackside_low = 10,      -- and for trackside items (signals, poles)
  trackside_full = 50,
  wait_ticks = 3600,       -- give up waiting at the station after this
  arrive_wait = 120,       -- ticks to pause at the frontier rail before resuming
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
shared.custom_input_resupply = "shay-resupply"

return shared

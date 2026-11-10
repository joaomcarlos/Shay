local shared = require("shared")

data:extend
{
  {
    type = "animation",
    name = shared.grinder_animation,
    filename = shared.graphics_dir .. "shay-grinder/shay-grinder-1.png",
    width = 96,
    height = 96,
    frame_count = 8,
    line_length = 8,
    scale = 0.4,
    priority = "low"
  },
  {
    type = "sprite",
    name = shared.ramp_sprite,
    filename = shared.graphics_dir .. "shay-ramp/shay-ramp-1.png",
    width = 64,
    height = 160,
    scale = 0.5,
    priority = "low"
  }
}

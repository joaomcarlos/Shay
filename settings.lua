local shared = require("shared")

data:extend
{
  {
    type = "double-setting",
    name = shared.setting_cruise_speed,
    setting_type = "runtime-per-user",
    default_value = shared.layer.cruise_speed,
    minimum_value = 0.1,
    maximum_value = 0.6
  }
}

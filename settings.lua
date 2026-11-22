local shared = require("shared")

data:extend
{
  {
    type = "string-setting",
    name = shared.rail_item_setting,
    setting_type = "startup",
    default_value = "rail",
    order = "a"
  },
  {
    type = "double-setting",
    name = shared.setting_cruise_speed,
    setting_type = "runtime-per-user",
    default_value = shared.layer.cruise_speed,
    minimum_value = 0.1,
    maximum_value = 0.6
  }
}

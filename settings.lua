local shared = require("shared")

data:extend
{
  {
    type = "int-setting",
    name = shared.setting_lanes,
    setting_type = "runtime-per-user",
    default_value = shared.layer.lanes,
    minimum_value = 1,
    maximum_value = 9
  },
  {
    type = "int-setting",
    name = shared.setting_lane_spacing,
    setting_type = "runtime-per-user",
    default_value = shared.layer.lane_spacing,
    minimum_value = 2,
    maximum_value = 16
  }
}

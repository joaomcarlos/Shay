local shared = require("shared")

data:extend
{
  {
    type = "custom-input",
    name = shared.custom_input_cruise,
    key_sequence = "CONTROL + G",
    consuming = "game-only"
  },
  {
    type = "custom-input",
    name = shared.custom_input_resupply,
    key_sequence = "CONTROL + SHIFT + G",
    consuming = "game-only"
  }
}

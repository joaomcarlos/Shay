local shared = require("shared")

data:extend
{
  {
    type = "custom-input",
    name = shared.custom_input_cruise,
    key_sequence = "CONTROL + G",
    consuming = "game-only"
  }
}

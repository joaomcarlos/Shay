local shared = require("shared")
local stock = require("prototypes.rolling-stock")

-- Keeps the cargo wagon's open_sound/close_sound for the ramps.
stock.clone("cargo-wagon", "cargo-wagon", shared.ramp_wagon)

local shared = require("shared")
local stock = require("prototypes.rolling-stock")

local loco = stock.clone("locomotive", "locomotive", shared.layer_locomotive)
loco.max_speed = 0.4
loco.weight = 3000
loco.equipment_grid = shared.layer.equipment_grid

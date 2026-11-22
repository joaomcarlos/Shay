local shared = require("shared")
local stock = require("prototypes.rolling-stock")

local wagon = stock.clone("artillery-wagon", "artillery-wagon", shared.cannon_wagon, {vanilla_pictures = true})

-- Same cannon, different ammo: the wagon's own gun accepts tank cannon shells
-- instead of artillery shells, so the wagon's inventory only chambers those.
local gun = table.deepcopy(data.raw.gun["artillery-wagon-cannon"])
gun.name = shared.cannon_wagon_gun
gun.attack_parameters.ammo_category = "cannon-shell"
wagon.gun = gun.name
data:extend{gun}

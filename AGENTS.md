# Shay

Factorio 2.1 mod (`base >= 2.1.0`): a track-laying locomotive that builds rails ahead of itself as it drives. Named for the geared Shay locomotive that ran on rough, freshly-laid frontier track.

## Conventions

- Release author and MIT copyright holder: `TheSilentWarrior`
- `publish.json` is the release whitelist; update it when shipped files are added. `publish/` is a gitignored build artifact, never committed
- Bump `info.json` version and add the top `changelog.txt` entry before packaging; entries state what the mod does, never the dev process
- Lua 5.2, Factorio runtime: keep data stage (`data.lua`) and control stage (`control.lua`) separate
- Fail fast, no meaningless nil-guards, no backwards-compat shims, YAGNI
- `docs/graphics-pipeline.md` — sprite/animation architecture study (Sweepbot teardown + vanilla rolling-stock spec + AI image-generation plan); read before touching graphics or prototypes
- `tools/` — asset pipeline: `extract_vanilla_stock.py` pulls vanilla cells into `work/raw/`, `pack_sprites.py` packs cells into sheets + `*.lua` metadata, `build_graphics_assets.py` runs the full asset build, `verify_graphics_assets.py` checks sheet/metadata integrity
- `prototypes/` — data stage: `rolling-stock.lua` clone/pictures helpers, one file per vehicle, `turrets.lua` (teleported ammo-turrets), `sentry-bot.lua` (unit), `overlays.lua` (grinder animation + ramp sprite), `equipment.lua`, `inputs.lua`
- `control.lua` + `lib/` — control stage via `__core__.lualib.event_handler` libraries: `lib/turrets.lua` (hardpoint teleport + ammo refill), `lib/layer.lua` (cruise CTRL+G, cardinal rail laying, rock grinding, grinder overlay), `lib/ramp.lua` (deploy/patrol/recall state machine + ramp sprites), `lib/frame.lua` (orientation math)
- `shared.lua` — the contract: every entity/item name, hardpoint offsets (`{side, forward}`), tuning constants. Prototypes and control code consume it; never duplicate names
- `work/` — gitignored raw-art staging + worker reports; packed output lands in `graphics/` and IS committed
- Headless smoke test: `factorio --create save.zip -c config.ini --mod-directory <dir>` with an isolated mod dir containing `mod-list.json` (base + Shay) — never use `~/.factorio`, jc's game locks it

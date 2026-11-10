# Shay

Factorio 2.1 mod (`base >= 2.1.0`): a track-laying locomotive that builds rails ahead of itself as it drives. Named for the geared Shay locomotive that ran on rough, freshly-laid frontier track.

## Conventions

- Release author and MIT copyright holder: `TheSilentWarrior`
- `publish.json` is the release whitelist; update it when shipped files are added. `publish/` is a gitignored build artifact, never committed
- Bump `info.json` version and add the top `changelog.txt` entry before packaging; entries state what the mod does, never the dev process
- Lua 5.2, Factorio runtime: keep data stage (`data.lua`) and control stage (`control.lua`) separate
- Fail fast, no meaningless nil-guards, no backwards-compat shims, YAGNI
- `docs/graphics-pipeline.md` — sprite/animation architecture study (Sweepbot teardown + vanilla rolling-stock spec + AI image-generation plan); read before touching graphics or prototypes
- `tools/` — asset pipeline scripts: `extract_vanilla_locomotive.py` pulls vanilla cells into `work/raw/`, `pack_sprites.py` packs cells into sheets + writes `*.lua` metadata next to them
- `prototypes/` — data-stage entity/item/recipe files, one per vehicle
- `work/` — gitignored raw-art staging; packed output lands in `graphics/` and IS committed
- Headless smoke test: `factorio --create save.zip -c config.ini --mod-directory <dir>` with an isolated mod dir containing `mod-list.json` (base + Shay) — never use `~/.factorio`, jc's game locks it

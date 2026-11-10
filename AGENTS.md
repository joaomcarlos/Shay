# Shay

Factorio 2.1 mod (`base >= 2.1.0`): a track-laying locomotive that builds rails ahead of itself as it drives. Named for the geared Shay locomotive that ran on rough, freshly-laid frontier track.

## Conventions

- Release author and MIT copyright holder: `TheSilentWarrior`
- `publish.json` is the release whitelist; update it when shipped files are added. `publish/` is a gitignored build artifact, never committed
- Bump `info.json` version and add the top `changelog.txt` entry before packaging; entries state what the mod does, never the dev process
- Lua 5.2, Factorio runtime: keep data stage (`data.lua`) and control stage (`control.lua`) separate
- Fail fast, no meaningless nil-guards, no backwards-compat shims, YAGNI

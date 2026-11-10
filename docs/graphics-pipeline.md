# Shay graphics & animation pipeline

How custom sprites and animations will be produced for Shay. Written from a teardown of
Sweepbot 2.1.0 (by Klaudia) cross-referenced against vanilla 2.1 rolling-stock prototypes.

## How Sweepbot does it

**Sprites are Blender renders, not drawn art.** The author's comment in `prototypes/bot.lua`:
`Rendered by tools/render_sprites.py (tools/blender/sweepbot.py) at 128 px a tile`. A 3D model is
rendered under an orthographic Factorio-style camera, one **row per direction** (north first,
clockwise) and one **column per animation frame**. Each render pass writes two things:

1. PNG sprite sheets (`*-1.png`, `*-2.png`, ...)
2. A generated Lua metadata file (`graphics/entity/sweepbot/sweepbot-layout.lua`) containing every
   number the prototypes need — frame size, shadow width, per-file row count, `frame_lift`,
   `distance_per_frame`, `brush_reach`. The Lua code never hardcodes sheet geometry; it `require`s
   this file. Keep this architecture: it decouples assets from code, and for us it's where a packing
   script can *write back measured numbers* (shifts, reach offsets) after trimming generated frames.

### Sheet anatomy (verified against the files)

| Sheet | File size | Cell | Grid | Loaded as |
|---|---|---|---|---|
| `sweepbot-run-{1,2}.png` | 1536x4608 | 256x288 | 6 cols x 16 rows | `direction_count=32`, `frame_count=6`, `lines_per_file=16`, `line_length=6`, scale 0.25 |
| `sweepbot-run-shadow-{1,2}.png` | 1056x2304 | 176x144 | 6 x 16 | half-res, scale 0.5, `draw_as_shadow` |
| `sweepbot-run-glow-{1,2}.png` | 768x2304 | 128x144 | 6 x 16 | half-res, scale 0.5, `draw_as_glow`, additive |
| `sweepbot-scrub-1.png` | 3584x1152 | 256x288 | 14 cols x 4 rows | `direction_count=4`, `frame_count=14` |
| `sweepbot-antenna{,-glow}.png` | 640x320 | 80x80 | 8 x 4 | `frame_count=32` rotation loop |

Conventions worth copying:

- **Three layers per visual**: color at full res (scale 0.25, i.e. rendered at 4x), shadow and glow at
  half res (scale 0.5). Halving shadow/glow sheets saves ~75% VRAM on passes that don't need detail.
- **Shadow is wider than the body** (`shadow_margin`), shifted right+down so it falls off to one side.
- **Glow = emissive-only layer** (headlamps, charge lights), additive blend.
- `shift` math: frame center is placed `frame_lift` above the entity position so feet/tracks land on
  the footprint; shadow gets `+shadow_margin/2` x-shift; the antenna layer re-centers on the mast top.

### Animation mechanics

- The bot is a **`unit`**, driven by `commandable.set_command` (`go_to_location`, `compound`,
  `attack`). `run_animation` is a `RotatedAnimation` (32 dirs x 6 frames); `distance_per_frame` ties
  frame advance to ground covered so treads don't slide.
- The "work" loop lives in `attack_parameters.animation` (4 dirs x 14 frames). Units only attack
  entities, so the script spawns an invisible `sweepbot-dirt` proxy unit at the target.
  `alternative_attacking_frame_sequence` slices one 14-frame sheet into phases:
  `warmup {1..6}` lowers the brush, `attacking/prepared/cooldown {7..14}` scrubs twice,
  `back_to_walk {6..1}` reverses warmup. Each phase gets its own `*_animation_speed`.
- **Script-drawn overlays** (`rendering.draw_animation`) for anything that animates independently of
  the entity's state machine: the 32-frame antenna loop (`animation_speed=0.25`, `animation_offset =
  unit_number % 32` so bots desync), charging sparks. Targets an entity + offset, so it follows.
- `rendering.draw_sprite` for static under-entity plates (dock port on `render_layer="floor"`).
- The dock is an `electric-energy-interface` with 4 per-direction pictures (base/shadow/glow layers)
  plus a `custom_status` for hover text.
- Sounds are reused from `__base__` (spidertron servo for walking, gate open/close for brush ram,
  roboport sparks), with `running_sound_animation_positions` tied to specific frames.

## What vanilla rolling stock actually needs (2.1)

Locomotive (`prototypes/entity/trains.lua`):

```lua
pictures = { rotated = { layers = {
  util.sprite_load(".../locomotive",       {dice=4, direction_count=256, scale=0.5, allow_low_quality_rotation=true, usage="train"}),
  util.sprite_load(".../locomotive-mask",  {dice=4, flags={"mask"}, apply_runtime_tint=true, tint_as_overlay=true, direction_count=256, scale=0.5}),
  util.sprite_load(".../locomotive-shadow",{dice=4, draw_as_shadow=true, direction_count=256, scale=0.5}),
}}}
front_light_pictures = { rotated = { layers = { -- additive headlight cones, draw_as_light }}}
wheels = standard_train_wheels   -- own rotated sprite (256 dirs), drawn under body
back_light = rolling_stock_back_light()     -- small local helpers in trains.lua
stand_by_light = rolling_stock_stand_by_light()
color = {r=0.92, g=0.07, b=0}     -- train-color default for the mask layer
minimap_representation / selected_minimap_representation = {filename, size={20,40}, scale=0.5}
```

- Vanilla uses `direction_count=256` for butter-smooth curves (8 files x 4 cols x 8 rows of 474x458
  cells). **We do not need 256.** Rolling stock snaps `orientation` to `direction_count` — 32 is
  plenty (45-degree curves only hit ~8 of them hard anyway), 16 acceptable, 8 minimum.
- `util.sprite_load(path)` reads a sibling `.lua` returning
  `{width, height, shift, line_length, filenames, lines_per_file}` — same metadata-file pattern as
  Sweepbot's layout.lua, just split per layer. We can use either convention; keep layout.lua style.
- `dice` slices sheets into atlas pieces — optional; skip it for our sheet sizes.
- `wheels`, `back_light`, `stand_by_light` helpers are defined locally in base `trains.lua` — copy
  the two light helper functions into our code; wheels can point at `__base__` train-wheel sheets
  verbatim for v1 (custom wheels later if the models justify it).
- Wagons are the same minus lights/`color`: `direction_count=128` vanilla, `cargo_wagon` has
  `open_sound`/`close_sound` (door/ramp hooks!).
- `tint_as_overlay` mask: a greyscale-ish sheet marking which pixels take the train's player color.
  Optional — skip for v1, add when we want colored trains.

## The AI-generation adaptation

We swap Blender for an image model. The output contract stays identical — grids of cells + a
layout.lua — but models can't reliably emit a 32x6 grid with consistent geometry, so the unit of
generation is **one cell or a small row**, assembled into sheets by our own packer.

### Generation rules that will work

1. **Ask for one direction at a time** (or at most a 4-view turnaround: N/E/S/W). 8 directions
   (every 45 deg) is the realistic maximum for consistency; 4 + mirroring works for symmetric stock.
2. **Fix the camera in the prompt, every time.** Factorio sprites: orthographic 3/4 view, camera
   elevated ~45 deg looking down, light source upper-left, transparent background, vehicle facing
   the stated compass direction, consistent pixel size per tile (specify e.g. "occupies a 2x5 tile
   footprint, 64 px per tile"). Reuse the first accepted image as a **reference image** for all
   later generations of that vehicle.
3. **Generate on transparent/alpha background.** If the model can't do alpha, use flat chroma
   (magenta) and key it in the packer.
4. **Post-process, don't re-prompt.** The packer trims each cell's transparent border, centers it on
   the footprint anchor, measures the real cell size, packs rows per file, and **writes layout.lua**
   (frame size, shifts, lines_per_file — the Sweepbot architecture, our numbers).
5. **Derive shadow + glow layers procedurally.** Shadow = alpha silhouette -> offset (+x, +y),
   blur, darken, render at half res. Glow/lights = hand-masked emissive regions or a second prompt
   ("same image, only the lit elements, black elsewhere"). Masks for train-color tint = flood-select
   body panels -> greyscale mask, same cell grid.
6. **Frame animation over direction animation.** Models keep a single pose consistent far better
   than a pose x direction matrix. So: full direction set for the *static body*; moving parts
   (grinder nose, turret barrels, door ramps, bot legs) become **separate overlay animations**
   (`rendering.draw_animation`, Sweepbot-antenna style) or phase-sliced attack animations.
7. **Sheet budget**: pack to <=4096px per file dimension; split rows across files (`lines_per_file`)
   like both references do.

### Prompt template (per vehicle, per direction)

```
Factorio-style game sprite, orthographic 3/4 view, camera elevated 45 degrees,
light source upper-left. A [VEHICLE DESCRIPTION], facing [DIRECTION], centered,
on transparent background. Occupies [W x H tile] footprint at 64 px per tile.
Clean pixel-crisp edges, Factorio art style: slightly desaturated industrial
colors, painted-metal surfaces, visible bolts and panel lines. No text, no shadow
painted into the sprite (shadow added separately).
```

Then one reference-image-locked variant per remaining direction, and per animated attachment a
loop prompt (e.g. "the same locomotive, grind-stone nose cone rotated 45 degrees more") or an
explicit N-frame strip.

## The four vehicles — asset plan

| Vehicle | Body directions | Overlays / animated parts | Notes |
|---|---|---|---|
| **Gun loco** (tank cannon nose + MG turret) | 16-32 static dirs | cannon + MG are separate `turret`/`ammo-turret` entities teleported to hardpoints each tick (aimable, actually shoots); muzzle flash = attack animation on turret | Turret hardpoints defined per-direction in layout data |
| **MG wagon** (3x MG turrets) | 16-32 static dirs | same teleported-turret approach x3 | Hardpoints fore/mid/aft |
| **Shay track-layer loco** | 16-32 dirs | grinder nose = looped `draw_animation` rotation overlay; headlamp glow layer | Slower max_speed; lays rail via script (FARL-style `create_entity` on tiles ahead); "acts as roboport" via `equipment_grid` on rolling stock or scripted ghost-placement; self-driving = script sets train manual mode + speed; rock-grinding = find rocks ahead, destroy + debris smoke/sound, NOT explosion; reversible: separate rear-view or symmetric sprite, `reversing_power_modifier` |
| **Ramp wagon** (deploys 2x10 ground bots) | 16-32 dirs | doors -> ramp-down = phase-sliced animation (Sweepbot scrub technique: warmup lowers ramp, prepared holds, back_to_walk raises); bots = `unit` entities with own run_animation sheets (small: 8 dirs x 4 frames) | Perimeter bots patrol near train while slow; recall when speed rises -> return to ramp, despawn on dock. Reuse cargo wagon `open_sound`/`close_sound` for ramps |

Turret sprite spec: base plate (static) + barrel (rotated, `direction_count` 16-32 for smooth aim)
+ attack flash frames — the vanilla `gun-turret` structure shrunk to train scale.

## Build order

1. `tools/pack_sprites.py` — trim/anchor/pack + emit `*-layout.lua` (ports Sweepbot's architecture)
2. Gun loco static body (N/E/S/W first, validate in-game on a loop)
3. One teleported turret end-to-end (sprite + entity + tick driver)
4. Shay layer loco: static + grinder overlay + scripted rail laying
5. Ramp wagon: doors + bot units
6. Polish: shadows, glow layers, color masks, minimap icons, thumbnails

## References

- Sweepbot 2.1.0 by Klaudia (license.txt in the zip; studied locally, not redistributed)
- Vanilla: `data/base/prototypes/entity/trains.lua`, `data/core/lualib/util.lua` (`util.sprite_load`)
- FARL (Fully Automatic Rail Layer) — study next for the scripted rail-placement half

# Low Poly Miner — Project Guide

Last audited against source: 2026-08-16

## 1. Product direction

Low Poly Miner is the beginning of a first-person incremental/exponential
mining game. The intended long-term loop is:

```text
mine manually → earn currency → buy stronger tools/methods
→ mine faster/more valuable material → unlock automation and scale
```

The current milestone intentionally stops at the first arrow. It establishes a
small, coherent mining environment and the systems future progression will
build on. The code should remain easy to understand and quick to tune.

The present visual direction is low-poly, textured, dark, atmospheric, and
survival-horror-adjacent: readable silhouettes, localized warm practical
lights, dynamic shadows, and restrained color. Day carries a quirky,
radiation-adjacent moss-green haze over bruised-purple ambient/background
countertones. A texture-free PS2-inspired depth pass turns distant geometry
toward one moss-green fog color through restrained ordered bands while leaving
nearby textures crisp. The effect recedes to a minimal dark trace at Night so
torches regain importance. Outside the mine, a broad scattered cloud deck below
the landing and sparse cloud islands overhead frame the player between two
world-anchored altitude layers.

## 2. Current playable loop

1. The player spawns on an unbreakable outdoor landing at `(0, 0.05, 14)` and
   faces toward negative Z, at the front of an 80×320×80 stone mass.
2. Field Rig slot 1 equips the field hammer.
3. In play mode, left-clicking a reachable cave block applies one damage.
4. The block shows cumulative crack stages while preserving earlier fractures.
5. Breaking stone, coal, or copper puts that block into one Field Pack cell.
6. Field Rig slot 2 equips the torch placeholder.
7. Right-click places a torch on a reachable block face, consuming one torch.
8. Left-clicking a placed torch removes it without returning an inventory item.
9. Field Rig slot 4 equips dynamite. Right-click lights a 6 s fuse; hold
   left-click to wind up and release to throw. The throw consumes the cell.
10. Selecting an empty Field Rig cell displays a simple procedural hand.
11. The automatic day/night cycle continues while the player mines.
12. Y opens Time Test / Admin. Admin Mode is for carving and painting the cube.
    Save Map writes the volume; Reset Stone Cube restores a solid fill. The FOG
    tab tunes mist and RetroFog live; Save Fog keeps those values for later runs.

Inventory, time, and placed torches reset each run. The sculpted volume persists
in `user://sculpted_volume.bin`. Saved fog sliders persist in
`user://fog_settings.cfg`.

## 3. Implemented feature inventory

### Player and interaction

- First-person mouse look.
- WASD movement and Space jump.
- Capsule collision and gravity via `CharacterBody3D`.
- Contextual one-block ledge climb: a tap remains an ordinary jump, while one
  uninterrupted Space hold from grounded takeoff through the short airborne
  lead-in deliberately authorizes a clear-ledge catch. Releasing before the
  catch locks climbing out for that jump, including after a midair re-press.
- A caught ledge commits a 0.76-second grab, brace, pull, and vault with a small
  body reach/sag and camera dip, lean, bob, twin effort tugs, and roll. Releasing
  Space after the catch does not cancel it. The regular jump stays unchanged;
  two-block walls, unsupported corners, and obstructed landings are rejected.
- Six-unit camera ray reach for mining and torch placement.
- Fast click support with a 0.05-second anti-event-spam cap.
- Camera-attached field hammer GLB (`HeldProp`) with bob and a raise/smash swing.
- Camera-attached field tablet GLB with movement bob.
- Camera-attached dynamite GLB: right-click lights a fuse, hold left-click
  winds up, release throws a gravity-arc `ThrownDynamite` and consumes the cell.
- Camera-attached low-poly untextured torch placeholder with bob.
- Empty Field Rig cells show a procedural hand placeholder.
- Mouse capture/release and modal menu movement lock.
- `admin_mode` on the player switches left/right click between play and sculpt.

### Mine and resources

- Solid sculptable 80×320×80 stone volume (2,048,000 voxels). Interior stays
  data; exposed faces become nearby `MineableBlock`s or distant batched visuals.
- Y menu can enter Admin Mode for map sculpting. Play mode mines normally.
- Admin left-click deletes a block in one hit without using the Field Pack.
- Admin right-click opens a Stone / Coal / Copper menu for the aimed block.
- Save Map in the Y menu writes `user://sculpted_volume.bin`. Unsaved edits
  also flush when the game exits. Reset Cube is in the same menu.
- Unbreakable outdoor grass/stone landing in front of the cube.
- Textured world-space triplanar stone, coal, copper, and grass materials.
- Blocks sized to eliminate visual gaps without overlapping collision volumes.

### Block damage and rewards

- Stone: 10 hits, one Stone inventory item.
- Coal: 20 hits, one Coal inventory item.
- Copper: 15 hits, one Copper inventory item (placed only in Admin Mode).
- Each mined block occupies its own Field Pack cell and does not stack.
- If the Field Pack is full, the block stays at one health and the final hit can
  be retried after a cell becomes available.
- Four visual conditions: intact 100%, light damage 77%, medium damage 33%,
  severe/almost broken 1%.
- Three transparent crack mask assets.
- Cumulative shader composition: a later condition includes every earlier mask.
- Crack interiors re-sample the block texture, stain it toward that type's
  vein pigment, and shade a shallow groove. They are not a flat black overlay.
- Medium mask strength reduced to 65% for visual separation.
- Smooth 0.08-second state crossfade independent of damage acceptance.
- 0.10-second scale hit response.
- Field Pack occupancy HUD and short block/status popup.

### Field Rig and Field Pack

- Vertical four-slot quick selector on the right side of the HUD.
- Keys 1–4 select slots.
- Slots 1–4 directly mirror Field Pack cells 1–4.
- Initial cell 1: field hammer.
- Initial cell 2: torch stack and remaining count.
- Initial cell 3: field tablet.
- Initial cell 4: dynamite.
- E toggles a ten-cell inventory overlay named Field Pack.
- Field Pack uses a centered 1030×786 industrial panel texture with transparent
  exterior pixels; the world remains visible around its silhouette.
- Cell 1 starts with the field hammer, cell 2 with the shared torch stack, cell 3
  with the tablet, cell 4 with dynamite, and cells 5–10 start empty.
- Mined stone and coal fill the first empty cell, one block per cell.
- Right-clicking an occupied cell opens a `THROW ITEM AWAY` action that clears
  the item or entire stack and frees the cell.
- Dragging an item onto an empty cell moves it there; dragging onto an occupied
  cell swaps the two items.
- Using the final torch automatically frees cell 2 and its shared Field Rig slot.
- Stone, Coal, and Copper render as transparent low-poly rubble icons in Field
  Pack cells, Field Rig slots, and drag previews; their display names omit the
  former `BLOCK` suffix.
- Inventory items are draggable; stacks cannot be split.

### Torches and lighting

- Ten starting torches.
- Placement on any ray-hit `StaticBody3D` face.
- Right-click placement while a torch is equipped.
- Left-click removal through a small ray-pickable collision shape; no refund.
- Surface-normal orientation supports floors, walls, and ceilings.
- Low-poly six-sided shaft and emissive low-poly flame.
- Equipped held torch light at 1.175 base energy, half the placed value.
- Warm point light with 25.12-unit range.
- Placed energy 2.35 before flicker modulation.
- Gentle 1.08 attenuation.
- Dynamic shadows at 0.66 opacity and 2.6 blur.
- Layered deterministic-per-instance sine flicker after a random starting phase.
- Empty Field Rig cells show a low-poly hand placeholder instead of no model.

### Day/night and testing

- Continuous 420-second/7-minute cycle.
- Exposed cave blocks cast directional shadows so the mountain occludes daylight.
- Ambient is a dim floor (0.16–0.18); Day brightness is the sun, not a global wash.
- A shadowless, 18-unit entrance OmniLight sits just outside the opening and
  below its ceilings. It lifts underside and cut-wall faces that the sun misses,
  rising from mossy `#77866a` at 0.42 energy by Night to muted amber-green
  `#b39a68` at 0.72 by Day. Its 1.65 attenuation preserves the dark interior.
- Day: 180 seconds (3/7), constant maximum brightness.
- Dusk: 60 seconds (1/7), smooth day-to-night interpolation.
- Night: 120 seconds (2/7), constant user-approved night values.
- Twilight: 60 seconds (1/7), smooth night-to-day interpolation.
- Dusk and Twilight are mathematically brightness-symmetric.
- Environment engine fog is disabled. `RetroFog` instead attaches one
  Compatibility-safe fullscreen QuadMesh pass to the player camera, samples the
  rendered screen and depth once per pixel, reconstructs linear distance, and
  blends toward one fog color. It uses no bitmap, particles, or local haze
  geometry.
- `AtmosphericMist` draws on a CanvasLayer behind the HUD and after all 3D,
  including RetroFog. It reconstructs world position from depth and
  alpha-blends three drifting noise bands plus sparse muted-green speckles.
  Night is denser muted violet-gray; Day stays present as dirty green-gray;
  Dusk/Twilight are the thickest. This is not a replacement for RetroFog.
- Day fog begins at 5 m and ends at 38 m with curve 0.85, maximum intensity
  0.88, moss color `#718451`, and 0.70 retro mix. Night begins at 18 m and ends
  at 60 m with curve 1.0, intensity 0.08, dark-violet color `#17131d`, and no
  retro mix. A symmetric fog-only ease-out derived from the smooth daylight
  scalar drives range, curve, color, and retro mix. Intensity adds a
  transition-only bell that peaks at 0.96 at both Dusk/Twilight midpoints, hiding
  the streamed-world horizon while preserving the exact Day and Night endpoints.
- Day mixes the depth coefficient through 16 bands and a static inline 4×4
  Bayer ordered dither. There is no repeating artwork, card edge, temporal
  noise, or shimmer; purple remains in ambient/background lighting rather than
  a second fog layer.
- Game starts at the middle of Night.
- Y toggles Time Test / Admin.
- Day, Dusk midpoint, Night midpoint, and Twilight midpoint shortcuts.
- Admin On/Off, Save Map, and Reset Stone Cube live on the same panel.
- HUD shows the current phase name and an Admin badge when sculpting.

### Exterior cloud strata

- `CloudLayers` creates six distinct procedural whole-cloud silhouettes shared
  between the lower deck and upper scatter. Compact mounds, low shelves,
  thunderheads, split islands, anvils, and thin wind streaks replace the former
  repeated blob assembly; no bitmap cloud asset exists.
- Each silhouette owns one lower and one upper `MultiMesh` wind batch: twelve
  draw objects and 1,800 instances total. Lower batches contain 1,200
  clouds; upper batches contain 600. A mixed random scale distribution produces
  an observed maximum/minimum scale ratio of 11.4508.
- Deterministic random centers fill both X and Z within one 360-unit base tile.
  That layout is repeated over a seamless 5×5 tile field, removing the former
  positive-Z edge near the landing and mountain.
- Six independent lower speeds are `+0.16`, `+0.23`, `+0.32`, `+0.43`, `+0.57`,
  and `+0.74` units/s. Upper speeds are `-0.29`, `-0.39`, `-0.51`, `-0.66`,
  `-0.84`, and `-1.05` units/s. Every batch drifts only along X and wraps over
  the same 360-unit period.
- The opaque, depth-writing shader uses a coarse static instance-attached dither
  to fade geometry from 340 to 520 m rather than ending the field on a hard plane.
  `BlockVolume.get_visual_aabb()` supplies an exact fragment exclusion guard so
  widely scattered clouds cannot show inside the mine mass.
- Clouds have no collision, shadow casting, transparency, particles, textures,
  or manual Day/Night tint interpolation. Fixed lower `#d0d4c5` and upper
  `#c3c0ca` tints receive the same directional sun and ambient environment as
  other lit geometry, then `RetroFog` treats their opaque depth normally.

## 4. World layout

The world uses a 2-unit block grid. `main.gd::_build_cave()` places the landing
and constructs `BlockVolume`. Voxel size and origin live on `BlockVolume`.

### Outdoor landing

- X loop `-8..8`, world X `-16..16`.
- Z loop `4..8`, world Z `8..16`.
- Floor block center Y: `-1` (walkable top at Y `0`).
- Loop Z `> 5` is grass; closer rows are stone.
- All landing blocks are unbreakable `StaticBody3D` instances.
- The pad meets the cube's front face around world Z `6`–`8`.

### Exterior air

- At wind time zero, the lower field has world bounds position
  `(-1053.326, -117.9921, -888.0961)` and size
  `(2066.411, 106.8718, 1797.964)`, for Y `-117.99..-11.12`. The upper field has
  position `(-1004.288, 35.97196, -873.4628)` and size
  `(2085.454, 139.8139, 1781.159)`, for Y `35.97..175.79`.
- The broad, irregular vertical bands remove the former shelf-like altitude
  cutoff while leaving the player between the lower and upper strata.
- Both fields remain world-anchored and repeat in X/Z. They do not follow the
  player downward. The mine's exact visual AABB is supplied to the cloud shader,
  which rejects any fragment that would enter that volume.

### Sculptable cube (`BlockVolume`)

- Size: 80 × 320 × 80 cells = 2,048,000 voxels (160 × 640 × 160 world units).
- Almost all extra height is downward (~304 cells below the landing floor).
  The landing-level floor and 15 layers above it stay at the old heights.
- Exposed cells in an inner 14-cell region are interactive `MineableBlock`s.
  Eight-cell chunks extend lightweight `MultiMesh` visuals to a nominal
  28-cell radius and retain them through 36 cells to prevent visible churn.
- Region targets refresh after 4 cells of travel. Promotion, batching, and
  retirement are queued with a 4 ms per-frame work budget; new presentation is
  built before its previous representation is hidden.
- Default fill is stone. Interior cells stay in a `PackedByteArray` until they
  have an air neighbor and are in range.
- Coal and copper exist only where Admin Mode paints them.
- Persistence: `user://sculpted_volume.bin`, magic `LPM1`, then size and bytes.

There is no remaining hand-authored tunnel or `_ore_at()` coordinate list.

## 5. Deliberately absent systems

The following are not partially hidden elsewhere; they truly do not exist yet:

- Shop or purchase UI.
- Tool upgrades or tool data resources.
- Additional mining methods or automation.
- Exponential income formulas.
- Offline progress.
- Full game save/load (inventory, time, torches). Volume map save exists.
- World-space block drops, pickup entities, or item physics.
- Block regeneration or infinite/procedural mine layers.
- Audio.
- Block break particles/debris.
- Health, enemies, damage, combat, hunger, or survival meters.
- A sky dome, visible sun/moon model, dynamic weather, or geographic time. The
  two cloud strata move continuously but do not change weather state.
- Inventory stack splitting or crafting. Drag-and-drop cell transfer and
  swapping are implemented.
- Controller bindings and accessibility settings.
- Pause menu, title screen, settings screen, or export preset.

## 6. Project structure

```text
LowPolyMiner/
├── AGENTS.md                     AI/contributor invariants and workflow
├── README.md                     Startup, controls, status, documentation index
├── project.godot                 Input actions, renderer, viewport, main scene
├── main.tscn                     Minimal entry node attaching main.gd
├── scripts/
│   ├── main.gd                   Composition root and game-state owner
│   ├── player.gd                 Controller, modal input, ray interactions
│   ├── held_prop.gd              First-person field-tool GLB wrapper
│   ├── thrown_dynamite.gd        Thrown stick, gravity arc, fuse timer
│   ├── block_volume.gd           Voxel data, surface spawn, map save
│   ├── inventory_slot.gd         Native Field Pack drag/drop cell control
│   ├── mineable_block.gd         Block durability and cumulative crack shader
│   ├── placed_torch.gd           Placed torch visuals/light/flicker
│   ├── day_night_cycle.gd        Cycle clock, lighting, daylight strength
│   ├── cloud_layers.gd            Exterior upper/lower faceted cloud fields
│   ├── retro_fog.gd              Fullscreen fog pass and Day/Night endpoints
│   └── atmospheric_mist.gd       Layered drifting mist over RetroFog
├── shaders/
│   ├── clouds.gdshader           Lit opaque clouds, mine guard, far dither
│   ├── retro_fog.gdshader        Depth reconstruction, fog bands, Bayer dither
│   └── atmospheric_mist.gdshader World-space mist layers and speckles
├── assets/
│   ├── blocks/
│   │   ├── stone.png             Cave/outdoor stone texture
│   │   ├── coal.png              Coal deposit texture
│   │   ├── grass.png             Outdoor grass texture
│   │   └── copper.png            Copper ore; admin-painted only
│   ├── items/
│   │   ├── stone.png             Centered transparent stone rubble icon
│   │   ├── coal.png              Centered transparent coal rubble icon
│   │   └── copper.png            Centered transparent copper rubble icon
│   ├── models/
│   │   ├── FieldHammer.glb       First-person field hammer
│   │   ├── FieldTablet.glb       First-person field tablet
│   │   └── FieldDynamite.glb     First-person dynamite stick
│   ├── ui/
│   │   └── inventory_panel.png   Centered transparent ten-cell Field Pack art
│   └── damage/
│       ├── cracks_77.png          Light damage mask
│       ├── cracks_33.png          Medium additions mask
│       └── cracks_01.png          Severe additions mask
└── docs/
    ├── PROJECT_GUIDE.md           This overview
    ├── ARCHITECTURE.md            Ownership and runtime flows
    ├── SYSTEMS_REFERENCE.md       Exact mechanics and tuning reference
    ├── DEVELOPMENT.md             Validation, extension, limits, roadmap
    └── DECISIONS.md               Established decisions and rationale
```

Godot-generated `.uid` and `.import` files may appear beside scripts/assets.
The `.godot/` import/cache directory is excluded by `.gitignore` and should not
be treated as source.

## 7. Current quality bar

The prototype should stay:

- Immediately runnable with no setup beyond opening Godot.
- Small enough that a new contributor can understand it in one sitting.
- Visually coherent even with placeholder native meshes.
- Responsive to rapid clicking.
- Dark but navigable at Night; torches should improve visibility substantially.
- Atmospherically green/purple by Day without obscuring nearby geometry;
  texture-free depth bands should collapse distance without repeating artwork,
  visible cards, or shimmer, then recede to a minimal dark trace at Night.
- Drifting mist should feel like dirty air on top of that tint: uneven,
  slow, world-anchored, thicker at Night and at Dusk/Twilight, still present
  by Day, with only sparse muted-green speckles. Nearby tools stay readable.
- Visibly high above a varied lower cloud deck with a sparse second stratum overhead;
  cloud silhouettes, scale, altitude, scatter, and drift should remain varied,
  seamless, world-lit, exterior-only, and noninteractive.
- Explicit about state ownership and intentionally missing features.
- Valid under Godot's editor parser/import and a headless runtime startup.

See `ARCHITECTURE.md` before moving responsibilities between scripts,
`SYSTEMS_REFERENCE.md` before tuning values, and `DEVELOPMENT.md` before adding a
new resource/tool/inventory item.

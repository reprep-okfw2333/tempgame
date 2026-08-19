# Development, Validation, and Extension Guide

Last audited against source: 2026-08-16

## 1. Development environment

The project is self-contained and requires only Godot 4. The currently detected
portable installation is:

```text
GUI:
C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe

Console:
C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe
```

Project path on the current machine:

```text
C:\Users\myawe\Documents\Codex\2026-08-16\i-w\outputs\LowPolyMiner
```

The portable engine is outside the project and must not be copied into it.

## 2. Running the project

GUI workflow:

1. Start Godot.
2. Import/open `project.godot`.
3. Press F6 or F5.
4. The game opens fullscreen at 1920×1080 and begins at Night at the landing.

Godot's embedded Game panel reports the panel's available size (for example
1656×932) and scales the 1920×1080 viewport to fit. Fullscreen mode avoids that
editor-only constraint for normal play testing.

PowerShell runtime launch:

```powershell
& 'C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe' `
  --path 'C:\Users\myawe\Documents\Codex\2026-08-16\i-w\outputs\LowPolyMiner'
```

## 3. Required automated validation

Run both checks after any GDScript, shader, project-setting, asset-path, or scene
change.

```powershell
$godot = 'C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = 'C:\Users\myawe\Documents\Codex\2026-08-16\i-w\outputs\LowPolyMiner'

# Imports assets, registers class_name scripts, and checks editor parsing.
& $godot --headless --editor --path $project --quit

# Creates the real Main tree and runs ten frames.
& $godot --headless --path $project --quit-after 10
```

Success criteria:

- Process returns without a crash.
- Output contains no `SCRIPT ERROR`.
- Output contains no shader compile error.
- Output contains no missing asset/resource error.
- Output contains no invalid property/method call.

Important: Godot may return exit code 0 even after logging a script error. Read
the output; do not rely only on the exit code.

## 4. Manual smoke-test checklist

Headless checks cannot verify visibility, UI layering, input capture, collision,
or feel. For a meaningful gameplay change, test these applicable cases.

### Startup and movement

- Game opens at Night with `TIME NIGHT` visible.
- Mouse begins captured; camera looks normally without inversion.
- WASD and Space work.
- A normal standing jump retains its existing height and feel.
- Tapping/releasing Space while moving toward a one-block rise performs only the
  normal jump and never starts a climb.
- Releasing Space before the catch permanently cancels that jump's climb
  opportunity; pressing it again while still airborne does not re-arm one.
- Holding one uninterrupted Space press from grounded takeoff through the
  0.08-second lead-in/probe catches a clear one-block rise. Releasing Space after
  that catch does not interrupt the committed climb.
- The 0.76-second motion clearly reads as a deliberate grab, brief hanging
  brace, struggling vertical pull, and inward settle/vault rather than a snap.
- The body shows its small reach arc and brace sag. Camera motion shows a dip,
  forward lean, lateral bob, two pull tugs, and restrained roll without nausea
  or clipping, then returns to the exact normal position and zero roll.
- A two-block wall, narrow/unsupported corner, or ledge with blocked capsule
  space does not trigger the climb.
- Pressing E or Y during any committed climb phase cancels it safely, restores
  the camera position/roll, and opens the requested menu; closing the menu leaves
  normal movement usable.
- Forcing an animated-path collision aborts safely and restores camera position
  and roll rather than leaving a partial effort offset.
- Placed torches never act as climbable ledges or obstruct player movement.
- Player stands on outdoor blocks without jitter or falling through seams.
- A solid stone cube faces the landing; seams are not visibly open.
- Walk, strafe, reverse, and turn around: distant blocks must not visibly appear
  or vanish near the player, and movement must not freeze at stream updates.

### Mining

- Slot 1 is selected initially and the field hammer is visible.
- Outdoor grass/stone cannot be damaged.
- Play-mode stone takes exactly ten accepted clicks.
- Play-mode coal takes exactly twenty accepted clicks.
- Play-mode copper (if painted) takes exactly fifteen accepted clicks.
- Rapid clicking is not delayed by crack crossfades or swing animation.
- Stone and coal each enter one separate Field Pack cell.
- With all cells occupied, the final hit leaves the block intact at one health
  and shows `FIELD PACK FULL`.
- Damage progression is cumulative: no crack disappears in later stages.
- The 33% stage remains visually milder than the 1% stage.

### Field Rig and inventory

- Keys 1–4 update selection highlight, label, resource icon, held model, and help text.
- Field Rig slots 1–4 exactly match Field Pack cells 1–4.
- Slots 1–4 show `HAMMER`, `TORCH x10`, `TABLET`, and `DYNAMITE` at a fresh run.
- Slots 3–4 show their held models. Slot 4 lights on right click and throws
  on a charged left-click release.

### Dynamite

- Selecting slot 4 shows the red FieldDynamite stick in the lower right.
- Right click lights a spark and starts a 6 s `LIT` countdown.
- Left click while unlit shows `LIGHT IT FIRST` and does not throw.
- Holding left click after lighting raises the stick toward the shoulder.
  A longer hold pulls it further back; it must stay on-screen in profile.
- Release throws a tumbling stick with a gravity arc. A tap is a short lob;
  5 s is a longer toss, not a line-drive.
- The Field Rig cell becomes empty and the held model hides.
- A fuse that reaches zero in hand or in the world removes the stick with no
  blast yet.
- E, Y, or a ledge climb cancels a charge but does not put out a lit fuse.
- Discarding the dynamite in the Field Pack clears the fuse state.
- E opens the ten-cell Field Pack, releases the mouse, hides the crosshair, and
  locks movement/item use.
- E or Escape closes it and recaptures the mouse.
- Field Pack cell 2 and Field Rig slot 2 always show the same torch count/state.
- Each mined block appears in the first empty cell as a non-stacking `x1` item.
- Stone, Coal, and Copper show the correct rubble icon in the Field Pack, Field
  Rig, and drag preview, with no `BLOCK` suffix in their displayed names.
- The industrial Field Pack frame is centered, all ten hit areas match its
  painted 5×2 bays, and the world is visible through the exterior alpha.
- Resource icons have alpha-zero corners and are visually centered in their
  TextureRects; no white/checkerboard matte is visible in any inventory view.
- Dragging an item highlights its source cell and shows a floating preview.
- Dropping on an empty cell moves it; dropping on an occupied cell swaps both
  items; dropping outside the grid leaves the inventory unchanged.
- Moving items into or out of cells 1–4 immediately updates the Field Rig and
  currently held model/action.
- Right-clicking an occupied cell opens `THROW ITEM AWAY`; selecting it clears
  exactly that cell and immediately reduces pack occupancy.
- Throwing away the torch stack sets both Field Pack and Field Rig counts to zero.
- Placing the final torch changes both Field Pack cell 2 and Field Rig slot 2 to
  `EMPTY`, hides the held torch, and shows the empty-hand placeholder.
- Selecting any empty Field Rig cell shows the hand and hides every held tool.

### Torches

- A torch-equipped Field Rig slot + right click places on floor, wall, and ceiling surfaces.
- Each placement consumes exactly one torch.
- At zero, no torch spawns and `NO TORCHES` appears.
- Left-clicking a placed torch removes it regardless of the selected cell and
  does not return a torch to the Field Pack.
- Equipping a torch creates visible local illumination around the player at
  half the placed torch's base energy; selecting another cell removes it.
- A placed torch has a shaft/flame, warm flicker, broad reach, soft transition,
  and shadows.
- Torch light remains useful during Night but does not make global lighting
  irrelevant.

### Day/night and Time Test

- Y opens Time Test / Admin, releases the mouse, hides the crosshair, and locks
  movement.
- ENTER ADMIN shows the ADMIN badge; play mining/inventory rules stay off.
- Admin left-click deletes a cube block in one hit and does not fill the pack.
- Admin right-click opens Stone / Coal / Copper; choosing one changes that cell.
- SAVE MAP writes the volume; RESET STONE CUBE restores a solid fill.
- FOG tab sliders change mist and RetroFog immediately. SAVE FOG writes
  `user://fog_settings.cfg` and those values load on the next boot. RESET FOG
  restores code defaults for the current session.
- Leaving Admin restores 10/20/15 hit mining and inventory rewards.
- E while Y is open switches to Field Pack rather than stacking panels.
- Y/E/Escape close behavior restores correct mouse capture.
- Day is maximum brightness.
- Night exactly matches the approved dark-but-navigable preset.
- At Night, exposed entrance undersides and cut side walls receive a faint
  green/amber lift instead of collapsing to featureless black; recesses remain
  dark and torches still make an obvious local difference.
- Day shows unmistakable moss-green distance haze with purple-biased shadows
  and background, while nearby block texture remains readable.
- At Day, nearby block/tool textures stay crisp while increasingly distant
  geometry collapses toward moss green through restrained 16-band ordered
  dither. No repeating artwork, billboard/card edge, local patch, or flat tint
  is visible.
- Walk, strafe, turn, and stop in both open landing space and a tunnel. The 4×4
  ordered pattern remains static in screen space with no temporal noise,
  crawling, shimmer, or particle recenter.
- Fog endpoints interpolate smoothly through Dusk/Twilight. Night retains only
  a minimal dark-violet trace beginning at 18 m with maximum intensity 0.08;
  Day begins at 5 m and reaches 0.88 maximum intensity.
- Blocks, held tools, crosshair, HUD, and modal panels stay readable. Canvas UI
  is not fogged, and practical lights do not create textured haze cards.
- Dusk and Twilight midpoint buttons have identical brightness and identical
  `RetroFog` uniforms; both fog intensities reach 0.96.
- Standing still, slow mist banks should drift independently of the camera.
  Walking should show mild parallax between nearer and farther mist, not a
  sheet glued to the lens.
- Held hammer and the aimed block stay readable. Mist does not start at 0 m.
- Sparse muted-green speckles appear inside thicker patches and fade; they
  must not look like fireflies or a regular grid.
- Day still has dirty green-gray mist. Night is denser and darker. Dusk and
  Twilight midpoints are the thickest. RetroFog's moss/violet distance tint
  remains visible underneath.
- Turning toward open air and looking down shows a broad, varied lower cloud
  deck with visibly varied silhouettes, scales, and depths; looking up shows
  separated upper islands across an irregular height range with open gaps.
- Clouds respond visibly to the shared sun/ambient lighting at Day, both
  transition midpoints, and Night; real depth fog affects them, twelve distinct
  lateral drift bands move at varied speeds, and tile wrapping introduces no pop.
- Scan the full horizon and far field: X/Z scatter has no positive-Z or altitude
  shelf edge, and the static 340–520 m dither removes a hard distance cutoff.
- Facing or entering the mine shows no clouds embedded in stone. The exact
  mine-AABB fragment guard works, and cloud nodes provide no collision, shadow
  casting, lights, or interaction surfaces.
- Dusk and Twilight automatically move in opposite brightness directions.
- The HUD phase name changes at boundaries/test selections.
- Time continues while a menu is open.
- A real 1920×1080 capture confirms crisp near texture, moss-green distance
  collapse at Day, minimal Night trace, no repeating cards/art, and unaffected UI.

### UI

- HUD is readable at 1920×1080.
- Field Rig does not overlap Time Test or Field Pack when hidden.
- Popup fade works for block collection, full-pack, torch-placed, and no-torches messages.

## 5. Adding a new block/resource type

Do not only add a texture and string. At current scale, a minimal safe path is:

1. Copy the texture under `assets/blocks/`.
2. Create a material in `main.gd::_create_materials()` with an intentional
   triplanar scale.
3. Extend `MineableBlock._set_health_for_type()` with health for the type.
4. Add a `BlockVolume` cell id, `_type_id` / `_type_name` / `_material_for`.
5. Add the type to the admin right-click setter in `main.gd`.
6. Decide whether existing crack masks suit the material; normally keep them.
   Crack wash pigments are sampled from the new albedo automatically.
7. Update inventory rendering if the resource needs a different display name.
8. Update all documentation tables.
9. Run validation and manually verify every damage state.

Copper is already wired: texture, material, 15 health, admin paint, play-mode
mining, and Field Pack storage. It does not generate naturally.

When there are several types, replace string branches with a small dictionary
or custom `Resource` containing at least ID, display name, health, reward type,
and material. Do this when it reduces real duplication, not preemptively.

## 6. Adding a new tool

Current selection behavior is hard-coded. For one additional tool:

1. Choose an empty Field Pack cell, or replace tablet/dynamite if their actions
   are still unused.
2. Add a `HeldProp` under the camera in `MinerPlayer.setup()`.
3. Extend `_update_held_item()` visibility.
4. Route left click for the new selected item ID.
5. Add a signal if the action changes state owned by `main.gd`.
6. Update Field Rig labels and contextual help in `main.gd`.
7. Decide whether the action shares `MIN_MINE_INTERVAL`.
8. Test modal locks and all four slot transitions.

Before adding multiple hammer tiers, move damage, use interval, reach, model,
and display name into a small tool data definition. The player should apply
selected tool stats; block scripts should remain unaware of tool classes.

## 7. Expanding the inventory

The current Field Pack has ten string-backed cells. Its first four cells are
also the Field Rig quick slots. The hammer occupies one cell, torches occupy
one stack cell, the tablet and dynamite occupy one cell each, and stone/coal occupy one non-stacking cell per block. Items can
be moved or swapped with drag-and-drop and discarded through a right-click
action. Stack splitting is not implemented.

Recommended minimal progression:

1. Replace the current string array with ten slot records (`item_id`, `count`).
2. Preserve Field Rig as direct views of inventory entries 1–4.
3. Render labels from data in one refresh method.
4. Keep drag/drop behavior centralized in `InventorySlot` and mutations in main.
5. Add stack transfer/splitting only when more than one stackable item exists.
6. Keep item-use requests owned by player but mutations owned by inventory/game
   state.

Do not let the HUD become the source of truth. Labels must render model state.

## 8. Tuning day/night

The user-approved current baseline is the Night illumination endpoint. Preserve
the `DayNightCycle` `NIGHT_*` constants unless explicitly retuning Night.
Environment engine fog is deliberately disabled; `RetroFog` owns its separate
minimal Night trace.

- To change total cycle speed while keeping proportions, edit
  `SEVENTH_DURATION` only.
- Day must remain 3 sevenths, Dusk 1, Night 2, Twilight 1 unless explicitly
  changed.
- Dusk/Twilight symmetry depends on using complementary phase progress and the
  same `smoothstep`. Do not create independent arbitrary brightness curves if
  equality is still required.
- There are no floating cave practicals. Interior light is the entrance leak
  plus player torches.
- `EntranceFill` is not a practical: it is a shadowless, range-limited
  `OmniLight3D` controlled by `DayNightCycle`. Keep it outside the front face
  and below entrance ceilings so underside/side normals face it. Preserve range
  18, attenuation 1.65, and specular 0.12 unless testing the carved entrance at
  both Day and Night. Raising ambient instead will flatten every cave face;
  extending this light deep into the volume will make torches unnecessary.
- Block meshes must cast directional shadows. The volume stores interiors as
  data, so only the exposed shell can occlude the sun. Disabling those
  shadows makes Day interiors as bright as the landing.
- Keep Environment fog disabled. Enabling it double-applies distance treatment
  over `RetroFog`. Do not add volumetric fog, `FogVolume`, or `FogMaterial`
  without first migrating and validating the renderer. Visible drifting mist
  belongs to `AtmosphericMist`, not a rewrite of RetroFog.
- Tune mist density, speed, contrast, and speckles from the named constants
  on `atmospheric_mist.gd`. Lower `MIST_BEGIN` or raise `MIST_OPACITY` only
  after checking hammer and HUD readability at Night.
- `DayNightCycle.get_daylight_strength()` is the single smooth scalar for the
  pass. `RetroFog` derives `1 - (1 - daylight)^2` as its approved symmetric
  fog-only weight for begin, end, curve, color, retro mix, and the base intensity.
  A second symmetric bell blends intensity toward 0.96 through Dusk/Twilight,
  while preserving the exact 0.08 Night and 0.88 Day endpoints. At either
  midpoint, begin/end/curve/retro mix remain 8.25 m / 43.5 m / 0.8875 / 0.525.
- Begin/end define the linear-depth transition interval. Moving begin inward can
  quickly erase nearby texture; moving end inward collapses distant silhouettes.
  Tune both in meters and keep `end > begin` (the shader guards with 0.001).
- `FOG_BAND_COUNT` is 16. Day mixes 70% toward the quantized coefficient; Night
  mixes 0%. The inline 4×4 Bayer threshold is deliberately static. Do not add a
  bitmap lookup, temporal jitter, animated noise, or shimmer.
- One `fog_color` is active at a time. Purple Day character comes from ambient
  and background countertones, not another fog layer or local haze geometry.
- The Compatibility fullscreen pass requires screen/depth texture copies and
  performs one screen plus one depth sample per 3D pixel. It removes particle
  simulation and layered transparent-card overdraw, but it is not free.
- Test all endpoints at native 1920×1080: crisp nearby textures, progressive
  distance collapse, stable ordered pattern, no card/art repetition, minimal
  Night trace, unaffected Canvas UI, and acceptable frame pacing.
- Test all four Y-menu buttons after any endpoint adjustment.

### Tuning exterior clouds

- `CloudLayers` owns silhouette geometry, counts, altitude/scale distributions,
  wind speeds/phases, fixed tints, scatter seeds, tile period, and fade range.
  `shaders/clouds.gdshader` owns lighting mode, mine exclusion, and the static
  far dither. Main only supplies `BlockVolume.get_visual_aabb()`.
- Keep geometry world-anchored and scattered across both X and Z. Parenting it
  to the player would drag the altitude cue underground. The exact mine visual
  AABB guard, not a positive-Z placement boundary, prevents mountain intrusion.
- Preserve opaque depth writing so `RetroFog` treats clouds like world geometry.
  The 340–520 m fade uses deterministic fragment discard at a coarse 0.45
  mesh-local sampling scale; do not replace it with alpha blending, transparent
  cards, particles, or a filler plane.
- Keep movement X-only and per batch. The lower speeds are
  `[0.16, 0.23, 0.32, 0.43, 0.57, 0.74]`; the upper speeds are
  `[-0.29, -0.39, -0.51, -0.66, -0.84, -1.05]`. Per-instance animation would
  defeat `MultiMesh` batching, while Z drift would require a second wrap axis.
- The deterministic base layout repeats over a 5×5 X/Z field at a 360-unit
  period. If the period or tile radius changes, update copies, wind wrap, phases,
  custom AABBs, and far-fade coverage together.
- Six whole-cloud meshes supply compact, shelf, thunderhead, broken, anvil, and
  streak silhouettes. Lower base weighting is `[14, 12, 8, 6, 5, 3]`; upper is
  `[7, 6, 4, 3, 2, 2]`, each repeated across 25 tiles. Preserve the mixed size
  distribution unless a visual retune deliberately changes the 11.4508 observed
  max/min ratio.
- Test from the landing looking down, up, around the full horizon, and at the far
  dither in all four time presets. Also face the mine and enter a carved tunnel
  to confirm mine exclusion. For lighting proof, compare the same phase and
  camera with sun energy enabled and disabled rather than comparing differently
  tinted phase presets alone.
- Native validation currently measures 1,200 lower and 600 upper instances in
  twelve `MultiMeshInstance3D`s, with no collision or shadow casting. Wind-time-
  zero Y extents are `-117.99..-11.12` and `35.97..175.79`.

If a visible sky/sun/moon is later added, `DayNightCycle` should expose a
normalized cycle fraction and drive their transforms. Keep brightness phase
rules separate from astronomical visuals.

## 9. Tuning torch lighting

`PlacedTorch` defines the shared range, attenuation, shadow softness, and placed
base energy. `MinerPlayer` reuses those constants for its held torch and applies
a 0.5 energy multiplier with its own flicker.

Current user preference after iteration:

- substantially wider reach than the first implementation;
- brighter local visibility;
- a very gentle dark-to-light transition;
- soft, partially transparent shadows;
- torches helpful but Night still navigable without them.

When changing range, evaluate energy and attenuation together. Increasing range
alone can create a large but imperceptibly dim outer area. Lower attenuation
extends brightness outward, but if it is too low a final range cutoff may become
noticeable. Increasing range slightly beyond the desired visible pool helps
hide that cutoff. Shadow opacity/blur affects local contrast separately.

Many simultaneous shadowed Omni lights are expensive. Before increasing the
starting count or creating persistent large mines, establish a maximum active
shadow-light budget or disable shadows at distance.

## 10. Expanding the mine

The 80×320×80 volume keeps interiors as bytes. Exposed faces are individual
`MineableBlock` bodies only in the 14-cell interaction tier; the 28-cell distant
tier is already batched by 8-cell chunk and material.

Before growing the mine much further:

- partition blocks into chunks;
- combine static visible surfaces or use `MultiMeshInstance3D` where possible;
- generate collision by chunk rather than one body per block;
- retain per-block logical durability only for exposed/active blocks;
- define regeneration or refill rules so the economy cannot permanently run
  out;
- handle torches attached to regenerated/destroyed supports;
- measure shadowed light cost.

Do not simply increase loop bounds by an order of magnitude and call it done.

## 11. Save-system preparation

The cave volume already persists (`user://sculpted_volume.bin`). A future full
save still needs stable identifiers for:

- inventory/Field Rig assignments;
- current cycle time;
- placed torches and remaining torch count;
- tool/upgrades once implemented.

World coordinates can identify blocks only while layout generation is stable.
If generation changes, save a world seed/version and chunk-local coordinates.
Version save data from the first implementation.

## 12. Known limitations and technical debt

### Gameplay/content

- The mine is a finite cube and does not refill except by Admin reset.
- Removing floor blocks can strand/drop the player.
- Inventory items cannot yet be sold or used beyond torches.
- Three resource types exist; copper is admin-placed only.
- Torches cannot be recovered.
- Torches remain floating if their support block is mined.
- Inventory slots use simple string IDs rather than reusable item records.
- There is no pause; menus only lock player control.

### Technical/performance

- Every *near* exposed cave block is an individual body with its own crack
  ShaderMaterial, though the Shader is shared.
- Streaming uses 14-cell interactive, 28-cell visible, and 36-cell retention
  regions over 8-cell chunks. Target regions update every 4 cells of travel and
  queued transitions target 4 ms per frame; one costly chunk may overshoot.
- Far surfaces use `MultiMesh` but near collision is still per block. Increasing
  interaction radius, chunk size, or frame budget can reintroduce hitches.
- Idle blocks do not run `_process()`; only blocks animating a hit/crack do.
- Every torch uses a shadowed Omni light with a large range.
- No light culling/budget beyond Godot defaults.
- `RetroFog` is one fullscreen pass with no particles or layered transparent
  cards. It still requires Godot's screen/depth copies and executes one screen
  plus one depth sample for every 3D pixel; profile native 1920×1080 frame pacing
  before adding samples or additional postprocess passes.
- Cloud presentation adds 1,800 opaque instances across twelve batched
  `MultiMeshInstance3D` draw objects. Each batch has a large custom AABB spanning
  its 5×5 field, and the 340–520 m dither discards fragments rather than avoiding
  their vertex work; do not increase tile radius, counts, or silhouette geometry
  without profiling native 1920×1080 frame pacing.
- UI uses many fixed pixel offsets.
- No automated gameplay tests.
- No export preset or release build pipeline.
- Type behavior/material routing uses string branches.

### Visual/audio

- Held/placed torches are untextured procedural placeholders.
- Crack masks repeat identically on all blocks/faces and are not randomized.
- Crack overlay uses object-space per-face UVs (not raw `BoxMesh` atlas UVs)
  while base textures and crack sediment are world-triplanar.
- Crack overlay is an opaque vertex-lit cutout (`discard` below 0.28) so
  `RetroFog`'s screen copy can see it. Dusty mask fill is discarded; there is
  no bleed expansion.
- Crack interiors re-sample the block albedo and stain it toward the vein
  hue, then apply a 0.86–0.62 groove. They are not a flat black or brush fill.
- No break particles, debris, decals, sound, music, or animation system.
- No sky dome, visible sun, moon, or astronomical time-of-day geometry. The two
  visible cloud strata are environmental geometry, not a full sky/weather system.
- `RetroFog` is a screen-space, single-color depth treatment rather than true
  volumetric density. It has no height variation, local pockets, light shafts,
  self-shadowing, or physically correct interaction with tunnel volumes; the
  static ordered dither is intentionally visible at stronger Day settings.

## 13. Recommended roadmap

Near-term, in order:

1. Add mining impact/break audio and a small break particle response.
2. Add one inventory use or selling path before introducing a shop economy.
3. Move tool stats into data once two tool tiers exist.
4. Add block regeneration or a second refillable mine layer.
5. Give copper a play-mode spawn/unlock/value role if it should appear without Admin.
6. Convert Field Pack strings to item records when stacking or item metadata is added.
7. Add full save/load (inventory, time, torches) after the first spending loop is fun. Volume save already exists.
8. Add automation and exponential number formatting only after manual progression
   has a tested baseline.

## 14. Documentation maintenance checklist

When behavior changes, update:

- `README.md` for controls, startup, and headline behavior.
- `AGENTS.md` if an invariant, workflow rule, or high-risk area changes.
- `PROJECT_GUIDE.md` for implemented/missing features or world layout.
- `ARCHITECTURE.md` for ownership, signals, dependencies, or runtime flows.
- `SYSTEMS_REFERENCE.md` for any exact constant, formula, asset, or tuning value.
- `DEVELOPMENT.md` for validation, recipes, limitations, or roadmap.
- `DECISIONS.md` when a user-approved design direction is added/reversed.

Documentation and code should be changed in the same task, not left for a later
cleanup.

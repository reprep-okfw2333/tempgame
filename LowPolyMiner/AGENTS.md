# Agent Handoff Instructions

This file is the operational contract for AI agents and future contributors
working in this project. Read it together with the documentation index in
`README.md` before editing code.

## Project intent

This is a deliberately compact Godot 4 first-person mining prototype that will
eventually become an incremental/exponential game. Preserve the playable,
low-complexity foundation. Do not introduce large frameworks, databases,
autoload hierarchies, dependency injection, or generalized item/economy systems
until the requested feature genuinely needs them.

## Current technical baseline

- Engine validated with Godot 4.7.1.
- Renderer is `gl_compatibility`; do not assume Forward+ features exist.
- Entry scene is intentionally tiny: `main.tscn` attaches `scripts/main.gd`.
- Nearly all runtime nodes are built in code.
- No third-party dependencies, plugins, addons, or autoloads.
- The project starts at Night, which is the user-approved baseline lighting.
- `RetroFog` supplies the texture-free, PS2-inspired distance treatment as one
  Compatibility-safe fullscreen screen/depth pass attached to the camera. It
  is moss green with restrained purple countertones by Day and a minimal dark
  trace at Night. Engine Environment fog stays disabled to prevent double
  application; Forward+ volumetric fog remains outside the renderer boundary.
- `AtmosphericMist` is a second camera-child pass that alpha-blends over
  RetroFog. It owns irregular drifting density, three world-space depth
  layers, and sparse procedural green speckles. It does not replace RetroFog.
- `CloudLayers` supplies two exterior-only, opaque low-poly strata: a dense
  ocean below the landing and sparse islands above it. Six procedural whole-cloud
  silhouettes and independent wind batches vary their shape, size, altitude, and
  speed. Both strata are texture-free, non-colliding, shadowless, world-anchored,
  lit by the shared sun/ambient environment, and depth-fogged.
- Inventory, time, and placed torches reset each run. The sculpted cave volume
  is edited in Admin Mode (Y menu) and saved with Save Map, or on exit if dirty.

## Invariants that must not regress

1. Outdoor landing blocks are unbreakable. Cave blocks are mineable.
2. Blocks sit on a 2-unit grid. Visual cubes are 2.02 units to hide seams;
   collision cubes remain exactly 2.0 units. Crack overlays are 2.035 units.
3. In play mode, stone takes 10 hits, coal 20, copper 15. Each broken block
   occupies one non-stacking Field Pack cell; mining does not award gold.
   Admin deletes skip inventory and break in one hit.
4. Damage states are 100%, 77%, 33%, and 1%, followed by destruction.
5. Crack damage is cumulative. Later stages must preserve all earlier cracks.
6. The 33% mask is intentionally only 65% strength to distinguish it from 1%.
7. Crack blending is presentation only. It must never throttle mining input.
8. Rapid clicking remains supported; the 0.05-second cap only rejects
   impossible event spam.
9. Base block textures use world-space triplanar mapping. Crack masks remain a
   separate overlay so base textures can be replaced independently. Crack
   interiors are a watercolor cavity derived from that overlay's block
   pigments (texture mean + high-saturation vein), never a flat black tint.
10. Field Rig slots 1–4 directly mirror Field Pack cells 1–4 and use the item
    stored in the selected cell. They start as hammer, torches, tablet, dynamite.
11. Field Pack has ten visible cells, starts with the hammer in cell 1, the
    torch stack in cell 2, the tablet in cell 3, and dynamite in cell 4, and
    stores each mined block in its own cell.
    Right-click discard and exhausting a usable stack both free the shared cell.
    Dragging moves an item to an empty cell or swaps it with an occupied cell.
    Its centered 1030×786 image-backed frame is `assets/ui/inventory_panel.png`;
    the screen outside the frame and all resource-icon backgrounds must retain
    real PNG alpha. Do not restore the former opaque fullscreen/card rectangles.
12. E and Y menus are mutually exclusive, release the mouse, and lock player
    movement/item use without pausing the world.
13. Torches may mount on any `StaticBody3D` face, consume one inventory unit,
    and use dynamic soft shadows/flicker. An equipped held torch also lights the
    player area at exactly half the placed torch's base energy. Right-click
    places a held torch; left-click removes a targeted placed torch with no refund.
14. Selecting an empty Field Rig cell shows the procedural hand placeholder.
15. Cave lighting is spatial, not a global mood. Ambient is a dim floor
    (Night 0.16 / Day 0.18). Outdoor brightness comes from the shadowed sun
    (Night 0.32 / Day 1.15). Exposed block meshes and far chunks must cast
    shadows so rock occludes daylight; the volume is a hollow surface shell
    and will otherwise be sunlit all the way through. Do not add floating
    interior OmniLights. The shadowless `EntranceFill` OmniLight sits at
    `(0, 2.4, 11)`, range 18, attenuation 1.65, using Night energy 0.42/color
    `#77866a` and Day energy 0.95/color `#b39a68`. It must stay localized near
    the opening so torches remain necessary deeper inside. Do not raise global
    ambient to brighten first-person tools; held meshes stay unshaded.
    Engine Environment fog stays disabled. The separate `RetroFog` Night trace
    begins at 18 m, ends at 60 m, uses curve 1.0, intensity 0.08, color
    `#17131d`, and zero retro quantization mix. Do not overwrite either owner's
    endpoints from `main.gd`.
16. Cycle proportions are Day 3/7, Dusk 1/7, Night 2/7, Twilight 1/7. Dusk and
    Twilight must be brightness-symmetric.
17. The Y menu must keep all four phase test points plus Admin On/Off, Save
    Map, and Reset Stone Cube on the TIME / ADMIN tab. The FOG tab may add
    live sliders and SAVE FOG / RESET FOG; it must not remove the Time/Admin
    controls.
18. Play mode and Admin Mode stay distinct. Play mines with durability and
    inventory. Admin sculpts the volume and paints stone/coal/copper through
    the right-click setter, not by cycling types.
19. `BlockVolume` owns voxel data. Interior cells stay in the byte array until
    a face is exposed. Do not spawn a `MineableBlock` for every filled cell.
20. Surface streaming is two-tier: interactive bodies within 14 cells, batched
    visuals to 28, retirement past 36, 8-cell chunks, and a 4 ms frame budget.
    Preserve load-before-unload transitions and full-chunk padding.
21. A Space tap is only the normal 5.2 jump. Ledge assistance requires one
    uninterrupted hold from grounded takeoff through the 0.08-second lead-in
    and probe; releasing locks it out for that entire jump, and a midair
    re-press must not re-arm it. Once caught, preserve the committed 0.76-second
    grab/brace/pull/vault struggle, exact camera reset, capsule/support clearance
    checks, rejection of two-block or obstructed `StaticBody3D` ledges, and safe
    E/Y cancellation; layer-2 placed torches stay ignored.
22. `RetroFog` owns one camera-child fullscreen QuadMesh pass using
    `shaders/retro_fog.gdshader`. Preserve the one screen plus one depth sample
    per pixel, linear-depth reconstruction, single fog color, 16 coefficient
    bands, static inline 4×4 Bayer dither, the approved eased interpolation for
    begin/end/curve/color/retro mix, and the separate symmetric transition
    intensity bell that peaks at 0.96. Surfaces inset inside the mine AABB
    may retarget to a darker cave haze; outdoor fog, the outer crust, and the
    view out the mouth stay on the Day/Night path.
    Do not reintroduce bitmap smoke, particles, local haze cards, temporal
    noise, or engine Environment fog.
23. `CloudLayers` remains separate from distance fog. Preserve six lower and six
    upper opaque `MultiMesh` wind batches, six procedural silhouette variants,
    deterministic full-X/Z scatter over seamless 360-unit tiles, broad fixed
    altitude/scale variation, independent X-only drift, static 340–520 m dither
    fade, exact `BlockVolume.get_visual_aabb()` fragment exclusion, and shared
    sun/ambient lighting. Clouds have no collision, shadow casting,
    transparency, particles, or textures. Never parent them to the player or
    manually replace world lighting with a Day/Night tint lerp.
24. `AtmosphericMist` stays a separate CanvasLayer (`layer = -1`) color-rect
    pass drawn after all 3D, including RetroFog. Preserve world-space layered
    noise, the three near/mid/far bands, sparse procedural speckles rather
    than particle emitters, the same `1 - (1 - daylight)²` ease plus
    transition boost, and Night-denser / Day-still-present behavior. Indoor
    mist stains toward a dark cave color rather than glowing Day moss. Do not
    fold it into RetroFog, parent it under the camera as a 3D quad (RetroFog
    will cover it), or enable engine volumetric fog to get this look.

## Before making changes

1. Read `docs/PROJECT_GUIDE.md`, `docs/ARCHITECTURE.md`, and the relevant section
   of `docs/SYSTEMS_REFERENCE.md`.
2. Inspect the current source rather than relying on this file for exact code.
3. Preserve unrelated user edits and imported assets.
4. Determine which object owns the state being changed; follow the ownership
   table in `docs/ARCHITECTURE.md`.
5. Prefer a direct, small implementation consistent with the prototype stage.

## Implementation conventions

- GDScript is typed where Godot's inference is ambiguous. Godot 4.7's parser
  will reject some untyped expressions even if they appear obvious.
- Use signals for requests crossing ownership boundaries. Example: the player
  emits a torch placement request; `main.gd`, which owns `torch_count`, decides
  whether it succeeds.
- Keep user-visible tuning values as named constants when practical.
- Maintain mouse/menu state symmetry when adding another modal UI.
- Assets referenced at runtime must live inside the project. Do not depend on
  files remaining in `.codex/generated_images`.
- Update documentation in the same change whenever controls, constants,
  ownership, assets, phase timing, or known limitations change.

## Definition of done

A change is complete only when all applicable items are true:

1. Requested behavior is implemented, not merely scaffolded.
2. Existing invariants above still hold unless explicitly superseded.
3. `README.md` and relevant files under `docs/` describe the new reality.
4. Godot editor import/parser validation passes.
5. Headless runtime startup passes.
6. Visual or interactive changes receive a manual in-game smoke test when
   feasible; document anything that could not be visually verified.
7. No project asset points to an external generated-images folder.

## Validation commands

```powershell
$godot = 'C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = 'C:\Users\myawe\Documents\Codex\2026-08-16\i-w\outputs\LowPolyMiner'
& $godot --headless --editor --path $project --quit
& $godot --headless --path $project --quit-after 10
```

Treat any `SCRIPT ERROR`, shader error, missing asset, invalid property, or
runtime error as a failed validation even if the process exits with code 0.

## High-risk change areas

- `main.gd` creates UI and world objects in a strict initialization order.
  Signals can fire before labels exist; handlers therefore null-check time UI.
- Changing modal menus can leave the mouse captured/visible incorrectly or
  accidentally unlock movement.
- Changing block spacing can reintroduce visible seams or collision overlap.
- Replacing cumulative crack shader logic with simple texture replacement will
  make cracks disappear between states.
- Crack overlays must remain opaque cutouts (`discard`, no `ALPHA` write). A
  blended transparent overlay is drawn after `RetroFog` copies the screen and
  is then covered by the fullscreen pass, so the cracks vanish.
- Do not restore a flat black `crack_tint` or a mask-bleed brush. Cracks
  re-sample the block albedo, stain toward the vein hue, and use a 0.62
  groove floor so the core cannot go black.
- Raising global ambient light can make torches irrelevant; lowering it can
  make the approved Night phase unplayably dark.
- `RetroFog` relies on Compatibility screen/depth textures and a fullscreen
  custom postprocess. Forward+ volumetric fog, `FogVolume`, and `FogMaterial`
  remain prohibited without an explicit renderer migration.
- The fog has no particle simulation or layered transparent-card overdraw, but
  its screen/depth copy and one screen plus one depth sample for every pixel are
  still GPU costs. Tuning can also crush nearby texture contrast or make the
  16-band dither distracting. Test native 1920×1080 Day, Night, both transition
  midpoints, UI isolation, and frame pacing after changes.
- `AtmosphericMist` must stay a CanvasLayer behind the HUD. A 3D camera-child
  quad is drawn before RetroFog's screen pass and disappears. World-space
  noise must stay; a screen-locked sheet reads as a decal. Cap alpha and
  keep `mist_begin` so tools stay readable.
- Clouds are opaque world geometry so RetroFog can use their depth. Alpha cards,
  collision, shadow casting, camera parenting, Z-axis drift, removing the exact
  mine-volume fragment guard, or turning the static far dither into blended
  transparency can reintroduce sorting cost, tunnel leaks, unwanted gameplay
  surfaces, or visible field cutoffs.
- Large numbers of individual blocks and shadowed torches will eventually
  require batching/chunking and a light budget. The volume already hides
  interior cells, keeps only a 14-cell interaction tier as bodies, and batches
  the 28-cell visual tier; do not turn distant batches back into individual
  bodies or re-enable idle block processing.
- Admin Mode changes `MinerPlayer.admin_mode`. Forgetting to keep play-mode
  mining/inventory rules when admin is off will break the intended loop.
- Map persistence is only the voxel file. Do not treat inventory, time, or
  torches as saved unless a full save system is added.

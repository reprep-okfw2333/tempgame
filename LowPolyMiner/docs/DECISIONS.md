# Design and Engineering Decisions

Last audited against source: 2026-08-16

This log records user-approved or technically important decisions. It is not a
chronological changelog of every edit; it captures constraints future work
should preserve until explicitly superseded.

## D-001 — Keep the foundation small

**Decision:** Build only the barebones beginning before shops, upgrades,
automation, and exponential scaling.

**Reason:** Mining feel, clarity, and code foundations should be testable before
progression systems multiply complexity.

**Consequence:** Avoid generalized frameworks until more than one concrete use
case exists.

## D-002 — Code-built scene at prototype scale

**Decision:** Keep `main.tscn` minimal and build the current world/UI/models in
GDScript.

**Reason:** The small prototype is faster to revise as a few readable scripts.

**Revisit when:** Models, animation trees, audio nodes, reusable world chunks,
or multiple scenes make procedural construction harder than scene composition.

## D-003 — Outdoor terrain is not mineable

**Decision:** Outdoor landing blocks are plain `StaticBody3D`; cave shell blocks
are `MineableBlock`.

**Reason:** The player should enter the mine rather than dismantling spawn.

**Consequence:** Keep separate creation helpers for solid scenery and mineable
content.

## D-004 — Hide seams with visual overlap, not collision overlap

**Decision:** Use 2.02 visual size, 2.0 collision size, and a 2-unit grid.

**Reason:** Original 1.92 cubes produced visible gaps. Slight visual overlap
eliminates hairlines while exact collision adjacency stays stable.

## D-005 — Four damage conditions with arbitrary durability

**Decision:** Display 100%, 77%, 33%, and 1%, then destruction. Distribute the
three non-breaking thresholds using rounded hit positions.

**Reason:** Future blocks may have durability not divisible into three equal
hit counts.

**Consequence:** Maximum health must be at least four to show all three damaged
conditions.

## D-006 — Crack history is cumulative

**Decision:** State 2 includes state 1; state 3 includes states 1 and 2.

**Reason:** Previously replacing masks made cracked areas visually heal, which
was physically incoherent.

**Implementation:** Shader takes the maximum alpha of all masks included by the
target state.

## D-007 — Medium damage is intentionally restrained

**Decision:** New cracks in the 33% state render at 65% strength.

**Reason:** The medium and severe generated masks originally read too similarly.

## D-008 — Visual transitions never throttle mining

**Decision:** Crack state blending is 0.08 seconds and independent of `hit()`;
input has only a 0.05-second anti-event-spam cap.

**Reason:** Players should be able to break blocks as quickly as they physically
click within reason.

## D-009 — World-space triplanar base textures

**Decision:** Stone, coal, and grass sample in world space with triplanar
mapping; crack masks remain a separate overlay mapped with object-space
per-face UVs so each face shows the full centered mask.

**Reason:** Adjacent blocks should read as a continuous cave surface rather than
each face stamping the same full image. Damage art must remain reusable when
base textures change.

## D-026 — Crack interiors are a pigment-derived watercolor cavity

**Decision:** Keep the three existing crack *masks* as a thin coverage vector
only (`alpha_scissor = 0.28`, no bleed). Do not fill them with a flat tint,
lifted or black. The overlay re-samples the block's own world-triplanar
albedo, stains that rock toward the texture's vein hue, and multiplies a
shallow groove (0.86→0.62). Pigments (body = mean RGB, vein = high-
saturation mean) are hue references, not a replacement fill. The overlay is
an opaque vertex-lit cutout so it shares Night lighting with the cube.

**Reason:** A black decal fought the painted style. Expanding the mask into a
brush-bleed made a thick rustic stamp that was still black. Replacing rock
with a solid pigment cannot look like depth *inside* the block. Staining the
actual cobble/ore paint keeps the same art, lets copper show orange in the
groove, and the 0.62 floor prevents a black core.

**Consequence:** Changing a block texture, or Admin-painting a cell, changes
the groove automatically. Do not restore `crack_tint` black. Do not add mask
bleed. Do not drop the groove floor below ~0.6. New block types inherit the
same two-pigment stain without a new mask set.

## D-010 — Copper is admin-placed, not a generated ore

**Decision:** Copper has a texture, material, 15-hit durability, and Field Pack
storage, but it only appears where Admin Mode paints it.

**Reason:** The type is needed for map authoring now. It still has no play-mode
spawn rule or economy role.

## D-011 — Field Rig is a four-slot vertical quick selector

**Decision:** Slots 1–4 directly mirror Field Pack cells 1–4 and are selected by
1–4. Their initial contents are Pickaxe, Torches, Empty, Empty; item behavior is
resolved from current cell contents rather than the slot number.

**Reason:** Establish quick equipment access without cloning Minecraft's
horizontal hotbar or prematurely building a full equipment framework.

## D-012 — Field Pack stores mined blocks in individual cells

**Decision:** E opens ten visible cells. Cell 1 starts with the hammer, cell
2 with the ten-torch stack, cell 3 with the tablet, and cell 4 with dynamite;
cells 1–4 are also the Field Rig. Every mined stone
or coal block occupies one separate empty cell. A full pack
rejects the final breaking hit and leaves that block at one health. Right-click
opens a single `THROW ITEM AWAY` action for occupied cells. Exhausting a usable
stack, currently torches, also frees its cell. Dragging onto an empty target
moves the item; dragging onto an occupied target swaps the two items.

**Reason:** Mining now yields physical inventory resources rather than gold,
while the prototype only needs deterministic slot occupancy—not a generalized
item framework.

## D-013 — Torches are practical lights, not global illumination

**Decision:** Torches consume inventory, mount to block surfaces, flicker, cast
soft dynamic shadows, and create a broad warm visibility pool. While equipped,
the held torch provides the same kind of local light at half the placed base
energy. Placement uses right-click. A placed torch is left-clickable and is
destroyed without refund; its interaction collision does not block the player.

**Current approved tuning:** placed energy 2.35, held energy 1.175, range 25.12,
attenuation 1.08, shadow opacity 0.66, blur 2.6.

**Reason:** Earlier torches were too small/dim and their light-to-dark boundary
was too harsh. Current direction favors wider, brighter, gently transitioning
light while keeping Night navigable without one.

## D-014 — Current illumination is the canonical Night endpoint

**Decision:** The approved non-atmospheric illumination balance became the
`NIGHT_*` endpoint in `DayNightCycle`. Atmospheric depth is owned separately by
`RetroFog`; its Night endpoint is a minimal dark trace beginning at 18 m and
ending at 60 m with maximum intensity 0.08.

**Reason:** Day/night was added after Night had already been iteratively tuned.

**Consequence:** Adjust Day separately unless the user explicitly requests a
Night change. Keep Environment fog disabled and preserve the intentional minimal
`RetroFog` Night endpoint when tuning haze.

## D-015 — Cycle proportions and transition symmetry

**Decision:** Day 3/7, Dusk 1/7, Night 2/7, Twilight 1/7. Dusk and Twilight use
the same brightness curve in reverse.

**Current test duration:** one seventh = 60 seconds; full cycle = 420 seconds.

**Reason:** The user specified exact proportions and equal Dusk/Twilight
brightness behavior.

## D-016 — Y opens Time Test and Admin on one modal

**Decision:** Y opens a clickable menu with Day maximum, Dusk midpoint, Night,
Twilight midpoint, Admin On/Off, Save Map, and Reset Stone Cube.

**Reason:** Lighting comparison and map sculpting are both development tools
and should not be separate hidden keybinds.

**Consequence:** It is mutually exclusive with Field Pack, locks player input,
but does not pause the clock. Admin Mode remains on after the menu closes.

## D-017 — Renderer remains Compatibility for now

**Decision:** Continue using `gl_compatibility`.

**Reason:** It is the validated baseline and keeps the prototype broadly
compatible.

**Consequence:** Compatibility screen/depth textures and one fullscreen custom
postprocess are allowed and validated. Environment engine fog remains disabled
for the current effect. Do not design core visuals around Forward+-only
volumetric fog, `FogVolume`, or other unverified features. A future renderer
migration needs an explicit visual/performance test.

## D-018 — Play mode and Admin Mode stay separate

**Decision:** Default play mines with durability and inventory. Admin Mode
one-hit deletes without inventory and sets block type from a right-click menu.

**Reason:** The cube is a map-authoring workspace. Treating every carve as
normal mining made the play loop and the editor fight each other.

**Consequence:** `main.gd` owns the admin flag and copies it to the player.
Play-mode right-click must not cycle ore.

## D-019 — Only the voxel map is persisted

**Decision:** Save Map (and dirty exit) write `user://sculpted_volume.bin`.
Inventory, time, and placed torches still reset each run.

**Reason:** The sculpt is the work product of Admin Mode. A full game save is
not needed until there is progression worth keeping.

## D-020 — Two-tier surface streaming

**Decision:** `BlockVolume` stores every cell in a byte array. Exposed cells in
8-cell chunks intersecting a 14-cell sphere become interactive `MineableBlock`
bodies; the visible region extends to 28 cells with per-material `MultiMesh`
batches and retains chunks through 36 cells. Targets refresh after 4 cells of
travel and transition work targets 4 ms per frame. New representation loads
before old representation is hidden.

**Reason:** The 80×320×80 logical mine contains 2,048,000 cells. A raw doubled
region made roughly 3,968 startup faces into bodies and an aggressive synthetic
movement profile peaked at 103 ms. The two-tier measurement used 1,322 bodies
plus 2,656 batched faces; budgeted stream calls stayed below 11 ms while idle
bodies remained excluded from per-frame processing.

## D-021 — Native play is 1920×1080 fullscreen

**Decision:** Keep the 1920×1080 design viewport and start in fullscreen mode.

**Reason:** Godot's embedded Game panel scales the project into its available
editor area, which appeared as 1656×932 on the development display. Fullscreen
launch tests the project at the actual native display resolution.

## D-022 — Visible radiation-adjacent Day haze palette

**Decision:** Preserve the quirky green/purple art direction: Day distance tends
toward moss `#718451` while purple ambient (`#806f91`) and purple-charcoal
background (`#403847`) supply countertones. Night keeps only a near-black violet
fog target `#17131d`. Dusk and Twilight interpolate the same endpoints in
opposite directions. D-024 owns the texture-free implementation.

**Reason:** Green distance collapse plus purple shadow/background color keeps the
radiation-adjacent identity without painting nearby stone with an opaque filter.
Substantially recessing atmospheric depth at Night gives darkness and practical
torches a different role.

**Consequence:** Keep the palette restrained and Compatibility-safe. Validate
native-resolution Day, Night, and both transition midpoints after any fog,
ambient, or background tune. Environment engine fog stays disabled.

## D-023 — One-block rises use a contextual ledge pull-up

**Decision:** Keep the ordinary jump at upward velocity 5.2. A ledge assist
requires one uninterrupted Space hold from the grounded jump through the
0.08-second normal airborne lead-in and probe inside the 0.28-second opportunity
window. Releasing before the catch permanently locks climbing out for that
airborne jump, so pressing Space again in midair cannot re-arm it. A tap is
therefore always an ordinary jump.

Once caught, commit the climb even if Space is released. The deliberate
0.76-second action grabs through normalized time 0.28, braces/hangs through 0.42,
pulls vertically through 0.82, then settles/vaults inward. Add a 0.06-meter body
reach arc and 0.025-meter brace sag. The camera adds up to 0.14 meters of dip,
0.085 meters of forward lean, 0.018 meters of lateral bob, two 0.028-meter
vertical effort tugs, and 1.1 degrees of roll.

**Safety boundary:** Only non-torch `StaticBody3D` ledges 1.55–2.20 units above
takeoff and within 1.15 units qualify. Center/side support probes plus real
capsule-clearance checks at hang, lift, and landing reject narrow corners,
two-block walls, and obstructed tops. Animated movement remains collision
checked. Finish, collision abort, and E/Y cancellation restore the exact camera
position and zero roll; E or Y still opens its modal. Placed torches on collision
layer 2 remain ignored.

**Reason:** Raising global jump height would make a two-unit block trivially
floaty. Requiring a continuous hold makes climbing deliberate and prevents
forward motion after an ordinary jump from causing an unwanted catch. The
longer staged struggle communicates that the player only just clears the edge
and has to brace and pull themselves over, while preserving the existing jump
everywhere else.

## D-024 — Replace textured wisps with texture-free PS2-inspired fog

**Superseding decision:** The textured `AtmosphericSmoke` strategy was rejected
and is removed. Do not restore its four particle emitters, 32 billboards, bitmap
asset, local haze geometry, or layered Environment fog. `RetroFog` and
`shaders/retro_fog.gdshader` are the sole distance-fog implementation, while
Environment engine fog remains explicitly disabled to prevent double
application.

**Implementation:** `RetroFog` creates one camera-child fullscreen QuadMesh pass.
The Compatibility shader samples screen and depth once per pixel, reconstructs
linear depth, shapes one fog coefficient, and blends toward one `fog_color`. It
quantizes through 16 coefficient bands and a static inline 4×4 Bayer ordered
dither. There is no bitmap lookup, particle simulation, local haze mesh, temporal
noise, or shimmer.

**Day/night behavior:** The pass reads `DayNightCycle`'s existing smooth
daylight scalar and derives the symmetric fog-only weight
`1 - (1 - daylight)^2`. Night→Day endpoints are: begin 18→5 m, end 60→38 m,
curve 1.0→0.85, maximum intensity 0.08→0.88, color
`#17131d`→`#718451`, and retro quantized mix 0.0→0.70. Begin, end, curve, color,
retro mix, and a base intensity keep that eased interpolation. Intensity then
uses `smoothstep(0, 1, 4 * daylight * (1 - daylight))` to blend toward a
transition-only 0.96 crest. Either transition midpoint therefore keeps begin
8.25 m, end 43.5 m, curve 0.8875, and retro mix 0.525 while intensity reaches
0.96 instead of 0.68. Exact Night/Day endpoints and the ambient, background,
sun, and tonemap endpoints remain unchanged.

**Renderer and performance boundary:** Compatibility screen/depth textures and
the fullscreen custom pass are supported; Forward+ volumetric fog and
`FogVolume` remain prohibited. The effect removes transparent-card overdraw and
particle simulation, but Godot's screen/depth copies plus one screen and one
depth lookup for every 3D pixel are real GPU costs. Because the pass copies the
screen before transparent objects and then covers the view, world-space damage
overlays must stay in the opaque/cutout pipeline. A blended transparent crack
layer is overwritten and disappears.

**Validated result:** A native 1920×1080 capture shows crisp nearby texture and
an increasingly moss-green collapse with distance by Day, without repeating
artwork or cards. Night retains only a minimal dark trace, and Canvas UI is
unaffected.

**Reason:** The particle cards read as separate textured objects and did not
deliver the desired retro distance treatment. A quantized, ordered-dithered
depth coefficient evokes PS2-era fog directly, keeps the nearby mine readable,
and avoids animated texture noise or a second atmospheric layer.

## D-025 — Frame the landing between two opaque low-poly cloud strata

**Decision:** Add a broad faceted cloud deck below the landing and sparse
faceted islands above it. `CloudLayers` owns six whole-cloud procedural
silhouettes and reuses each in one lower and one upper opaque `MultiMesh` batch.
The silhouettes—compact, shelf, thunderhead, broken, anvil, and streak—use a
broad mixed size distribution and deterministic random X/Z scattering rather
than repeating one blob assembly on a grid.

**Layout and motion:** The 360-unit base tile repeats in a 5×5 X/Z field. Lower
base weighting `[14, 12, 8, 6, 5, 3]` produces 1,200 repeated instances; upper
weighting `[7, 6, 4, 3, 2, 2]` produces 600. Six lower batches drift along +X at
`0.16, 0.23, 0.32, 0.43, 0.57, 0.74` units/s; six upper batches drift along -X
at `0.29, 0.39, 0.51, 0.66, 0.84, 1.05` units/s. Each wraps independently at
the shared period while retaining fixed world altitude.

**Rendering boundary:** Clouds are environmental world geometry, not a second
fog implementation and not a return to D-024's rejected local haze cards.
`shaders/clouds.gdshader` is opaque, depth-writing, texture-free, and lit through
Compatibility vertex lighting, so the real directional sun and ambient
environment affect fixed lower `#d0d4c5` and upper `#c3c0ca` tints. There is no
manual daylight color lerp, transparency, collision, shadow casting, particles,
or texture asset. Opaque depth lets `RetroFog` treat cloud distance normally.

Broad scatter is allowed on every side of the mountain. Main supplies
`BlockVolume.get_visual_aabb()` to an exact shader fragment guard, preventing a
cloud from showing inside the mine mass without imposing the former positive-Z
layout edge. A coarse, instance-attached static dither progressively discards
fragments from 340 to 520 m, concealing the field's far boundary without alpha
sorting or a hard cutoff.

**Reason:** The player is fictionally extremely high, and one depth-color pass
cannot establish that spatial relationship by itself. A continuous lower deck
provides the drop/altitude cue; a sparse upper stratum places the player between
layers without replacing the open background. The original repeated blobs,
similar sizes/speeds, positive-Z boundary, and narrow altitude bands looked too
regular and ended abruptly. Whole-cloud archetypes, weighted sizes, randomized
full-tile scatter, twelve wind bands, broad altitude ranges, lighting response,
and a far dither address those failures while retaining low-poly batching.

**Validated result:** Native Compatibility captures at Day, Night, Dusk
midpoint, and Twilight midpoint show a readable lower ocean and separate upper
islands, with real depth fog in every phase. Same-phase sun-on/sun-off comparison
over a 6,227-pixel fog-disabled Day cloud mask measured mean RGB delta 0.48519
and p90 0.73464, confirming that renderer lighting changes cloud appearance.
Frozen Dusk/Twilight captures matched at image MAE 0.0. Automated inspection
measured 1,200 lower plus 600 upper instances across twelve batches, a validated
size ratio of 11.4508, no collision or shadow casting, and wind-time-zero bounds:
lower position `(-1053.326, -117.9921, -888.0961)`, size
`(2066.411, 106.8718, 1797.964)`; upper position
`(-1004.288, 35.97196, -873.4628)`, size
`(2085.454, 139.8139, 1781.159)`.

## D-026 — Resource items use rubble portraits and concise names

**Decision:** Stone, Coal, and Copper inventory entries use matching transparent
low-poly rubble portraits in the Field Pack, Field Rig, and drag preview. Their
display names are simply `STONE`, `COAL`, and `COPPER`; the mined-count line may
still show `x1`, but the former `BLOCK` suffix is removed from item labels,
equipped-item text, and collection feedback.

**Reason:** The mined reward represents broken material rather than an intact
placeable cube. A shared rubble silhouette with resource-specific fragments is
more legible and coherent with that state than text-only block entries.

**Consequence:** Keep the UI portraits under `assets/items/` and separate from
the triplanar world textures under `assets/blocks/`.

## D-027 — Use the industrial inventory artwork as the Field Pack itself

**Decision:** Field Pack is now an image-backed modal. A centered 1030×786
`TextureRect` displays `assets/ui/inventory_panel.png`; ten otherwise transparent
`InventorySlot` controls align with the artwork's five-by-two bay layout. The
full-viewport parent still catches input while open, but draws no fullscreen
color. Labels occupy the panel's existing black status displays rather than
covering its slot art with a second programmatic card.

The source panel and the Stone, Coal, and Copper portraits were exported as
RGBA PNGs, centered on their canvases, and verified with alpha-zero corner
pixels. Resource portraits remain 1024×1024 so Field Pack, Field Rig, and drag
preview can share one texture without per-view asset variants.

**Reason:** The former opaque backdrop and replacement `ColorRect` grid hid the
provided art, while baked white/checkerboard mattes made rubble portraits look
like pasted rectangles. One centered art layer plus transparent controls keeps
the requested presentation and existing inventory behavior independent.

**Consequence:** If the panel art is replaced, preserve its 1030×786 layout or
update the slot coordinates in `_create_inventory()` at the same time. Do not
flatten transparency when exporting PNGs; verify both pixel format and corner
alpha before committing a replacement.

## D-028 — Layer drifting mist over RetroFog, do not replace it

**Decision:** Keep `RetroFog` as the only distance-tint / PS2 banding pass.
Add `AtmosphericMist` as a CanvasLayer (`layer = -1`) ColorRect drawn after
all 3D. A 3D camera-child quad is covered by RetroFog's screen-reading pass
and is invisible. The mist shader rebuilds a view ray from uploaded camera matrices, samples
three world-space planes along it (canvas_item cannot read depth here), and
evaluates scrolling value-noise plus sparse hashed green speckles. It uses
no bitmap, particle nodes, fog cards, or engine volumetric fog.

Daylight uses the same `1 - (1 - daylight)²` ease and a Dusk/Twilight density
boost. Night is denser and violet-gray; Day stays present as dirty green-gray.
Speckles are procedural world cells, not emitters.

**Reason:** RetroFog already supplies the approved color-and-distance
atmosphere. The missing piece was tangible, uneven, moving air. A later
depth-aware alpha pass can sit on that tint without rewriting it. D-024's
rejected `AtmosphericSmoke` cards stay rejected.

**Consequence:** Do not fold mist into `retro_fog.gdshader`. Do not move the
mist pass back under the camera as a 3D quad. Code constants remain the
factory defaults; the Y-menu FOG tab can override them live and SAVE FOG
writes `user://fog_settings.cfg`. Nearby gameplay (held tools, mined faces)
must stay readable. Composite by staining the RetroFog'd screen in dense
banks, not by alpha-blending a solid color (light = milk, dark = invisible).

## D-030 — Fog sliders live in the Y menu and persist on Save Fog

**Decision:** Time Test / Admin is a two-tab panel. TIME / ADMIN keeps the
phase shortcuts and map tools. FOG exposes live sliders for AtmosphericMist
and RetroFog intensity. SAVE FOG writes `user://fog_settings.cfg` and that
file is loaded at startup as the new standard. RESET FOG restores the
script constants for the session only.

**Reason:** Finding a readable, scary mist level needs in-game iteration
with the real Day/Night lighting, not another guess in source.

**Consequence:** Do not remove the Time/Admin controls. Do not treat fog
slider save as a full game save.

## D-029 — Prevent zero-light entrance faces with a localized point fill

**Decision:** Add a shadowless `OmniLight3D` named `EntranceFill` at
`(0, 2.4, 11)`, outside the voxel front face at Z 6 and below most carved
ceilings. It uses range 18, attenuation 1.65, and 0.12 specular contribution.
`DayNightCycle` owns its interpolation: Night uses energy 0.42 / moss-green
`#77866a`; Day uses energy 0.72 / muted amber-green `#b39a68`. Dusk and Twilight
share the existing symmetric daylight scalar.

**Reason:** The first attempted horizontal directional fill only helped faces
whose normals pointed toward the entrance. A follow-up entrance screenshot
showed ceiling undersides and perpendicular cut walls still nearly black:
their dot product with both directional sources remained near zero. A point
source outside and below the opening sends upward rays into undersides and
lateral rays into side faces. Raising global ambient would instead flatten the
whole cave and weaken the need for torches.

**Scope:** The 18-unit range and 1.65 attenuation deliberately localize the
visibility floor. The source is shadowless so carved entrance faces do not fall
back into hard zero-light bands, but it should fade before becoming general cave
illumination. Player torches remain the only deep interior lights.

**Consequence:** Do not convert this back to a directional light, raise global
ambient to solve entrance normals, or extend the range deep into the volume.
If the opening/spawn moves, reposition the light outside and below the new
entrance; validate underside and both side orientations at Day and Night.

## D-031 — Lighting is occlusion plus local sources, not a global wash

**Decision:** Treat the mine as a sunlit exterior and a dark interior. Global
ambient is only a dim floor (Night 0.16, Day 0.18). Daytime brightness is the
shadow-casting sun. Exposed near blocks and far MultiMesh chunks cast shadows
so the hollow voxel shell actually occludes daylight. Remove the floating
entrance/deep cave OmniLights. Keep `EntranceFill` as the only non-torch
interior leak, with Day energy 0.95. Held tools stay unshaded.

**Reason:** With shadows off, every face was Lambert-lit by the sun regardless
of depth, so Day interiors did not get darker. Raising ambient or adding fill
OmniLights made visible blobs and flattened Night. The correct fix is
occlusion.

**Consequence:** Do not reintroduce interior practicals to "see the cave."
Do not raise Day ambient back toward 0.34. If shadow cost becomes a problem,
keep casters on the near tier first; do not disable all block shadows.

## D-032 — Dynamite is lit, charged, and thrown; blast comes later

**Decision:** Slot 4 starts with one dynamite. Right click lights a 6 s fuse.
Hold left click up to 5 s (5 strength per second) and release to throw a
`ThrownDynamite` RigidBody3D. Main consumes the inventory cell. A fuse that
burns out in hand also consumes the cell. Explosion and player damage are not
implemented yet.

**Held pose:** restore the pre-throw `HeldProp` rest `(0.56, -0.50, -0.86)` /
`(-18, 10, -14)` so the stick stays visible. Wind-up only raises and pulls it
toward the shoulder; do not change yaw enough to aim the stick down the camera.

**Reason:** Lighting and throwing are the requested loop. Visibility regressed
when the held mesh was replaced; the original prop setup is the baseline.

**Consequence:** Do not swap the held dynamite for a new first-person builder
without a screenshot that matches the original rest pose. Add blast on the
existing fuse timer when requested.

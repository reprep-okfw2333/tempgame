# Systems and Tuning Reference

Last audited against source: 2026-08-17

This document records current behavior and exact values. Source code remains
authoritative; update this file whenever values change.

## 1. Project and renderer configuration

| Setting | Current value | Source |
|---------|---------------|--------|
| Godot feature version | 4.7 | `project.godot` |
| Validated engine | 4.7.1 stable | development environment |
| Main scene | `res://main.tscn` | `project.godot` |
| Renderer | `gl_compatibility` | `project.godot` |
| Viewport | 1920×1080 | `project.godot` |
| Window mode | Fullscreen (`3`) | `project.godot` |
| Stretch mode | `canvas_items` | `project.godot` |
| Default clear color | `(0.055, 0.07, 0.075, 1)` | `project.godot` |

Compatibility rendering supports the screen and depth textures used by the
custom `RetroFog` fullscreen pass. The shader reconstructs linear depth and
blends the rendered scene toward one fog color; it is not volumetric fog.
Forward+-only features such as SDFGI, volumetric fog, `FogVolume`, or
`FogMaterial` remain prohibited without an explicit renderer decision and
hardware test. Environment engine fog is disabled so it cannot double the
custom coefficient.

## 2. Input map

| Action name | Physical input | Used by |
|-------------|----------------|---------|
| `move_forward` | W | player physics |
| `move_back` | S | player physics |
| `move_left` | A | player physics |
| `move_right` | D | player physics |
| `jump` | Space | tap for a normal jump; uninterrupted hold authorizes a one-block ledge climb |
| `mine` | Left mouse | Present in map; direct mouse event mines/removes torches |
| `inventory` | E | Field Pack toggle |
| `slot_1` | 1 | Select Field Pack/Field Rig cell 1 |
| `slot_2` | 2 | Select Field Pack/Field Rig cell 2 |
| `slot_3` | 3 | Select Field Pack/Field Rig cell 3 (tablet) |
| `slot_4` | 4 | Select Field Pack/Field Rig cell 4 (dynamite) |
| `cheat_menu` | Y | Time Test / Admin toggle |
| `ui_cancel` | Escape | built-in action used for close/release |

Player item use listens directly for pressed mouse events rather than polling:
left-click mines, admin-deletes, or removes a placed torch; right-click places
an equipped torch in play mode or opens the admin block setter. Holding does
not repeat.

## 3. Player controller

Defined in `scripts/player.gd`.

| Constant/property | Value | Meaning |
|-------------------|-------|---------|
| `SPEED` | 6.0 | Horizontal units per second |
| `JUMP_VELOCITY` | 5.2 | Upward velocity |
| `MOUSE_SENSITIVITY` | 0.0022 | Radians per mouse delta unit |
| `REACH` | 6.0 | Mining/placement ray length |
| `MIN_MINE_INTERVAL` | 0.05 s | Shared item-use event cap |
| Capsule radius | 0.42 | Player collision |
| Capsule height | 1.8 | Player collision |
| Capsule center Y | 0.9 | Places feet near player origin |
| Camera Y | 1.62 | First-person eye height |
| Pitch clamp | -1.45..1.45 rad | Prevents camera inversion |
| `LEDGE_CHECK_DISTANCE` | 1.15 | Forward wall-probe reach |
| `LEDGE_MIN_HEIGHT` | 1.55 | Minimum top height above takeoff |
| `LEDGE_MAX_HEIGHT` | 2.20 | Maximum top height above takeoff |
| `LEDGE_ATTEMPT_DELAY` | 0.08 s | Normal-jump lead-in before probing |
| `LEDGE_ATTEMPT_WINDOW` | 0.28 s | Total ascending probe window |
| `LEDGE_CLIMB_DURATION` | 0.76 s | Committed grab/brace/pull/vault duration |
| `LEDGE_GRAB_PHASE` | 0.28 | Normalized end of rise/grab phase |
| `LEDGE_BRACE_PHASE` | 0.42 | Normalized end of hang/brace phase |
| `LEDGE_LIFT_PHASE` | 0.82 | Normalized end of vertical pull phase |
| Ledge body effort | 0.06 m reach arc, 0.025 m brace sag | Temporary path offsets before the pull |
| Ledge camera effort | 0.14 m dip, 0.085 m forward lean, 0.018 m side bob, two 0.028 m tugs, 1.1° roll | Peak temporary first-person motion |

Gravity comes from `CharacterBody3D.get_gravity()` and therefore follows the
project/world gravity setting rather than a script constant.

Horizontal deceleration uses `SPEED * 7 * delta`. Movement bob advances at
10 radians/second while moving and 3 while idle.

### Contextual one-block ledge climb

Pressing Space while grounded always begins the ordinary jump with
`JUMP_VELOCITY = 5.2`. Ledge assistance is eligible only while that same
physical press remains held: the controller waits 0.08 seconds so the takeoff
is visible, then probes during the remainder of the 0.28-second opportunity
window. Releasing before a catch immediately discards the opportunity for the
entire airborne jump, so pressing Space again in midair cannot re-arm it. A tap
therefore remains an ordinary jump. A candidate must be a non-torch
`StaticBody3D` within 1.15 units whose upward top is 1.55–2.20 units above the
takeoff root.

The center top ray and side support rays at ±0.72 capsule radii must find a
level top. The actual 0.42-radius, 1.8-high capsule must also fit at the hanging,
lifted, and final landing roots. These checks reject narrow corner catches,
blocked headroom, and two-block walls. `PlacedTorch` is explicitly excluded;
its layer-2 collision remains available for item rays without becoming a
climbable obstacle.

An accepted climb is committed for 0.76 seconds even if Space is then released:
rise/grab through normalized time 0.28, a hanging brace through 0.42, the
vertical pull through 0.82, then the final inward settle/vault. The body adds a
0.06-meter reach arc during the grab and a 0.025-meter sag while bracing to make
the pull read as deliberate effort. `move_and_collide` guards every animated
step.

The camera effort envelope adds up to 0.14 meters of dip, 0.085 meters of
forward lean, 0.018 meters of lateral bob, two vertical pull tugs with
0.028-meter amplitude, and 1.1 degrees of roll. Finish, E/Y cancellation, and
unexpected collision all restore the exact `(0, 1.62, 0)` camera position and
zero roll. Normal movement, looking, slot selection, and item use are suppressed
once the ledge is caught so the short staged motion remains committed. E or Y
cancels cleanly, restores camera/velocity state, and opens the requested modal;
releasing Space does not cancel an accepted climb.

### Hammer presentation

- Rest position: `(0.50, -0.36, -0.58)` in camera space.
- Facing lives on the mesh child: `(-24, 90, -16)` degrees so a striking face
  aims down the look axis.
- Built by `HeldProp` from `assets/models/FieldHammer.glb`. Visual scale 1.9,
  grip offset `(0.02, -0.16, 0.02)`.
- A parent `HammerArm` swings in camera space so the 90° facing does not
  remap the chop onto the look axis.
- Swing duration: 0.36 seconds.
- Wind-up through 0.38: ease-out to `+48°` X / `+16°` Z and a short lift.
- Strike through 0.86: cubic ease-in to `-58°` X / `-22°` Z and a forward
  thrust toward the crosshair.
- Last 0.14: short settle, then idle lerp returns the arm to rest.
- The animation may be restarted by rapid input; it does not gate damage.
- Held tool materials are unshaded so their atlases stay readable without
  extra first-person lights.

### Held tablet presentation

- Rest position: `(0.26, -0.18, -0.46)` in camera space.
- Rest rotation: `(-22, 12, -6)` degrees.
- Built by `HeldProp` from `assets/models/FieldTablet.glb`. Visual scale 1.35.
- No use action yet. Selecting the tablet only shows the model and movement bob.

### Held dynamite presentation

- Rest position: `(0.48, -0.40, -0.68)` in camera space.
- Rest rotation: `(-20, 12, -16)` degrees.
- Built by `HeldProp` from `assets/models/FieldDynamite.glb`. Visual scale 2.15,
  extra local rotation `(10, 18, 8)`, grip offset `(0.0, -0.06, 0.0)`.
- Rest pose: `(0.56, -0.50, -0.86)`, rotation `(-18, 10, -14)`.
- Wind-up pose: `(0.50, -0.28, -0.60)`, rotation `(-42, 10, -20)`. The stick
  stays in the right hand, rises, and pulls toward the shoulder. Yaw is held
  near rest so it does not twist end-on. Charge uses a smoothstep and follows
  the hold tightly (`delta * 22` while charging).
- Right click lights a 6.0 s fuse (once). A spark sits on the fuse tip.
- Hold left click up to 5.0 s to charge. Strength = `5 * hold seconds`.
- Release throws a `ThrownDynamite` RigidBody3D: speed `3.6 + 0.42 * strength`,
  loft 0.22, gravity scale 1.55, mass 2.4, capsule collision, voxel resolve so
  far visual-only faces still stop it. The throw consumes the inventory cell.
- Blast and player damage are not implemented yet. A fuse that burns out in
  hand or in the world just removes the stick.

### Held torch presentation

- Position: `(0.58, -0.48, -0.92)`.
- Rotation: `(-12, 0, -18)` degrees.
- Six-sided cylinder shaft, height 0.72, radius 0.055–0.07.
- Six-segment sphere flame, radius 0.10, height 0.20.
- Flame Y: 0.45.
- Emission multiplier: 2.0.
- A child `OmniLight3D` uses the placed torch's color, range, attenuation, and
  shadow tuning.
- Held base energy: 1.175, exactly 50% of `PlacedTorch.BASE_ENERGY` (2.35).
- The held light and flame flicker while equipped and disappear with the held
  model when another or empty Field Rig cell is selected.

### Empty-hand presentation

- Visible only when the selected Field Rig cell is empty.
- Camera-space rest position: `(0.56, -0.55, -0.82)`.
- Three low-poly `BoxMesh` pieces form a palm, fingers, and thumb.
- Skin placeholder color: `#b97955`.
- Uses the same movement bob scale as other held items.

## 4. Field Rig and Field Pack

### Field Rig

- Four vertically stacked slots anchored top-right.
- Slot size: 126×58 pixels.
- Slot vertical spacing: 68 pixels.
- Selected background: `#3a3328`.
- Unselected background: `#101617`.
- Amber accent strip: `#d39b4a`.
- Slots 1–4 directly render and equip `inventory_items[0..3]`.
- Stone, Coal, and Copper show their rubble icon beside the compact resource
  name when moved into a Field Rig cell.
- Initial mapping: `[HAMMER, TORCH x10, TABLET, DYNAMITE]`.
- The selected item ID, rather than the numeric slot, determines mining or
  torch placement behavior and which held model is visible.

### Field Pack

- Full-screen input-catching `Control` with no painted background. The visible
  world therefore remains visible outside the inventory artwork.
- Centered frame: a 1030×786 `TextureRect` using
  `assets/ui/inventory_panel.png`, which has real exterior alpha and balanced
  20-pixel transparent padding.
- Grid: five columns by two rows = ten cells.
- The ten transparent interaction cells are 176×171 pixels, begin at `(58,220)`
  inside the frame, and advance 180 pixels horizontally / 182 vertically. They
  sit directly over the ten painted bays instead of drawing replacement cards.
- Normal cells have zero-alpha fill. Only the active drag source receives a
  temporary amber fill at 48% opacity.
- The top black display holds `FIELD PACK` and `E CLOSE`; the lower display
  holds drag/right-click guidance. These labels are children of the centered
  frame so they remain registered to the artwork at every canvas stretch.
- Starting torch count: `main.gd` variable `torch_count := 10`.
- `inventory_items` contains ten string-backed cells. Cell 1 starts with the
  field hammer, cell 2 with the shared torch stack, cell 3 with the tablet,
  cell 4 with dynamite, and other cells start empty.
- Cells 1–4 use a distinct background and `RIG 1`–`RIG 4` labels in the Field
  Pack to make their shared quick-slot role visible.
- Stone and coal each occupy one non-stacking cell.
- Stone, Coal, and Copper cells render centered 1024×1024 project-local RGBA
  rubble icons with alpha-zero corners;
  drag previews carry the same icon and their names omit the `BLOCK` suffix.
- Right-clicking an occupied cell opens a `PopupMenu` with `THROW ITEM AWAY`.
  Selecting it clears that cell; discarding torches clears the whole stack and
  sets `torch_count` to zero.
- Dragging an occupied `InventorySlot` creates a floating label preview and
  marks the source with `#6a5030`.
- Dropping on another cell swaps their item IDs, which acts as a move when the
  target is empty. Dropping outside the grid cancels without changing items.
- Using the final torch clears cell 2 automatically; the shared Field Rig slot
  immediately reads `EMPTY` and the held torch is unequipped.
- There is no stack splitting. Inventory itself is not saved; only the cube is.

Opening either Field Pack or Time Test:

- makes the mouse visible;
- locks movement, jumping, look, mining, and placement;
- does not pause `_process`, physics, torch flicker, or time progression.

## 5. Block geometry and spacing

Defined by `MineableBlock` constants and mirrored for unbreakable blocks in
`main.gd`.

| Geometry | Size | Rationale |
|----------|------|-----------|
| Grid spacing | 2.0 | Stable world coordinate lattice |
| Base visual cube | 2.02 | 0.02 overlap prevents visible hairline gaps |
| Collision cube | 2.0 | Adjacent colliders meet without overlap |
| Crack overlay cube | 2.035 | Sits above base without z-fighting |

Do not make collision shapes 2.02 merely to match visuals; overlapping static
collision faces can cause undesirable movement behavior.

## 6. Resource blocks and inventory rewards

Current type branches live in `MineableBlock.setup()`.

| Type | Maximum health/hits | Inventory reward | Base material |
|------|---------------------|------------------|---------------|
| Stone | 10 | One Stone cell | `stone_material` |
| Coal | 20 | One Coal cell | `coal_material` |
| Copper | 15 | One Copper cell | `copper_material` |

Health lives in `MineableBlock._set_health_for_type()`. Unknown type strings
fall through to stone health. Adding a type requires a volume byte id, a
material, health, admin menu entry, and inventory display name.

`main.gd` owns ten string-backed inventory cells. The hammer, starting torch
stack, tablet, and dynamite use the first four cells. Every mined block uses one otherwise empty cell
without stacking. If no cell is empty, the final breaking hit is rejected and
the block stays at one health. Discarding an item or exhausting the torch stack
frees its shared inventory/Field Rig cell for a later block.

## 7. Damage-state algorithm

Defined in `scripts/mineable_block.gd`.

### State meanings

| State index | Display name | Included masks | Strength |
|------------:|--------------|----------------|----------|
| 0 | 100% intact | none | 0 |
| 1 | 77% | `cracks_77` | 1.0 |
| 2 | 33% | state 1 + `cracks_33` | new mask 0.65 |
| 3 | 1% | states 1–2 + `cracks_01` | new mask 1.0 |

These percentages are presentation labels, not literal health ratios.

### Rounded thresholds

Let:

```text
hits_taken = max_health - health
non_breaking_hits = max_health - 1
light_hit  = max(1, round(non_breaking_hits / 3))
medium_hit = max(light_hit + 1, round(non_breaking_hits * 2 / 3))
severe_hit = non_breaking_hits
```

The block breaks when health reaches zero. At least four maximum health is
needed to guarantee all three visible non-breaking stages.

Current thresholds:

| Type | 77% begins | 33% begins | 1% begins | Break request |
|------|------------|------------|-----------|---------------|
| Stone, max 10 | hit 3 | hit 6 | hit 9 | hit 10 |
| Copper, max 15 | hit 5 | hit 9 | hit 14 | hit 15 |
| Coal, max 20 | hit 6 | hit 13 | hit 19 | hit 20 |

### Shader composition

The overlay uses one per-block `ShaderMaterial` and one shared `Shader` object.
Godot `BoxMesh` UVs are a 3×2 atlas, so the shader rebuilds 0–1 coordinates
from local vertex position and face normal. Each face shows the full mask
centered, rather than a cropped atlas cell. The shader samples all three
images. For any state it calculates the maximum alpha of every mask included
up to that state. Therefore a pixel cracked in state 1 remains cracked in
states 2 and 3.

The old cumulative alpha and new cumulative alpha are mixed by
`blend_amount`. Script interpolation uses `smoothstep` over
`DAMAGE_BLEND_DURATION = 0.08` seconds.

The overlay is vertex-lit, cull-back, roughness 0.93, and an opaque cutout
(`discard` below `alpha_scissor = 0.28`, `depth_draw_opaque`). It does not
write `ALPHA`. Cracks must stay in the opaque pipeline so `RetroFog`'s screen
copy can see them. The 0.28 scissor keeps only the original stroke; dusty
fill in the later masks is discarded so the overlay cannot become a thick
black blotch.

### Watercolor groove (stained rock, not a fill)

The three masks are only a coverage vector. The overlay never paints a flat
color. It re-samples the same world-triplanar block albedo as the cube
(`uv1_scale`, sharpness 4) at `world_pos - normal * 0.008`, then stains and
shades that rock so the stroke reads as a shallow opening in the existing
paint.

`MineableBlock` samples the block albedo once per unique texture (128-cell
stride, cached) for two pigments used only as *hue*:

| Pigment | Rule |
|---------|------|
| Body | Mean RGB of every sampled texel. |
| Vein | Mean RGB of texels whose HSV saturation is above `1.25 ×` the texture's mean saturation. |

`apply_type()` rebinds pigments and the albedo sampler. If `get_image()`
fails, measured fallbacks are used. A missing albedo becomes a 1×1 body
swatch so the sampler cannot return black.

| Type | Body | Vein |
|------|------|------|
| Stone | `#423d32` | `#3b3527` |
| Coal | `#33302a` | `#332f27` |
| Copper | `#594334` | `#944016` |

Fragment steps:

1. Discard if mask `< 0.28`. No bleed, no expanded brush.
2. `depth = smoothstep(0.28, 1.0, mask)` along the original stroke.
3. Sample the block's own triplanar rock color.
4. Tint that rock toward the vein hue by 18–42% (hashed), plus a little body
   on the shallow lip. The pixel stays the same cobble/ore paint.
5. Multiply by a groove of 0.86→0.62. The 0.62 floor is what keeps the core
   from going black.
6. Add a thin highlight where the mask falls off upward, so the opening has
   a one-sided lip.

Vertex lighting then matches the cube, so Night darkens the groove the same
way it darkens the stone instead of turning it into an unshaded black decal.

If a hit arrives before a transition completes, the current target is finalized
and the next transition begins immediately. This keeps damage responsive and
crack history monotonic.

### Hit response

On every accepted hit:

- `hit_flash` becomes 0.10 seconds.
- Base and crack meshes shrink toward 0.88 scale then return to 1.0.
- Collision does not scale.

## 8. Base material and texture system

`main.gd::_block_material()` configures block materials:

- Albedo color: white (texture colors remain unchanged).
- Roughness: 0.92.
- Filter: linear with mipmaps and anisotropic filtering.
- UV1 triplanar: enabled.
- UV1 world triplanar: enabled.
- Triplanar sharpness: 4.0.

| Texture | Runtime use | `uv1_scale` | Status |
|---------|-------------|-------------|--------|
| `stone.png` | stone/cave/outdoor near rows | 0.25 | active |
| `coal.png` | coal blocks | 0.5 | active |
| `grass.png` | outdoor far rows | 0.25 | active |
| `copper.png` | admin-painted copper | 0.5 | active |

Inventory presentation loads `assets/items/stone.png`, `coal.png`, and
`copper.png` as transparent low-poly rubble icons. These are UI assets and do
not replace the triplanar block textures above.

Stone/grass scale 0.25 lets the painting span more world area and reduces
obvious repetition. Coal uses 0.5 so deposits remain recognizable per block.
World-space mapping makes adjacent cubes share a continuous surface.

Damage textures are project-local transparent PNGs in `assets/damage/`; they
must not be baked into base albedo textures. The fog system has no bitmap asset.

## 9. Spatial lighting

Created in `main.gd::_create_environment()` before the cycle takes ownership.

The mountain is a hollow shell of exposed voxels. Light only makes sense if
that shell occludes the sun: otherwise every interior face is day-lit by
Lambert response alone. Ambient is a dim floor so shadowed rock still shows
albedo. Outdoor Day brightness is the sun. Interior Day darkness is the sun
being blocked. The only interior sources are the entrance leak and torches.

### Environment baseline / Night

| Property | Value |
|----------|-------|
| Background mode | solid color |
| Background color | `#020304` |
| Ambient source | color |
| Ambient color | `#354247` |
| Ambient energy | 0.16 (cave floor; Day only rises to 0.18) |
| Tonemapper | Filmic |
| Adjustment brightness | 0.90 |
| Adjustment contrast | 1.16 |
| Adjustment saturation | 0.82 |
| Environment fog enabled | false; `RetroFog` is the sole distance treatment |

### Directional sun initial/Night

- Rotation: `(-52, -28, 0)` degrees.
- Color is immediately controlled by cycle Night endpoint `#9eafbd`.
- Energy: 0.32 Night / 1.15 Day.
- Shadows: enabled, four cascades, max distance 240 m, fade start 0.85.
- Bias 0.05, normal bias 2.0.
- Near `MineableBlock` meshes and far `MultiMesh` chunks cast shadows.
- Crack overlays and clouds do not.

### Local entrance fill

- Type / node name: `OmniLight3D` / `EntranceFill`.
- Position: `(0, 2.4, 11)`, just outside the volume front face at Z 6 and below
  most entrance ceilings.
- Range / attenuation: 18.0 / 1.65.
- Night color/energy: `#77866a` / 0.42.
- Day color/energy: `#b39a68` / 0.95.
- Specular contribution: 0.12.
- Shadows: disabled deliberately. This is a soft visibility floor for exposed
  entrance geometry, not a second source of hard shadow bands.
- The local point geometry sends upward rays into ceiling undersides and lateral
  rays into cut side walls, which the rejected horizontal directional fill
  could not do. Range and attenuation keep the lift near the opening so it does
  not replace torches deeper in the volume. There are no floating interior lamps.

## 10. Day/night cycle

Defined in `scripts/day_night_cycle.gd`.

### Timing

| Constant | Value |
|----------|-------|
| `SEVENTH_DURATION` | 60 s |
| `CYCLE_DURATION` | 420 s |
| `DAY_END` | 180 s |
| `DUSK_END` | 240 s |
| `NIGHT_END` | 360 s |

Timeline:

```text
0                  180       240                360       420/0
|------ DAY 3/7 -----| DUSK 1/7 |--- NIGHT 2/7 ---| TWILIGHT |
daylight = 1          fades 1→0  daylight = 0      fades 0→1
```

The initial `cycle_time` is 300 seconds, the middle of Night.

### Endpoint values

| Controlled property | Night | Day |
|---------------------|-------|-----|
| Ambient energy | 0.16 | 0.18 |
| Sun energy | 0.32 | 1.15 |
| Entrance fill energy | 0.42 | 0.95 |
| Adjustment brightness | 0.90 | 1.04 |
| Adjustment contrast | 1.16 | 1.08 |
| Adjustment saturation | 0.82 | 0.96 |
| Ambient color | `#354247` | `#806f91` |
| Background color | `#020304` | `#403847` |
| Sun color | `#9eafbd` | `#ffe0ad` |
| Entrance fill color | `#77866a` | `#b39a68` |
| Retro fog begin | 18 m | 5 m |
| Retro fog end | 60 m | 38 m |
| Retro fog curve | 1.0 | 0.85 |
| Retro fog maximum intensity | 0.08 | 0.88 |
| Retro fog color | `#17131d` | `#718451` |
| Retro quantized mix | 0.0 | 0.70 |

Dusk uses `1 - phase_progress`; Twilight uses `phase_progress`. Both are passed
through the same `smoothstep(0, 1, daylight)`, guaranteeing equal values at
equal mirrored progress. Their cheat shortcuts both choose 50% phase progress.
Ambient, sun, and entrance-fill endpoints all use that same scalar, so the new
fill does not break Dusk/Twilight brightness symmetry.
`RetroFog` derives a fog-only interpolation weight from that scalar:

```text
fog_daylight = 1 - (1 - daylight) ^ 2
```

Begin, end, curve, color, and retro mix interpolate with `fog_daylight`. Fog
intensity starts with the same eased endpoint interpolation, then adds a smooth
symmetric transition bell:

```text
transition_axis = 4 * daylight * (1 - daylight)
transition_peak = smoothstep(0, 1, transition_axis)
base_intensity = lerp(0.08, 0.88, fog_daylight)
fog_intensity = lerp(base_intensity, 0.96, transition_peak)
```

Exact Day and Night values remain unchanged. At either transition midpoint,
`daylight = 0.5`: begin is 8.25 m, end 43.5 m, curve 0.8875, retro mix 0.525,
and intensity now reaches 0.96 instead of 0.68. Representative intensity
samples are:

| Smooth daylight | Fog intensity |
|-----------------|---------------|
| 0.00 | 0.08 |
| 0.25 | 0.8771875 |
| 0.50 | 0.96 |
| 0.75 | 0.9396875 |
| 1.00 | 0.88 |

Dusk and Twilight traverse the same values in opposite directions, so equal
mirrored brightness remains identical. The stronger middle hides the streamed
world horizon without changing either constant-phase endpoint. Environment fog
remains disabled.

### Texture-free PS2-inspired RetroFog

`main.gd` creates `RetroFog` after the player, adds the controller under `Main`,
and calls `setup(player.camera, day_night_cycle)` plus `set_mine_bounds`.
Setup creates one 2×2
`QuadMesh` named `RetroFogPass` as a camera child and assigns
`res://shaders/retro_fog.gdshader`. The shader's clip-space vertex output makes
that quad cover the screen; it is not a large world-space haze surface.

The Compatibility spatial shader is unshaded, double-sided, depth-test disabled,
and depth-write disabled. Each pixel performs one nearest-filtered screen sample
and one nearest-filtered depth sample. It reconstructs linear view depth with
`INV_PROJECTION_MATRIX`, then computes:

```text
span = max(fog_end - fog_begin, 0.001)
coefficient = clamp((linear_depth - fog_begin) / span, 0, 1)
coefficient = pow(smoothstep(0, 1, coefficient), fog_curve)
stepped = floor(coefficient * 16 + bayer4(pixel)) / 16
styled = lerp(coefficient, stepped, retro_mix)
fog_amount = clamp(styled * fog_intensity, 0, 1)
output = lerp(screen_color, fog_color, fog_amount)
```

Outdoor Day/Night fog uniforms stay unchanged. The shader reconstructs each
pixel's world position and only uses the dark cave target (`#0b0d09`,
intensity 0.58) for surfaces inset from the mountain exterior. Torch-lit
cave walls stay on the cave path; the landing, the outer crust, and the view
out the mouth stay on outdoor fog.

`bayer4` is a static inline 4×4 Bayer ordered-dither matrix. It uses no texture,
time input, temporal noise, or shimmer. `FOG_BAND_COUNT` is fixed at 16. Night
sets retro mix to 0.0 for a minimal smooth dark trace; Day mixes 70% toward the
ordered 16-band coefficient. One `FOGCOL`/`fog_color` is used at a time—there
are no particles, textured wisps, local haze volumes, or repeating artwork.

The pass is a GPU postprocess cost: Godot must provide screen and depth textures,
and the shader executes one screen plus one depth lookup per 3D pixel. It has no
particle simulation or layered transparent-card overdraw. Canvas UI is drawn
outside the 3D treatment and remains unaffected. Draw priority is 120 so the
later mist pass can blend over this tint.

### Atmospheric mist layer

`main.gd` creates `AtmosphericMist` after `RetroFog`. Setup builds a
`CanvasLayer` at layer `-1` with a fullscreen `ColorRect` using
`shaders/atmospheric_mist.gdshader`. Canvas draws after every 3D pass, so
the mist actually lands on top of RetroFog. A 3D camera-child quad cannot:
RetroFog's screen-reading pass covers the view last and erases it.

`canvas_item` cannot sample the depth buffer here, so the shader rebuilds a
view ray from uploaded camera matrices and evaluates noise on three world
points along it. It *does* sample `hint_screen_texture` — the RetroFog'd
frame — and smothers the RetroFog'd frame in large slow fields: desaturate, dim,
and dirties toward Night `#3a3540` / Day `#657054`. That reads as thick air
instead of a sliding gray stamp. Near contribution is low; far is stronger.
Speckles stay sparse. A lower-right fade keeps the held tool readable.
HUD stays on CanvasLayer 0 above the mist.

Jobs stay split: RetroFog is distance color and banding; this pass is tangible,
uneven, moving air. There is no bitmap, particle node, or fog card.

World-space value-noise FBM (three octaves, no texture) is evaluated on a
partially quantized world position so the field is slightly low-resolution
without becoming screen-locked static. A slow XZ wind plus a cheap sine warp
on Y gives irregular horizontal drift.

Three overlapping depth bands, all from the same field at different scales
and speeds:

| Band | World scale | Wind | Depth weight | Role |
|------|-------------|------|--------------|------|
| Near | 1.55 / `mist_scale` | 1.35× | fades out by 13 m × `mist_near_amount` | larger, faster, subtle |
| Mid | 1.00 / `mist_scale` | 1.00× | 3.5–50 m | primary drifting banks |
| Far | 0.52 / `mist_scale` | 0.42× | from 16 m × `mist_far_amount` | slower, merges into RetroFog |

Night stain is `#4a4552`; Day is `#6a7358`. Veil is
`lerp(0.10, 0.36, mist)` so a low haze is always present and thickenings
stay visible without the old 0.58 slab mix. Scale 13, contrast 0.55.

Sparse speckles are world-cell hashes, not emitters. A cell appears only if
its seed clears `speckle_density * 0.085` and local mist is already present.
Size, pulse, and a tiny wind drift vary per cell. Color is muted `#6e7d48`.

Daylight uses the same ease as RetroFog:

```text
fog_daylight = 1 - (1 - daylight) ^ 2
transition_peak = smoothstep(0, 1, 4 * daylight * (1 - daylight))
cycle_mul = lerp(1.10, 0.88, fog_daylight)
cycle_mul = lerp(cycle_mul, cycle_mul * 1.15, transition_peak)
```

| | Night | Day |
|---|---|---|
| Mist stain | `#4a4552` muted violet-gray | `#6a7358` dirty moss |
| Density multiplier | 1.10 | 0.82 |
| Speckle brightness | ×1.15 | ×0.88 |

Mist stays on in Day. Dusk/Twilight are the densest. Tuning constants live
on `AtmosphericMist`: `MIST_DENSITY`, `MIST_OPACITY`, `MIST_AMBIENT`, `MIST_SCALE`,
`MIST_SPEED`, `MIST_DIRECTION`, `MIST_CONTRAST`, `MIST_DEPTH_FALLOFF`,
`MIST_NEAR_AMOUNT`, `MIST_FAR_AMOUNT`, `SPECKLE_DENSITY`, `SPECKLE_SIZE`,
`SPECKLE_BRIGHTNESS`, `SPECKLE_SPEED`, `SPECKLE_COLOR`,
`DAY_MIST_MULTIPLIER`, `NIGHT_MIST_MULTIPLIER`.

### Exterior low-poly cloud layers

`main.gd` creates one `CloudLayers` after the player and before `RetroFog`.
`CloudLayers.setup(block_volume.get_visual_aabb())` generates six whole-cloud
`ArrayMesh` silhouettes. Each silhouette combines four to seven deformed,
flat-shaded icosahedral lobes into a compact mound, shelf, thunderhead, broken
twin island, anvil, or diagonal wind streak. Duplicated triangle vertices carry
quantized face values, and randomized instance colors add restrained value and
warmth variation.

Each silhouette is reused by one lower and one upper `MultiMesh` batch. The two
shared `ShaderMaterial`s use `shaders/clouds.gdshader`, whose Compatibility-safe
render mode is `vertex_lighting`, `specular_disabled`, `cull_back`, and
`depth_draw_opaque`. Fixed layer tints therefore receive the actual directional
sun and ambient environment; `CloudLayers` neither stores `DayNightCycle` nor
manually interpolates cloud color. Opaque cloud depth remains available to the
later `RetroFog` pass.

| Setting | Lower cloud deck | Upper cloud islands |
|---------|-------------------|---------------------|
| Silhouette / wind batches | 6 | 6 |
| Base instances by silhouette | `14, 12, 8, 6, 5, 3` | `7, 6, 4, 3, 2, 2` |
| Repeated X/Z copies | 5×5 | 5×5 |
| Total instances | 1,200 | 600 |
| Fixed tint | `#d0d4c5` | `#c3c0ca` |
| Drift speeds (units/s) | `+0.16, +0.23, +0.32, +0.43, +0.57, +0.74` | `-0.29, -0.39, -0.51, -0.66, -0.84, -1.05` |
| Wind-time-zero world AABB position | `(-1053.326, -117.9921, -888.0961)` | `(-1004.288, 35.97196, -873.4628)` |
| Wind-time-zero world AABB size | `(2066.411, 106.8718, 1797.964)` | `(2085.454, 139.8139, 1781.159)` |
| Validated Y extent | `-117.99..-11.12` | `35.97..175.79` |

The deterministic base layout scatters centers randomly across both X and Z of
a 360-unit tile, with short rejection sampling for local separation. Every base
instance is copied across offsets -720, -360, 0, +360, and +720 on both axes.
Each batch has its own initial phase and X speed, wraps after 360 units, and
retains its fixed world altitude. The validated mixed scale distribution spans
a maximum/minimum ratio of 11.4508, including uncommon very small and very large
silhouettes rather than a uniform cloud size.

The cloud shader rejects fragments inside the exact AABB supplied by
`BlockVolume.get_visual_aabb()`, so the broad X/Z scatter cannot leak into the
mountain volume. From 340 to 520 m camera distance, an instance-seeded static
object-space dither sampled at a coarse 0.45 mesh-local factor progressively
discards fragments, concealing the field's far limit without alpha blending or
a hard horizontal cutoff. Clouds have no
`CollisionObject3D`, light nodes, shadow casting, transparency, particles,
emission, or bitmap textures. Each batch supplies a custom AABB that covers all
repeated transforms.

### Time-test shortcuts

| Menu button | `cycle_time` selected |
|-------------|-----------------------|
| Day / Maximum | 90 s |
| Dusk / Midpoint | 210 s |
| Night | 300 s |
| Twilight / Midpoint | 390 s |

Selecting a shortcut does not freeze time; the cycle resumes immediately from
that point.

## 11. Placed torch system

Defined in `scripts/placed_torch.gd`.

### Placement/model

- Root offset from hit point: normal × 0.35.
- Root rotation: shortest quaternion from local Up to surface normal.
- Shaft: six-sided cylinder, height 0.68, radius 0.055–0.075.
- Flame: six-segment sphere, radius 0.095, height 0.19, Y 0.43.
- Flame emission multiplier: 2.6.
- Flame does not cast shadows.
- Torch has no base texture.
- A local-Y cylinder collision (radius 0.14, height 0.85) makes it left-clickable.
- Collision layer 2 is ray-visible but ignored by the player's layer-1 mask.

### Light

| Property | Value |
|----------|-------|
| Type | `OmniLight3D` |
| Local Y | 0.43 |
| Color | `#ff9a52` |
| Base energy | 2.35 |
| Range | 25.12 |
| Attenuation | 1.08 |
| Shadows | enabled |
| Shadow bias | 0.08 |
| Shadow normal bias | 1.1 |
| Shadow opacity | 0.66 |
| Shadow blur | 2.6 |

The range, attenuation, and shadow constants are shared with the held torch;
only its base energy is halved.

### Flicker

Each instance receives a random initial phase. Every frame:

```text
slow_wave = sin(time * 7.3 + phase) * 0.07
fast_wave = sin(time * 17.1 + phase * 1.7) * 0.035
flicker = 0.92 + slow_wave + fast_wave
energy = BASE_ENERGY * flicker
flame Y scale = 1 + fast_wave * 2.2
```

Approximate flicker multiplier range is 0.815–1.025. The asymmetric baseline
keeps average output below the static base energy.

## 12. Sculptable volume and Admin Mode

Defined in `scripts/block_volume.gd`. Policy (play vs admin, inventory, save
button) stays in `main.gd`.

| Constant | Value |
|----------|-------|
| `SIZE` | `Vector3i(80, 320, 80)` — 2,048,000 cells |
| `CELL` | 2.0 |
| `INTERACTION_RADIUS` | 14-cell near body region |
| `STREAM_RADIUS` | 28-cell nominal visible region (56 world units) |
| `DESPAWN_RADIUS` | 36-cell retention region |
| `STREAM_UPDATE_DISTANCE` | 4 cells before target regions update |
| `STREAM_CHUNK_SIZE` | 8 cells per axis |
| `STREAM_WORK_BUDGET_USEC` | 4,000 µs queued work target per frame |
| `SAVE_PATH` | `user://sculpted_volume.bin` |
| `SAVE_MAGIC` | `LPM1` |
| Cell ids | 0 air, 1 stone, 2 coal, 3 copper |

Origin is computed in `setup()` so the +Z face is at world Z `6`, X is centered
on 0, and Y of the bottom layer is `-1`.

Surface rule: a filled cell is spawned if any of the six neighbors is air or
out of bounds. Breaking a cell sets air, frees the node, and spawns any newly
exposed neighbors.

Chunks whose bounds intersect the 14-cell sphere use individual interactive
`MineableBlock` bodies. Other chunks intersecting the 28-cell sphere use up to
three `MultiMeshInstance3D`s (stone/coal/copper) with no collision. Whole chunks
add hidden distance padding; 36-cell retention prevents reverse-direction
thrash. Promotions build bodies before hiding the far batch, and demotions build
the batch before queue-freeing bodies. After startup, transition work is queued
with near promotion ahead of far loading and unloading.

The current smoke-test map measured 1,322 near bodies and 2,656 far instances
(3,978 visible faces). Counts vary with the saved sculpt. Idle near blocks still
disable `_process()` except during their 0.10-second hit flash or 0.08-second
crack blend. The combined check measured a 6.2 ms worst queued stream call;
an aggressive synthetic path remained below 11 ms after budgeting, versus a
103 ms peak when all 3,968 startup faces were individual bodies.

`dirty` becomes true on remove, paint, or reset. `save_to_disk()` writes magic,
three `u16` sizes, then the byte buffer. Exit-tree saves if dirty.

Admin Mode (`main.gd.admin_mode`, copied to `MinerPlayer.admin_mode`):

- Left click deletes without inventory.
- Right click opens a `PopupMenu` (Stone / Coal / Copper) at the pointer.
- Y menu TIME / ADMIN tab: ENTER ADMIN / ADMIN ON, SAVE MAP, RESET STONE CUBE.
- Y menu FOG tab: live sliders for mist opacity/ambient/density/contrast/
  scale/speed/near/far, day/night mist multipliers, speckle density/brightness,
  and RetroFog day/night/transition intensity. SAVE FOG writes
  `user://fog_settings.cfg`. RESET FOG restores code defaults without deleting
  the file until the next save.
- HUD badge `ADMIN MODE` or `ADMIN · UNSAVED`.

Play mode never opens the setter and never one-hit deletes.

## 13. HUD and feedback

- Pack occupancy panel: top-left, 250×86 at `(22, 20)`.
- Phase label shares the pack panel area.
- Tool name appears below pack occupancy.
- Crosshair is a centered `+` label.
- Context help is bottom-left and changes by selected slot/menu.
- Reward/status popup is centered 46 pixels below center.
- Popup alpha lasts 0.8 seconds and fades using `time * 2.5`.
- Time label updates only on phase boundary, not with numerical clock progress.

UI is currently assembled with fixed pixel offsets for a 1920×1080 design.
Anchors are used for center/right/bottom elements, but responsive layout at
other aspect ratios is not fully validated.

## 14. One-page tuning index

| Desired change | Edit location |
|----------------|---------------|
| Move speed/jump/reach/click cap | constants in `player.gd` |
| Hammer/tablet/dynamite/held torch appearance | `player.gd::setup` / `held_prop.gd` / `_create_held_torch` |
| Stone/coal/copper health | `MineableBlock._set_health_for_type` |
| Crack speed/sizes/strengths | constants in `mineable_block.gd` |
| Crack blending logic | shader string + transition methods in same file |
| Crack watercolor pigments / cavity wash | `_sample_pigments` + crack shader in `mineable_block.gd` |
| Block texture scale/filter | `main.gd::_block_material` |
| Cube size / save path | `BlockVolume` constants |
| Landing size | `main.gd::_build_cave` |
| Spawn | `main.gd::_create_player` |
| Starting inventory/torches | top-level vars in `main.gd` |
| Field Rig/Pack layout | UI creation methods in `main.gd` |
| Sun shadows / entrance leak / ambient floor | `main.gd::_create_environment`, `day_night_cycle.gd` |
| Night/Day lighting and timing | `day_night_cycle.gd` constants |
| Retro fog ranges/curve/intensity/color/transition ease/bands | `retro_fog.gd` constants; day/night/transition intensity also on the Y FOG tab |
| Retro fog depth reconstruction/banding/Bayer dither | `shaders/retro_fog.gdshader` |
| Atmospheric mist density/opacity/scale/speed/direction/contrast/depth | constants in `atmospheric_mist.gd` |
| Mist noise layers / speckle hash | `shaders/atmospheric_mist.gdshader` |
| Cloud silhouettes/counts/altitudes/scales/wind/tints/layout seeds/far fade | `cloud_layers.gd` constants and setup |
| Cloud lighting/mine exclusion/static dither | `shaders/clouds.gdshader` |
| Stream radii/chunks/frame budget | `block_volume.gd` constants |
| Torch range/brightness/softness/flicker | `placed_torch.gd` |
| Input keys | `[input]` in `project.godot` |

# Architecture

Last audited against source: 2026-08-17 (dynamite throw, spatial lighting, cave fog)

## 1. Architectural style

This project currently uses a code-built prototype architecture:

- `main.tscn` contains one `Node3D` named `Main`.
- `scripts/main.gd` is the composition root.
- Materials, environment, cloud strata, retro fog, cave geometry, player, HUD, and
  modal panels are created at runtime.
- Reusable behavior is split into named GDScript classes: `MinerPlayer`,
  `HeldProp`, `ThrownDynamite`, `MineableBlock`, `BlockVolume`, `PlacedTorch`,
  `DayNightCycle`, `CloudLayers`, `RetroFog`, `AtmosphericMist`, and
  `InventorySlot`.
- There are no autoload singletons, dependency injection containers, plugins,
  addons, data services, or serialized gameplay scenes.

This is intentional for the prototype. Split systems into scenes/resources only
when their complexity or reuse justifies it.

## 2. Initialization order

`main.gd::_ready()` calls these methods in this exact order:

1. `_create_materials()`
2. `_create_environment()`
3. `_build_cave()` (landing + `BlockVolume`)
4. `_create_player()`
5. `_create_cloud_layers()`
6. `_create_retro_fog()`
7. `_create_atmospheric_mist()`
8. `_create_ui()`

Dependencies make the order important:

- Cave blocks require materials and crack textures.
- `DayNightCycle` requires the Environment, primary directional sun, and local
  entrance OmniLight created by `_create_environment()`.
- The player requires shared wood/metal materials.
- `CloudLayers` requires the already-built `BlockVolume` visual AABB so its
  shader can reject fragments that would enter the mine mass. Cloud appearance
  follows the ordinary sun and ambient environment; it has no cycle reference.
- `RetroFog` requires the already-created player camera and `DayNightCycle` so
  it can attach its fullscreen pass and read normalized daylight strength.
- `AtmosphericMist` requires the same camera and cycle, and is created after
  RetroFog so its higher-priority pass blends over the distance tint.
- UI reads `day_night_cycle.get_phase_name()`.
- Player signals are connected before UI creation, but user input cannot occur
  until the frame is running. Time signal handlers still null-check labels
  because the cycle is initialized before the UI exists.

Do not reorder these calls without checking every dependency.

## 3. Approximate runtime tree

Node names for code-created instances are engine defaults, but ownership is
approximately:

```text
Main (Node3D, main.gd)
├── WorldEnvironment
├── Sun DirectionalLight3D                shadowed outdoor primary, 240 m
├── EntranceFill OmniLight3D              shadowless local opening fill
├── DayNightCycle                         day_night_cycle.gd
├── CloudLayers                           cloud_layers.gd exterior presentation
│   ├── LowerCloudDeck Node3D
│   │   └── LowerWind00..05 Node3D        six independent +X drift bands
│   │       └── MultiMeshInstance3D       weighted 75–350 clouds; 1,200 total
│   └── UpperCloudScatter Node3D
│       └── UpperWind00..05 Node3D        six independent -X drift bands
│           └── MultiMeshInstance3D       weighted 50–175 clouds; 600 total
├── RetroFog                              retro_fog.gd controller/material owner
├── many StaticBody3D                     unbreakable outdoor landing
├── BlockVolume                           block_volume.gd
│   ├── nearby exposed MineableBlock       interactive 14-cell tier
│   │   ├── MeshInstance3D                textured base cube
│   │   ├── MeshInstance3D                cumulative crack overlay
│   │   └── CollisionShape3D              2-unit BoxShape3D
│   └── FarChunk_* Node3D                  28-cell visual tier
│       └── up to 3 MultiMeshInstance3D   stone/coal/copper faces, no collision
├── MinerPlayer                           player.gd
│   ├── CollisionShape3D                  capsule
│   └── Camera3D
│       ├── Node3D                        HammerArm camera-space swing
│       │   └── HeldProp                  field hammer GLB, fixed facing
│       ├── HeldProp                      field tablet GLB
│       ├── HeldProp                      dynamite GLB + fuse spark
│       ├── Node3D                        held torch + half-energy light
│       ├── Node3D                        empty-hand placeholder
│       └── MeshInstance3D                RetroFogPass fullscreen QuadMesh
├── zero or more ThrownDynamite           thrown_dynamite.gd
│   ├── FieldDynamite GLB
│   ├── CollisionShape3D                  layer 2 sphere
│   └── OmniLight3D                       tiny fuse spark
├── zero or more PlacedTorch              placed_torch.gd
│   ├── MeshInstance3D                    shaft
│   ├── MeshInstance3D                    emissive flame
│   ├── CollisionShape3D                  layer 2 pick target
│   └── OmniLight3D                       flickering practical
├── AtmosphericMist                       atmospheric_mist.gd
│   └── CanvasLayer (layer -1)
│       └── ColorRect                     AtmosphericMistPass
└── CanvasLayer                           all HUD/modal UI
    ├── pack occupancy/time/tool labels
    ├── ADMIN badge
    ├── crosshair and help text
    ├── reward/status popup
    ├── four-slot Field Rig
    ├── hidden Field Pack overlay
    │   ├── centered transparent inventory-panel TextureRect
    │   └── ten transparent InventorySlot controls aligned to its painted bays
    ├── admin block PopupMenu             stone/coal/copper setter
    └── hidden Time Test / Admin overlay
```

## 4. State ownership

State should be changed by its owner. Other objects send requests or subscribe
to signals.

| State/resource | Owner | Readers/mutators |
|----------------|-------|------------------|
| Inventory slot contents | `main.gd` | Filled by breaks; cleared by discard/exhaustion; rendered by HUD/pack |
| Torch count | `main.gd` | Placement/discard handlers mutate it; HUD/pack mirror it |
| Block/tool materials and inventory icon textures | `main.gd` | Passed into volume/player/torches or rendered in Field Pack/Field Rig |
| Field Pack frame texture | `main.gd` | Centered modal presentation; slot controls remain the interaction layer |
| Voxel map (filled cells) | `BlockVolume` | Main asks it to remove, paint, save, reset |
| Near block bodies / far batched visuals | `BlockVolume` | Promotes/demotes 8-cell chunks; emits `block_spawned` for near bodies |
| Map dirty / disk file | `BlockVolume` | Save Map and exit-if-dirty write `user://sculpted_volume.bin` |
| Admin Mode flag | `main.gd` | Copied onto `MinerPlayer.admin_mode`; HUD badge mirrors it |
| Selected Field Rig slot | `MinerPlayer` | Main resolves its shared inventory cell and updates the equipped item |
| Inventory open state | `MinerPlayer` | Main shows/hides Field Pack |
| Cheat/Admin menu open | `MinerPlayer` | Main shows/hides Time Test / Admin panel |
| Mouse capture | `MinerPlayer` | Updated with modal state/input |
| Player transform/velocity/ledge-climb state | `MinerPlayer` | Character physics loop and deliberate committed climb action |
| Block health/type/pending break | Each `MineableBlock` | Player calls `hit`; main accepts/rejects final break |
| Block visual damage state | Each `MineableBlock` | Internal shader parameters and per-texture body/vein pigments |
| Cycle clock/current phase/daylight strength | `DayNightCycle` | Main reads name/calls test setter; `RetroFog` and `AtmosphericMist` read smooth strength |
| Environment/sun values | `DayNightCycle` after setup | Interpolated every frame; Environment fog remains disabled |
| Cloud meshes/layout/wind/fixed tints | `CloudLayers` | Builds twelve deterministic exterior MultiMeshes; receives the `BlockVolume` visual AABB; ordinary renderer lighting supplies time response |
| Retro fog pass/material/uniform state | `RetroFog` | Creates a camera-child 3D pass; reads `DayNightCycle.get_daylight_strength()`; intensity tune can be overridden from the Y FOG tab |
| Atmospheric mist pass/material/uniform state | `AtmosphericMist` | Creates a CanvasLayer ColorRect after 3D; uploads camera matrices each frame; reads daylight strength; live tune from the Y FOG tab |
| Fog slider save file | `main.gd` | Reads/writes `user://fog_settings.cfg` on load / SAVE FOG |
| Held torch light/flicker | `MinerPlayer` | Active only when a torch item is selected |
| Placed torch light/flicker | Each `PlacedTorch` | Internal process loop |

Important: `MinerPlayer` does not own or decrement inventory. Main passes it the
item ID from the selected shared slot; the player only routes that item's use
and reports a valid torch placement ray. This prevents the input object from
creating free items.

## 5. Signals and public method boundaries

### Player signals

| Signal | Payload | Consumer | Meaning |
|--------|---------|----------|---------|
| `selected_slot_changed` | `slot: int` | `main.gd` | Refresh Field Rig/tool/help labels |
| `inventory_toggled` | `is_open: bool` | `main.gd` | Show/hide Field Pack and crosshair |
| `cheat_menu_toggled` | `is_open: bool` | `main.gd` | Show/hide Time Test / Admin UI |
| `torch_placement_requested` | position, normal | `main.gd` | Attempt a count-authorized placement |
| `dynamite_throw_requested` | origin, velocity, fuse | `main.gd` | Spawn a thrown stick and consume the cell |
| `dynamite_spent_requested` | none | `main.gd` | Fuse burned out in hand; consume the cell |
| `status_message_requested` | text | `main.gd` | Show a short HUD popup |
| `dynamite_state_changed` | none | `main.gd` | Refresh LIT / charge hint |
| `admin_break_requested` | block reference | `main.gd` | Admin one-hit delete, no inventory |
| `admin_paint_menu_requested` | block reference | `main.gd` | Open Stone/Coal/Copper setter |

### Volume and block signals

| Signal | Payload | Consumer | Meaning |
|--------|---------|----------|---------|
| `BlockVolume.block_spawned` | block reference | `main.gd` | New surface block; main connects `break_requested` |
| `MineableBlock.break_requested` | block reference | `main.gd` | Play-mode final hit asks inventory to accept |

### Cycle signal

| Signal | Payload | Consumer | Meaning |
|--------|---------|----------|---------|
| `DayNightCycle.phase_changed` | enum integer, name | `main.gd` | Phase boundary crossed or test phase set |

### Setup methods

- `BlockVolume.setup(stone, coal, copper, cracks)` loads or fills the cube,
  creates near bodies, and batches distant exposed faces by chunk/material.
- `MineableBlock.setup(type, block_material, crack_textures)` injects content
  and builds child nodes. `apply_type()` repaints an existing node.
- `MinerPlayer.setup(wood_material, metal_material)` builds collision, camera,
  hammer, tablet, dynamite (plus fuse spark), held torch, and empty-hand
  placeholder.
- `ThrownDynamite.setup(origin, velocity, fuse_left, block_volume)` places a
  gravity-arc stick. Main owns spawn and inventory consume.
- `PlacedTorch.setup(surface_position, surface_normal, wood_material)` positions
  and builds the placed practical light.
- `DayNightCycle.setup(environment, sun, entrance_fill)` gives it the Environment,
  directional sun, and local entrance OmniLight it continuously controls.
  Ambient stays a dim floor; Day brightness is the shadowed sun. Engine fog
  stays disabled. The fill is shadowless and range-limited; it is
  not a player-placeable practical light.
- `DayNightCycle.get_daylight_strength()` exposes the normalized smoothstep
  daylight scalar for presentation systems without transferring clock ownership.
- `CloudLayers.setup(block_volume.get_visual_aabb())` builds both deterministic
  world-anchored fields and supplies the exact mine bounds to their shared lit
  shader. It does not read the day/night clock.
- `RetroFog.setup(player.camera, day_night_cycle)` plus `set_mine_bounds`
  creates one fullscreen QuadMesh pass under the camera, loads
  `shaders/retro_fog.gdshader`, and applies daylight strength. Surfaces inset
  in the mine AABB use a darker cave haze; outdoor fog stays on the Day/Night
  path.
- `AtmosphericMist.setup(player.camera, day_night_cycle)` creates a
  `CanvasLayer` at layer -1 with a fullscreen ColorRect, loads
  `shaders/atmospheric_mist.gdshader`, uploads camera matrices every frame,
  and applies the same daylight strength to density, color, and speckle
  brightness.

These objects are instantiated with `.new()` and added/configured by `main.gd`.
Most are configured before insertion. `PlacedTorch` is added before setup
because it sets `global_position`; `RetroFog` and `AtmosphericMist` are likewise
added under `Main` before setup constructs the live passes under the camera.

## 6. Interaction flows

### Dynamite throw flow

```text
right click, dynamite selected
→ light fuse once, 6 s remaining, spark on the tip

hold left click while lit
→ charge 0–5 s, stick eases to the shoulder wind-up
→ release
→ player emits origin, velocity (3.6 + 0.42 × 5 × seconds), fuse left
→ main.gd spawns ThrownDynamite and clears the inventory cell
→ held model hides (empty hand if that slot is selected)

fuse reaches zero in hand
→ emit dynamite_spent_requested; main clears the cell; no blast yet
```

### Mining flow

```text
left mouse event, play mode, hammer selected
→ 0.05 s input cap check
→ ray from 0.55 past the camera to 6 units, excluding player
→ only MineableBlock collider accepted
→ block.hit(1)
→ health decreases and hit-scale response begins
→ if health remains: choose rounded crack state and start visual blend
→ on the final hit: keep one health and emit break_requested(block)
→ main.gd stores the block type in the first empty Field Pack cell
→ accepted: block frees; BlockVolume.remove_voxel() reveals neighbors
→ full pack: block remains at one health and shows FIELD PACK FULL
```

### One-block ledge-climb flow

```text
Space pressed while grounded and moving toward a ledge
→ keep the regular 5.2 upward jump velocity and arm one climb opportunity
→ require that original Space press to remain held through the 0.08 s airborne
  lead-in and the probe within the 0.28 s opportunity window
→ released before catch: permanently discard the opportunity for this jump;
  pressing Space again in midair cannot re-arm it
→ require a `StaticBody3D` wall within 1.15 units and a top 1.55–2.20 units
  above takeoff; explicitly reject `PlacedTorch`
→ center and two side rays confirm a broad, level support surface
→ the real player capsule must fit at hang, lift, and landing positions
→ accepted: commit a 0.76 s grab through normalized 0.28, brace through 0.42,
  vertical pull through 0.82, and final inward settle/vault; Space may release
→ add a 0.06 m body reach arc and 0.025 m brace sag
→ camera adds a 0.14 m dip, 0.085 m forward lean, 0.018 m lateral bob, two
  0.028 m vertical effort tugs, and up to 1.1° roll
→ restore the exact camera rest position and zero roll, zero velocity, and
  floor-snap
```

Normal movement, look, slot, and item input are suppressed once the catch begins
so the staged motion remains committed; releasing Space does not cancel it.
Collision during the motion aborts safely and restores the camera position and
roll. E or Y cancels the climb, restores the camera, clears the assisted motion,
and opens the requested modal. Tapped or released jumps, unsafe corners, blocked
tops, and two-block walls stay on normal character physics. Placed torches are
on collision layer 2 and never qualify as ledges.

### Admin sculpt flow

```text
Y → ENTER ADMIN
→ main.gd.admin_mode and MinerPlayer.admin_mode become true
→ HUD shows ADMIN badge; help text switches to delete/set-block

left click
→ emit admin_break_requested
→ main frees the node and BlockVolume.remove_voxel()
→ no Field Pack change; map marked dirty

right click
→ emit admin_paint_menu_requested
→ mouse released; PopupMenu Stone / Coal / Copper
→ set_voxel_type() updates data + live material/health
→ menu close recaptures the mouse

SAVE MAP
→ BlockVolume.save_to_disk() writes user://sculpted_volume.bin
```

Visual transitions never gate `hit()`. If a new hit arrives during a blend, the
block resolves its current target and immediately starts blending to the next
cumulative target.

### Torch placement flow

```text
right mouse event
→ selected_item_id == "torch"
→ 0.05 s input cap check
→ ray to 6 units
→ supporting StaticBody3D accepted; PlacedTorch explicitly rejected
→ player emits placement position + surface normal
→ main.gd checks torch_count
→ if zero: show NO TORCHES
→ otherwise: create PlacedTorch, setup, decrement, refresh both UIs
```

### Torch removal flow

```text
left mouse event with any selected cell
→ ray to 6 units
→ if collider is PlacedTorch: call break_apart()
→ queue-free the placed torch without changing torch_count or inventory
```

Placed torches use collision layer 2 so interaction rays can hit them. The
player's default layer-1 collision mask ignores them, preventing movement snags.

### Modal UI flow

E and Y are mutually exclusive:

```text
open one menu
→ close/emit false for the other if necessary
→ cancel an active ledge climb and restore its camera offset
→ set local modal boolean
→ mouse becomes visible
→ signal main.gd to show correct panel
→ physics loop uses zero movement input
→ item-use/mouse-look input returns early
```

Closing the active menu recaptures the mouse. Escape closes a menu first; if no
menu is open it merely releases the mouse.

### Inventory discard flow

```text
right click an occupied Field Pack cell
→ main.gd records that cell and opens its PopupMenu at the pointer
→ choose THROW ITEM AWAY
→ clear the cell; if it held torches, also set torch_count to zero
→ refresh Field Pack occupancy, cell labels, and the Field Rig torch count
```

Placing the final torch follows the same cell-clearing rule automatically. Since
Field Rig slots 1–4 are views of inventory cells 1–4, clearing cell 2 also makes
quick slot 2 empty and unequips the held torch when that slot is selected.

### Inventory move flow

```text
drag an occupied InventorySlot
→ InventorySlot returns source metadata and a floating item preview
→ main.gd highlights the source while Godot tracks the drag
→ drop on another InventorySlot
→ target emits source/target indices to main.gd
→ main.gd swaps the two cell strings (an empty target is a move)
→ refresh all pack cells, occupancy, Field Rig slots, and selected held item
```

Dropping outside a valid cell cancels without changing inventory contents.

### Time flow

```text
DayNightCycle._process(delta)
→ advance cycle_time modulo 420
→ determine phase and normalized daylight scalar
→ smoothstep daylight
→ publish daylight_strength
→ interpolate illumination, purple ambient/background, primary sun, and the
  localized green-to-amber entrance fill
→ on phase change emit name for HUD/menu

CloudLayers._process(delta)
→ advance six positive-X and six negative-X wind offsets independently
→ wrap each batch across the 360-unit period; its deterministic base scatter is
  copied across a seamless 5×5 X/Z tile field

RetroFog._process(delta)
→ read DayNightCycle.get_daylight_strength()
→ apply the approved fog-only ease-out to begin/end/curve/color/retro mix
→ apply a separate symmetric transition bell to intensity, peaking at 0.96
→ one camera-child pass reconstructs linear depth, quantizes it through 16 bands
  with static 4×4 Bayer dither, and blends the scene toward one fog color

AtmosphericMist._process(delta)
→ read the same daylight strength
→ apply the same ease-out to Night/Day color and density multipliers
→ apply a transition boost so Dusk/Twilight are the densest mist
→ a CanvasLayer ColorRect after 3D reconstructs world position from depth,
  evaluates three scrolling noise layers, and alpha-blends mist plus speckles
```

Time keeps advancing while Field Pack or Time Test is open because neither
menu pauses the scene tree.

## 7. Dependencies between scripts

```text
main.gd
├── creates MinerPlayer
├── creates BlockVolume
├── connects BlockVolume.block_spawned → MineableBlock.break_requested
├── creates InventorySlot controls
├── creates PlacedTorch
├── creates DayNightCycle
├── creates CloudLayers after BlockVolume exists and supplies its visual AABB
├── creates RetroFog after player and cycle exist
└── creates AtmosphericMist after RetroFog so its pass can blend over it

BlockVolume
├── owns PackedByteArray voxel data
├── creates/frees nearby exposed MineableBlock children
├── batches distant exposed faces into per-material MultiMeshes
├── queues chunk transitions within a per-frame work budget
└── writes/reads user://sculpted_volume.bin

player.gd
├── instantiates HeldProp for hammer, tablet, and dynamite
├── emits dynamite throw/spent requests; does not spawn or free inventory
└── type-checks ray colliders (MineableBlock, PlacedTorch, StaticBody3D)

held_prop.gd
└── instances a field-tool GLB; no gameplay-script dependency

inventory_slot.gd
└── emits drag source/target indices; does not mutate inventory state

mineable_block.gd
└── no gameplay-script dependency

placed_torch.gd
└── no gameplay-script dependency

day_night_cycle.gd
└── no gameplay-script dependency

cloud_layers.gd
├── owns twelve opaque, non-colliding exterior MultiMesh wind batches
├── receives BlockVolume's visual AABB for exact shader-side exclusion
├── loads shaders/clouds.gdshader for lit depth-writing presentation
└── relies on the shared renderer sun and ambient environment for lighting

retro_fog.gd
├── attaches one QuadMesh pass to the MinerPlayer camera
├── reads DayNightCycle's smoothed daylight strength
└── loads shaders/retro_fog.gdshader for screen/depth reconstruction

atmospheric_mist.gd
├── attaches a CanvasLayer ColorRect after all 3D
├── uploads camera inv-projection / inv-view each frame
├── reads DayNightCycle's smoothed daylight strength
└── loads shaders/atmospheric_mist.gdshader for depth-aware layered mist
```

Who talks to whom for the map:

```text
Player look/click
        │
        ▼
 MinerPlayer  --signals-->  main.gd  --methods-->  BlockVolume
   (input)                  (policy:                 (data)
                            play vs admin,
                            inventory,
                            save UI)
                                  │
                                  ▼
                            MineableBlock
                            (one exposed cell:
                             health, cracks, mesh)
```

This dependency direction keeps content nodes independent and leaves
`main.gd` as the intentional integration point.

## 8. Scene/resource strategy going forward

Code creation is appropriate at current scale, but use these thresholds:

- Convert the player to a `.tscn` when models, audio nodes, animation trees, or
  many equipment sockets make procedural construction awkward.
- Convert torches to a scene when they gain textures, particles, audio, pickup,
  support tracking, or multiple torch variants.
- Introduce custom `Resource` definitions when at least several tools/blocks
  share the same data fields and branches become error-prone.
- The 80×320×80 cube stores interiors as data and already batches its distant
  visible tier with `MultiMesh`. Before increasing the interactive radius or
  mine dimensions again, generate near collision/meshes per chunk rather than
  returning to one body per distant exposed face.
- Introduce an autoload only when persistent cross-scene state actually exists
  (for example save data used by a title scene, mine scene, and shop scene).

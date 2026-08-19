# Low Poly Miner

Low Poly Miner is a small Godot 4 first-person mining prototype and the
foundation for a future incremental/exponential game. The current build focuses
on the feel and technical foundations of mining: movement with contextual
one-block ledge climbing, a sculptable stone
volume, cumulative block damage, Field Pack rewards, darkness, placeable
torches, inventory/quick-slot UI, a testable day/night cycle with texture-free,
PS2-inspired green–purple distance fog, a second layer of drifting mist and
sparse green speckles, exterior low-poly cloud strata above
and below the landing, and an Admin Mode for carving and painting the cave map.

The project deliberately does **not** yet contain shops, tool upgrades,
automation, full game save/load, or the exponential economy. The cave volume
is the only persisted data. Progression systems should wait until the mining
loop feels right.

## Requirements and startup

- Godot **4.7.1** is the version currently used for development and validation.
- Rendering method: `gl_compatibility`.
- Main scene: `res://main.tscn`.
- Design viewport: 1920×1080.
- Launch mode: fullscreen, so editor play opens at the native display size
  instead of scaling into Godot's smaller embedded Game panel.
- No third-party addons or runtime dependencies.

On this development machine, the validated Godot executable is:

```text
C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe
```

Open `project.godot` in Godot and press **F6** or **F5**. The game starts at the
outdoor landing facing a huge stone mass, during the Night phase.

## Controls

| Input | Action |
|-------|--------|
| Mouse | Look |
| WASD | Move |
| Tap Space | Perform the ordinary jump |
| Hold Space continuously while jumping toward a clear one-block ledge | Grab, brace, pull, and vault onto it |
| Left click with hammer (play mode) | Mine the aimed cave block |
| Left click (admin mode) | Delete the aimed cave block in one hit |
| Right click a cave block (admin mode) | Open Stone / Coal / Copper setter |
| Right click with a torch equipped (play mode) | Place a torch on the targeted surface |
| Right click with dynamite equipped | Light the fuse (6 s) |
| Hold left click with a lit dynamite, then release | Throw it; longer hold (up to 5 s) adds 5 strength per second |
| Left click a placed torch (play mode) | Break it without recovering the torch |
| 1–4 | Select a vertical Field Rig slot |
| E | Toggle the ten-cell Field Pack inventory |
| Drag an item between Field Pack cells | Move it or swap with the target item |
| Right click an occupied Field Pack cell | Open `THROW ITEM AWAY` action |
| Y | Toggle Time Test / Admin menu |
| Escape | Close an open menu, otherwise release the mouse |

Field Rig slots 1–4 are the same cells as Field Pack cells 1–4. They start with
the field hammer in cell 1, the ten-torch stack in cell 2, the field tablet in
cell 3, and dynamite in cell 4.
Discarding or exhausting an item in those cells also empties its Field Rig slot.
Inside the Field Pack, drag an item onto another cell. An empty target receives
the item; an occupied target swaps places with it. Selecting an empty Field Rig
cell displays a simple hand placeholder. Mined Stone, Coal, and Copper use
matching transparent low-poly rubble icons in both inventory views and are
named without a `BLOCK` suffix. The Field Pack itself uses the centered,
transparent industrial panel under `assets/ui/`; there is no opaque fullscreen
inventory backdrop.

## Current gameplay

- The mine is an 80×320×80 stone cube (about 2 million voxels). Interactive
  blocks stay within 14 cells while lightweight chunk visuals extend the visible
  region to 28 cells (56 world units) and retire beyond 36 cells.
- Streaming work is spread across frames; the current startup measurement is
  1,322 interactive blocks plus 2,656 batched distant faces.
- Play mode: stone takes 10 hits, coal 20, copper 15. Each broken block fills
  one Field Pack cell and does not stack.
- A full pack blocks the final hit until a cell is free.
- Admin mode (Y → ENTER ADMIN): one-hit delete, right-click block type menu,
  Save Map, Reset Stone Cube. Admin deletes do not use inventory.
- Save Map writes `user://sculpted_volume.bin`. Unsaved edits also flush on exit.
- Outdoor landing blocks are solid and unbreakable.
- A normal jump keeps its 5.2 upward velocity. A ledge climb requires one
  uninterrupted Space hold from grounded takeoff through the 0.08-second
  lead-in and probe. Releasing Space leaves that entire jump ordinary; pressing
  it again in midair cannot re-arm the climb.
- A caught ledge commits a deliberate 0.76-second grab, brace, pull, and vault
  with body effort and camera dip, lean, bob, tugs, and roll. Releasing Space
  after the catch does not cancel it. Two-block walls, narrow corners, and
  blocked tops remain unclimbable; E or Y still cancels safely.
- Torches are untextured low-poly placeholders with wide, warm, flickering
  shadowed light. An equipped torch lights the player at half placed energy.
- The seven-minute cycle is Day 3/7, Dusk 1/7, Night 2/7, Twilight 1/7.
- A broad, randomly scattered faceted cloud deck sits below the landing while
  sparse low-poly islands cross above it. Six whole-cloud silhouettes, a wide size/altitude
  range, randomized X/Z scatter, and twelve independent wind speeds keep the
  field varied. The opaque geometry is world-anchored, texture-free,
  non-colliding, shadowless, lit by the same sun and ambient environment as the
  world, and depth-fogged.
- Day applies a texture-free PS2-inspired depth pass: nearby textures remain
  crisp while distance collapses through 16 ordered-dithered bands toward moss
  green. It uses one screen/depth fullscreen pass—no bitmap smoke, particles, or
  local haze cards—and retains the purple ambient/background countertones.
- Night moves the fog trace much farther out and reduces maximum intensity from
  0.88 to 0.08 with a near-black violet target. Dusk and Twilight retain the
  same symmetric range/color response but add a transition-only intensity bell,
  peaking at 0.96 at either midpoint so the streamed-world horizon stays hidden
  without changing the Day or Night endpoints.

## Documentation index

Future contributors and AI agents should read these documents before changing
systems:

- [`AGENTS.md`](AGENTS.md) — invariants, workflow, and definition of done for
  future AI/code agents.
- [`docs/PROJECT_GUIDE.md`](docs/PROJECT_GUIDE.md) — product intent, current
  status, world layout, and feature overview.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — runtime tree, ownership,
  signals, initialization order, and interaction flows.
- [`docs/SYSTEMS_REFERENCE.md`](docs/SYSTEMS_REFERENCE.md) — exact mechanics,
  equations, constants, materials, lighting values, UI, and asset reference.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — validation, manual smoke tests,
  extension recipes, limitations, and roadmap.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — established design/engineering
  decisions and their rationale.

## Automated validation

From PowerShell, using the installed console build:

```powershell
$godot = 'C:\Users\myawe\OneDrive\Desktop\slop\mygame\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = 'C:\Users\myawe\Documents\Codex\2026-08-16\i-w\outputs\LowPolyMiner'
& $godot --headless --editor --path $project --quit
& $godot --headless --path $project --quit-after 10
```

Both commands must complete without `SCRIPT ERROR`, shader errors, or runtime
errors. They do not replace the manual visual/gameplay checklist in
`docs/DEVELOPMENT.md`.

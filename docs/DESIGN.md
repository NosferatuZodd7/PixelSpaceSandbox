# Design

The technical design of PixelSpaceSandbox: how the game is built and why.
The product brief, with the pillars, features and milestones, is in
[BRIEF.md](BRIEF.md); progress is in [STATUS.md](STATUS.md). This document
grows milestone by milestone.

## Pillars

1. Gravity, light and time that feel real.
2. Living worlds that react.
3. Cause and effect you can see and understand.
4. Runs well on weak PCs, and still feels polished and immersive.
5. Pixel-art charm in every screen.

When two options compete, the one that serves these better wins.

## Technology

| Decision | Why |
| --- | --- |
| Godot 4.7.2 (latest stable), typed GDScript | Free, light, exports to Windows and Linux; typed GDScript catches mistakes early and runs faster |
| Compatibility renderer (OpenGL 3.3), ANGLE fallback on Windows | Runs on Intel HD 4000-class GPUs; ANGLE (OpenGL over Direct3D) rescues machines with broken OpenGL drivers |
| No compute shaders; simulation on the CPU with `WorkerThreadPool` and `Packed*Array` | Compatibility has no compute; packed arrays are compact and fast to loop over |
| A C++ GDExtension only for the gravity/particle core, and only if the milestone 2 benchmark shows GDScript cannot meet the budget | Keeps the project simple until there is evidence |

### Typed code

`debug/gdscript/warnings/untyped_declaration` is set to **error**: every
variable, parameter, return value and loop variable has a type (or is
inferred with `:=`). The test `test_scripts_compile` loads every script, so a
missing type fails the test run even in code nothing uses yet.

## Pixel-perfect output

- Internal resolution **640×360**, stretch mode `viewport`, aspect `keep`,
  **integer** scaling: the game renders at 640×360 and is enlarged by a whole
  factor (2× in the default 1280×720 window, 3× at 1920×1080), with black
  bars when the screen is not an exact multiple.
- Nearest-neighbour texture filtering everywhere, and 2D transforms and
  vertices snapped to whole pixels, so sprites never jitter between pixels.
- The interface is drawn at the same 640×360 as the game. A UI scale setting
  comes with the settings screen (milestone 9).

### Fonts

Pixel fonts are only sharp at the size their design grid was drawn for:

| Font | Native size | Use |
| --- | --- | --- |
| Micro 5 | 11 px (line height 11, capitals 5 px) | Interface text |
| Press Start 2P | 8 px, or multiples (16, 24…) | Titles, the big time counter |

Both import with antialiasing, hinting and subpixel positioning off. Micro 5
was chosen over Tiny5 because its Portuguese accents (ã, õ, ç) stay readable
at 5 px capitals.

### Colours

All colours come from one palette, `data/palette.json` (56 colours plus
semantic aliases such as `ui_text`). Code asks for them by name with
`Palette.color(&"nebula_3")`. A test fails if any script under `src/` writes
a colour value directly, or names a colour the palette does not have.

Gradients and soft shapes are drawn with **ordered dithering** (4×4 Bayer
matrix) between neighbouring palette colours, never with blended in-between
colours.

## Code layout and layers

```
src/core/   palette, input bindings, the App autoload
src/sim/    simulation: plain data + systems (from milestone 1)
src/view/   presentation: nodes that draw the simulation
src/ui/     screens, panels, theme
data/       content in data files (JSON or Godot resources)
```

Rules:

- **The simulation never depends on the presentation.** Code in `src/sim/`
  does not use nodes, scenes, the palette or the renderer, so it can be run
  and tested headless and stepped on worker threads.
- The presentation reads the simulation state and draws it; it changes the
  simulation only through explicit commands (god powers), which is also what
  undo and snapshots record.
- Content (presets, species, biomes, the tree of knowledge, god powers…)
  lives in `data/`, not in code. Parsers validate data and return a list of
  errors instead of crashing, so mods can be checked later.

## Determinism

The same seed and settings must give the same system, the same planet and
the same future. Rules from day one:

- Every random choice uses an explicitly seeded `RandomNumberGenerator`
  (seed derived from the system seed and the object's id), never the global
  `randi()`/`randf()`.
- Work split across threads is combined in a fixed order (floating-point
  sums depend on order).
- Saves store seeds, settings, the player's changes and the simulation
  state, not the generated details.

The sky backdrop already follows these rules (`SkyGenerator`, tested).

## Units and precision (from milestone 1)

- Astronomical units, solar masses and years; `G = 4π² AU³/(M☉·yr²)`;
  `c = 63,241.077 AU/yr`.
- Godot's `Vector2` is **32-bit**. GDScript `float` is 64-bit, so simulation
  positions and velocities are stored as 64-bit floats in
  `PackedFloat64Array`s, never in `Vector2`. Drawing converts them to
  camera-relative 32-bit positions (floating origin around the camera).

## Testing

- `tools/run_tests.sh` (or `tools/run_tests.ps1` on Windows) imports the
  project, runs every test headless, runs the game for 300 frames, and fails
  if a test fails **or Godot prints any error or warning**.
- Tests live in `tests/unit/` and `tests/smoke/`, named `test_*.gd`, and
  extend `TestCase` (`tests/framework/base_test_case.gd`). A small runner of
  our own (`tests/run_tests.gd`) replaces a third-party test framework: it is
  about 100 lines and has no dependencies.
- `tools/screenshot.gd` renders a scene to a PNG for reviews and docs.

## Performance budget

- Minimum PC: dual-core CPU, 4 GB RAM, Intel HD 4000-class GPU.
- 60 FPS at default settings on it; no frame may stall while a simulation
  step runs. Heavy work (the sky today; physics and planets later) runs on
  worker threads and is picked up when it is ready.
- Measured: a 640×360 sky takes about 0.4 s on a worker thread (editor
  build, 4-core cloud machine). When the camera starts to pan and zoom
  (milestone 1) the backdrop becomes a parallax layer generated once per
  system, not per frame.

## Decisions log

| # | Decision | Date |
| --- | --- | --- |
| 1 | Godot 4.7.2 stable, Compatibility renderer, ANGLE fallback on Windows | 2026-10 |
| 2 | Micro 5 (11 px) for interface text, Press Start 2P (8 px multiples) for titles | 2026-10 |
| 3 | Own minimal headless test runner instead of a third-party framework | 2026-10 |
| 4 | Interface text in a CSV (`locale/ui.csv`), English and Portuguese (Portugal) | 2026-10 |
| 5 | Default key bindings in `data/input_bindings.json`; rebinding stores only overrides | 2026-10 |
| 6 | Simulation state in 64-bit packed arrays, not `Vector2` | 2026-10 |

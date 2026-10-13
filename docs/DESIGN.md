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
src/core/   palette, input bindings, player settings, the App autoload
src/sim/    simulation: plain data + systems (bodies, orbits, clock, fronts)
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

## Units and precision

- Astronomical units, solar masses and years; `G = 4π² AU³/(M☉·yr²)`;
  `c = 63,241.077 AU/yr` (`src/sim/units.gd`).
- Godot's `Vector2` is **32-bit**. GDScript `float` is 64-bit, so simulation
  positions and velocities are stored as 64-bit floats in
  `PackedFloat64Array`s, never in `Vector2`. Drawing converts them to
  camera-relative 32-bit positions (floating origin around the camera), so
  the view is exact from a star's surface to the edge of the system.

## The cosmic layer (milestone 1)

### State

A `StarSystem` holds its `CelestialBody`s (star, planet, dwarf planet, moon:
mass, radius, luminosity, albedo, rotation, pole, look, rings, orbit) and
two packed arrays: positions and velocities, three 64-bit numbers per body,
in the J2000 ecliptic frame centred on the star. Bodies are stored parents
first. The screen only reads this state.

### Motion "on rails"

In milestone 1 every body follows a fixed orbit (`OrbitModel`), so positions
are a pure function of time: exact at any speed and deterministic.

- **Planets, Pluto:** `KeplerOrbit` with JPL's "Approximate Positions of the
  Planets" elements and their drift per century (Table 1, fitted to
  1800–2050). Drifts are frozen beyond ±50 centuries so orbits stay valid
  for billions of years; the bodies keep moving.
- **Ceres, Eris:** classical elements from JPL's small-body database.
- **The Moon:** `LunarOrbit`, the Astronomical Almanac's low-precision lunar
  theory (about 0.3°), so its phase is real on any date.
- **Other moons:** real sizes, periods, eccentricities and inclinations,
  in their planet's equatorial plane (from the IAU pole), so Uranus's moons
  circle upright. Their place along the orbit is approximate (no ephemeris
  was reachable from the build environment); the inspect window says so.
- **Earth–Moon and Pluto–Charon:** the orbit is the pair's centre of mass;
  each body is placed around it by mass.

The game starts on the real current date. Tests check the result against
the sky: Mars, Jupiter and Saturn oppositions within 0.15°, the total lunar
eclipse of 2025-09-07 (Moon 179.6° from the Sun) and the total solar eclipse
of 2024-04-08 (0.4°).

Milestone 2 replaces rails with n-body gravity behind the same
`Simulation.advance()`; bodies far from any disturbance may stay on rails.

### Time

One `SimClock` in years since J2000.0. Its speeds come from
`data/time_speeds.json`: from ×0.01 through real time to a billion years per
second; + and − step, the number keys jump to presets, Space pauses.

### Light and gravity fronts

`WaveFront` is in place (light or gravity, origin, emission time, speed c)
with the arrival rule — a body feels a change once the front's radius passes
its distance from the origin — and is tested: arrival after d/c within one
sub-step, and a front is dropped once it has passed every body. Milestone 2
creates fronts when the player changes the system:

- light: each body keeps the light of the latest front that reached it;
- gravity: in steady motion bodies pull towards where the others are now
  (never towards delayed positions); changes travel as fronts; a removed
  body leaves a gravity ghost on its last path until the news arrives.

### Drawing

- `SpaceCamera`: centre and pixels per AU, zoom towards the cursor with
  easing, from 0.5 to 2×10⁷ px/AU.
- Bodies are drawn larger than life (shrinking when zoomed out so they do
  not crowd); **T** shows true scale. A moon appears once it is clear of its
  planet's disc.
- `BodySprite`: one shader (`planet_disc.gdshader`) wraps a small surface map
  on a sphere, spins it, and lights it from the star with a dithered
  terminator. Maps come from `data/body_looks.json` (styles and palette
  colours) until milestone 5 brings real planet maps. Stars get a dithered
  glow; rings are dithered ellipses in the planet's equator plane, the far
  half behind the disc.
- Orbits are dashed lines with fixed on-screen dashes; only the parts near
  the screen are cut into dashes. Past 2,500 px of radius an orbit is drawn as
  an exact arc around its body instead, so the line passes through it at any
  zoom.
- Names never cover bodies, each other, the counter or the toolbar.
- The habitable zone is a dithered green band (`dither_ring.gdshader`) whose
  fill fades out when it is much wider than the screen.
- The star backdrop does not move when panning: real background stars are
  so far away that crossing a whole system does not shift them.

## Testing

- `tools/run_tests.sh` (or `tools/run_tests.ps1` on Windows) imports the
  project, runs every test headless, runs the game for 300 frames, and fails
  if a test fails **or Godot prints any error or warning**.
- Tests live in `tests/unit/` and `tests/smoke/`, named `test_*.gd`, and
  extend `TestCase` (`tests/framework/base_test_case.gd`). A small runner of
  our own (`tests/run_tests.gd`) replaces a third-party test framework: it is
  about 100 lines and has no dependencies.
- `tools/screenshot.gd` renders a scene to a PNG for reviews and docs; for
  the game screen it can set the date, select, follow, zoom and open the menu.
- `tests/unit/test_architecture.gd` fails if anything under `src/sim/` uses
  nodes, the palette, input or the renderer.

## Performance budget

- Minimum PC: dual-core CPU, 4 GB RAM, Intel HD 4000-class GPU.
- 60 FPS at default settings on it; no frame may stall while a simulation
  step runs. Heavy work (the sky today; physics and planets later) runs on
  worker threads and is picked up when it is ready.
- Measured (editor build, 4-core cloud machine):
  - a 640×360 sky takes about 0.4 s on a worker thread;
  - the game screen costs 2–5 ms of CPU per frame at every zoom and speed
    (simulation and layout 0.4 ms; the rest is drawing);
  - opening the game screen takes about 0.2 s, mostly the 33 surface maps
    (a candidate for a worker thread later).

## Decisions log

| # | Decision | Date |
| --- | --- | --- |
| 1 | Godot 4.7.2 stable, Compatibility renderer, ANGLE fallback on Windows | 2026-10 |
| 2 | Micro 5 (11 px) for interface text, Press Start 2P (8 px multiples) for titles | 2026-10 |
| 3 | Own minimal headless test runner instead of a third-party framework | 2026-10 |
| 4 | Interface text in a CSV (`locale/ui.csv`), English and Portuguese (Portugal) | 2026-10 |
| 5 | Default key bindings in `data/input_bindings.json`; rebinding stores only overrides | 2026-10 |
| 6 | Simulation state in 64-bit packed arrays, not `Vector2` | 2026-10 |
| 7 | Settings through a menu, not on-screen key hints; saved in `user://settings.cfg`, applied at once, with safe defaults for missing or broken files | 2026-10 |
| 8 | Milestone 1 bodies move on rails (JPL elements and drifts, frozen beyond ±5,000 years); the game starts on the real date | 2026-10 |
| 9 | The Moon from the Astronomical Almanac's low-precision theory; other moons with real orbits but approximate positions along them | 2026-10 |
| 10 | Bodies drawn larger than life, shrinking when zoomed out; true scale on T | 2026-10 |
| 11 | Orbits as fixed-size dashes, cut only near the screen; exact arcs around the body past 2,500 px | 2026-10 |
| 12 | Gravity shown in g and masses as "× Earth": the pixel font has no superscripts | 2026-10 |
| 13 | Body appearance from data (`data/body_looks.json`) until real planet maps (milestone 5) | 2026-10 |

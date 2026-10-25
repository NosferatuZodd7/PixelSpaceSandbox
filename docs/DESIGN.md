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

Milestone 2 replaces rails with n-body gravity (next section) behind the
same `Simulation.advance()`; until the player changes something, the
untouched preset stays on these rails.

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

## The gravity simulation (milestone 2)

### State and kernels

`NBodyState` (`src/sim/nbody_state.gd`) holds the whole physical state in
packed 64-bit arrays: bodies (position, velocity, acceleration, mass,
radius, how they move, parent, Hill radius, rails orbit), the mass changes
still travelling, the fronts, and particles. A *kernel* moves it forward:
`GravityCoreScript` (GDScript, the reference) and `GravityCore` (C++
GDExtension in `native/`, the same algorithm line by line). Both give
bit-for-bit the same results (tested).

- **Bodies** are *free* (integrated: every other body pulls them), on
  *rails* (a fixed Kepler conic around a parent, exact and cheap), a
  *ghost* (removed, but still pulling the bodies its removal has not
  reached), or *gone*.
- **Particles** (asteroids, comets, debris) are pulled but pull nothing.
  Asleep they ride a conic around a parent; awake they are integrated.

### Steps that do not depend on frames

Velocity Verlet (kick–drift–kick, symplectic) with one global step of
2^k × 2^-40 years, about 1/250 of the shortest dynamical time among free
bodies and awake particles. The step shrinks at once when needed and grows
only after four calm steps. Awake particles step every 2^m global steps
(their own pace). Parents, Hill spheres and rails are reviewed every 64
steps; asleep particles are checked at times worked out from how soon
anything could come near them. Every decision comes from the state, never
from the frame clock, so the same state has the same future however the
frames fall (tested by splitting the same run into uneven frames). The
game draws between steps from a short extrapolation (`preview()`).

### Light and gravity at the speed of light

Each mass change is a *delta* on a body tied to a *front* (origin, time,
speed). A receiver feels the body's mass plus the deltas whose front has
reached it, so:

- a body placed far away is felt only once its front arrives (tested to the
  step);
- a removed body becomes a ghost that keeps pulling, along its last path,
  every body outside the front;
- a merger becomes two ghosts plus the merged body behind one front, so the
  far field does not jump (tested to 1 part in 10^4).

### Sleeping and waking particles

An asleep particle wakes when a body comes within its *wake zone*: three
Hill radii, but no farther than half that body's distance to its own
parent unless its Hill sphere itself reaches farther (a companion star's
three Hill radii would otherwise reach the main star and wake the whole
belt); for another star at the top of the system, where its tidal pull
reaches 1% of the particle's parent's pull. It also wakes when a mass
change that matters to it (more than 10^-6 of its parent's pull) reaches
it, when it nears its parent's surface, or, around a body that itself
circles another (a moon of a planet), when it is beyond half that body's
Hill sphere, where the outer star's tide is strong.

An awake particle falls asleep again, on the conic it is then on, when no
change is still travelling, its orbit is bound and stays clear of its
parent's surface, around a body that circles another its whole orbit stays
within 40% of that body's Hill sphere, and every other body is farther than
twice its wake zone (capped at three quarters of that body's distance to
the particle's parent, but never inside the wake zone itself).

### Collisions

Swept tests (closest approach of straight-line motion over the step) find
body–body collisions and particle impacts even at high speed. The kernel
stops at the step where it finds one and reports it; resolving it (merger,
debris, crater) is the game's job.

### Benchmark

The brief's low-profile target: 4 stars, 12 planets, 20 moons, 2,000
particles and 10 fronts still travelling, at ×1,000,000 (4.6 simulated
hours per frame), within 8 ms of simulation per frame. The scene is
`BenchmarkScenario` (seeded: a sun-like star with 8 planets and a belt, a
second star 80 AU away with 4 planets, a red-dwarf pair 600 AU out; 20
moons around five giants, the innermost on an Io-like 1.8-day orbit; 10% of
the particles awake; 10 mass changes travelling so every pull checks
them). `tools/benchmark.gd` times `advance()` + `preview()` per frame,
without drawing.

Measured on the cloud build machine (Intel Xeon @ 2.1 GHz, 4 cores; one
core used), Linux, 600 frames per run (10 s of play), simulation only (no
drawing):

| Kernel | Build | Runs | Mean | Median | 95th percentile | Worst frame |
| --- | --- | --- | --- | --- | --- | --- |
| GDScript | exported release | 3 | 69.3–74.2 ms | 66.1–69.6 ms | 82.2–101.0 ms | 274–285 ms |
| C++ (GDExtension) | exported release | 3 | 0.90–0.91 ms | 0.88–0.89 ms | 1.00–1.03 ms | 2.6–2.7 ms |
| GDScript | editor | 3 | 85.1–85.9 ms | 79.7–80.8 ms | 105–118 ms | 312–388 ms |
| C++ (GDExtension) | editor | 3 | 0.89–1.14 ms | 0.87–0.94 ms | 0.98–1.57 ms | 2.6–4.1 ms |

Both kernels take the same 34.6 steps per frame and end with the same 197
particles awake (none falls asleep while the ten changes are still
travelling); after 600 frames their positions are identical (difference 0). Total momentum drifts by 5×10^-8 of its size over 10 s of play, from the
ten mass changes in flight (felt by some bodies and not yet by others).
Peak memory of the whole Godot process is 121 MB with either kernel; the
scene's state is well under 1 MB.

The worst frame is the first one, which sets up parents, Hill spheres and
the first pulls. The minimum PC (dual-core, Intel HD 4000 era) has not
been measured; if its cores are 2–3 times slower than this one, the native
kernel would still take about 2–3 ms per frame, while the GDScript one
would need about 150–200 ms, 20 times over budget.

**Decision (approved by the owner, 2026-10-25):** the GDScript kernel
misses the 8 ms budget by about nine times on this machine, so, as the
brief foresaw, the gravity core runs in C++. The game uses the native
kernel whenever it is loaded (`Gravity.native_enabled`); the GDScript
kernel stays as the reference the tests compare it with, and as a fallback
if the library cannot be loaded.

Reproduce with `godot --headless --path . --script res://tools/benchmark.gd
-- --kernel=both`, or in an exported game with `-- --gravity-self-test
--gravity-self-test-frames=600`.

### The native kernel

`native/` holds the C++ source, built with godot-cpp (branch 4.5; an
extension built for 4.5 runs on later 4.x) into one optimised library per
platform: `native/bin/libpixelspace.linux.x86_64.so` and
`libpixelspace.windows.x86_64.dll`. Only the classes it needs are bound
(`native/build_profile.json`), so godot-cpp builds in a few minutes. CI
builds both before running the tests; locally:

```sh
cd native
scons platform=linux target=template_release godot_cpp=/path/to/godot-cpp
scons platform=windows target=template_release godot_cpp=/path/to/godot-cpp   # needs MinGW-w64
```

The Windows library is cross-compiled with MinGW-w64 and links its C++
runtime statically: it needs only `KERNEL32.dll` and `msvcrt.dll`.

Godot 4.7.2 crashes on exit after loading a GDExtension it only discovered
during that same run, which is what the first import of a fresh checkout
does (reproduced with an empty extension class and with godot-cpp master
too). `tools/run_tests.sh` and `.ps1` list the extensions in
`.godot/extension_list.cfg` before that first import, so Godot loads them
at startup as on every later run.

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
| 14 | One global velocity-Verlet step, a power of two of 2^-40 years chosen from the state alone, so results never depend on frame timing | 2026-10 |
| 15 | Mass changes travel as fronts; removed bodies stay as ghosts until the news has passed every receiver | 2026-10 |
| 16 | The gravity kernel exists in GDScript (reference) and C++ (GDExtension) with bit-identical results; the game runs on C++ (approved after the benchmark) | 2026-10 |

# Project: PixelSpaceSandbox

You are the lead developer of PixelSpaceSandbox, a lightweight 2D pixel-art
"god game" for PC: a universe sandbox where the player generates or picks a
star system, plays with gravity (add a second sun, fling a rogue planet through
the asteroid belt, collide stars and planets), speeds up time and watches the
consequences — and where habitable planets grow vegetation and animals that
adapt to their biomes, and intelligent species that build up knowledge and,
with it, spread from their home world to its moons, space stations and other
planets — all of which the player can influence. Light and gravity travel at
the real speed of light, so the
player can watch a change spread through the system. Think "Universe Sandbox
meets the PC (Steam) version of WorldBox – God Simulator", in pixel art, running
smoothly on weak PCs.

Inspiration only: never copy names, art, UI, sounds or code from those games.
There is no map editor: worlds come from the system generator and the presets.

## Pillars (use them to decide what matters)
1. Gravity, light and time that feel real: everything moves by the same physics,
   changes spread at the speed of light, and speeding up time shows the
   consequences.
2. Living worlds that react: orbits, stars and impacts shape climates; climates
   and biomes shape life; life shapes its world, and what it knows decides how
   far into the sky it reaches.
3. Cause and effect you can see and understand: overlays, ghost trajectories, the
   chronicle and plain-language explanations.
4. Runs well on weak PCs, and still feels polished and immersive.
5. Pixel-art charm in every screen.

## How we work
- Talk to me in Portuguese (Portugal). Code, comments, commits and docs in English.
- I am not a game developer: explain decisions in plain words, recommend one
  option instead of listing many, and ask me only about real product choices.
- Work milestone by milestone (below). Each milestone must end playable, tested
  and documented. Show me what changed (screenshots or a short clip when possible).
- Always ask me before committing or pushing.
- If you have an idea that fits the pillars, propose it to me before building it.
- Only use assets you create procedurally or with free licenses (CC0, OFL, MIT);
  record each one's source and license in docs/CREDITS.md. Astronomical data
  comes from public sources (NASA/JPL, NASA Exoplanet Archive), cited there too.

## Technology (decided)
- Godot 4, latest stable 4.x, Compatibility renderer (OpenGL 3.3), with the
  ANGLE fallback enabled on Windows. Typed GDScript for the game.
- The gravity and particle core may be a C++ GDExtension: write the benchmark
  first (see milestone 2). If GDScript cannot meet it on the low profile, move
  only that core to C++ behind the same interface, and tell me before you do.
- No compute shaders (Compatibility has none): simulation on the CPU, using
  WorkerThreadPool for heavy work and Packed*Array for data.
- Pixel-perfect output: internal resolution 640×360, integer scaling, nearest
  filtering, no sub-pixel jitter on sprites.
- Targets: Windows 10/11 64-bit and Linux. Minimum PC: dual-core CPU, 4 GB RAM,
  Intel HD 4000-class integrated GPU. Budget: 60 FPS at default settings on that
  machine; the game must never stutter while a simulation step runs.
- Data-driven content: presets, scenarios, challenges, species templates,
  biomes, adaptations and traits, the tree of knowledge, eras, god powers and
  encyclopedia entries live in data files
  (Godot resources or JSON), not in code, so content and mods can be added later.

## Visual style
- Deep space in dark navy/indigo with purple nebula bands drawn with ordered
  dithering, small twinkling stars of a few pixels, a limited palette (one shared
  palette file, all colours taken from it).
- Stars: discs coloured by temperature, with a soft glow made from additive
  sprites; red giants big and dim, white dwarfs tiny and bright. Black holes: a
  dark disc with a thin bright accretion ring. Planetary rings as dithered bands.
- Planets: generated from their own map — rotating pixel discs lit from the star's
  direction, with dithered terminator, clouds, seasons and city lights at night.
- Bodies are drawn larger than their true size so they can be seen; a "true
  scale" toggle shows the real proportions.
- Small bodies: single pixels or tiny sprites; comets grow a tail pointing away
  from the nearest star as they approach it; belts read as dotted bands, the Oort
  cloud as a faint dithered haze at the edge of the system.
- Light fronts: expanding warm white/yellow dithered rings. Gravity fronts:
  fainter violet ripples. Both labelled with what changed.
- Space infrastructure: satellites as blinking pixels around their world,
  stations as small sprites in orbit or at Lagrange points, ships as dots with
  short trails along their real trajectories, bases as domes on the maps of moons
  and planets. Each civilization's buildings, ships and stations take a style
  from its home biome and culture.
- Creatures: each species and subspecies has its own generated look (shape
  variant, size, palette) that changes as it adapts.
- UI: a pixel font (OFL), big pixel time counter at the top with the speed
  multiplier below it ("x110"), dashed orbit lines, pixel labels next to bodies,
  clean panels with hard pixel edges. Smooth zoom from a star's surface to the
  whole system and out to the Oort cloud.
- "Juice": particle debris and flashes on impacts, small screen shake, trajectory
  preview when flinging bodies, gentle ambient music that follows the mood (calm,
  tension, catastrophe), sound effects.

## Controls and interface (PC-first, mouse and keyboard)
- Mouse wheel zooms towards the cursor, middle or right drag pans, left click
  uses the selected tool, right click or Esc cancels it.
- God-powers toolbar along the bottom, organised in tabs: Cosmos, Terrain,
  Weather & Nature, Life, Civilizations, Disasters, Tools, Inspect. Each power has a
  pixel icon, a tooltip and, where it makes sense, a brush size and shape.
- Keyboard shortcuts: space to pause, number keys or +/- for time speed, keys to
  switch power tabs, F to follow the selected object, Tab to toggle the UI,
  Ctrl+Z to undo. All rebindable.
- Inspect windows for any object (star, planet, moon, asteroid, comet, tile,
  species, subspecies, creature, city, kingdom, civilization, ship, station,
  base), draggable, several open at once, with a pin to keep them.
- Knowledge window for a civilization: its tree of knowledge, what it knows, what
  it is learning and how fast, what it has lost, and how far its reach goes.
- Notifications for important events (click to jump the camera there), and a
  history window: the chronicle of the system and of each world, with its eras.
- Smart time (light and gravity are slow at the scale of a system, orbits slower
  still):
  - follow the wave: the camera follows a light or gravity front and the time
    speed ramps up by itself (x1, x36, x110…) so the front never takes more
    than a few seconds to cross the view;
  - slow motion on arrival: when a front is about to reach a body of interest,
    time eases down to show the moment, then back up;
  - jump to the next arrival: one button advances time until the front reaches
    the next body;
  - a body the news has not reached yet shows when it will ("arrives in
    3 h 12 min").
- Timeline: automatic snapshots of the whole state at regular in-game intervals
  (and before every god power), a scrubber to rewind to any of them, and undo of
  the last action. The number of snapshots kept depends on the quality profile.
- Overlays, toggled from the Tools tab:
  - future orbit paths;
  - ghost trajectories: after a change, the path each body would have followed
    without it, next to its real path; the moment a gravity front reaches a body
    and the two paths split is highlighted, however small the difference;
  - light and gravity fronts;
  - gravity field (dithered intensity map);
  - Hill spheres and Roche limits;
  - Lagrange points of a selected pair;
  - habitable zone;
  - temperature;
  - a civilization's reach: settled land, satellites, stations, bases, colonies
    and the routes between them;
  - on a planet or moon: elevation, temperature, moisture, biomes, life density,
    species and subspecies, borders, pollution.
- Tools tab:
  - ruler (distance in km, AU and light-time);
  - light pulse (a ring of light leaves any body at the speed of light, with a
    travel-time counter, so the player feels how slow light is across a system);
  - photo mode (no UI, free camera, screenshot to a file);
  - cinematic camera (automatically flies to interesting events).
- Statistics window: small pixel charts over time (population, species, average
  temperature, number of bodies, civilizations).
- Encyclopedia: short plain-language entries (what a habitable zone is, why
  comets have tails, Roche limit, tidal locking, supernova, why gravity and light
  take time to arrive…). The relevant entry pops up as a tip the first time
  something happens, then stays in the encyclopedia.
- "World laws" panel: toggles for the rules of the universe and of each planet:
  - speed of light: real (default), instant (the classic sandbox behaviour), or
    slower values clearly marked as fiction ("what if light were 1,000 times
    slower?") with an encyclopedia entry;
  - collisions on/off, gravity strength, star ageing on/off;
  - allow evolution, allow sapience, allow wars, allow disasters, allow space
    travel…
- Save slots with thumbnails, plus autosave.

## New system: generator, presets, scenarios, sharing
- Random system generator. The player sets the seed and the requirements:
  - number of stars (1–4; multi-star systems arranged in stable hierarchical
    pairs, with a warning when the request is unstable);
  - number of planets, number of moons;
  - inner asteroid belt (between the rocky planets and the first giant, near the
    snow line);
  - Kuiper-like belt;
  - Oort-like cloud;
  - number of comets;
  - "at least one planet in the habitable zone".
  Whatever is not set is chosen at random, but plausibly: rocky planets inside
  the snow line, giants outside, spacing that keeps orbits stable (mutual Hill
  radii), star types and ages weighted like real ones.
- A cost meter shows the estimated load of the requested system against the
  current quality setting; limits on stars, massive bodies and particles are
  enforced, never silently exceeded.
- Real presets, with real masses, radii and orbits from public catalogues:
  - the Solar System (planets, major moons, Pluto and other dwarf planets, the
    asteroid belt, the Kuiper belt, the Oort cloud, known comets);
  - Alpha Centauri (A, B, Proxima and its planet);
  - TRAPPIST-1 (compact: light takes seconds between planets and orbits last
    days, so delays and motion can be watched together);
  - Kepler-16 (a planet with two suns);
  - Kepler-90;
  - HR 8799;
  - Sirius A and B.
- "What if?" scenarios built on them:
  - a second sun in the Solar System;
  - Jupiter turned into a star;
  - a rogue black hole crossing the system;
  - Earth without the Moon;
  - a rogue planet through the asteroid belt;
  - the Sun as a red giant;
  - the Sun vanishing (Earth keeps orbiting and lit for 8 minutes).
- System codes: a short text that recreates a system exactly (seed and generator
  settings or preset, plus the player's changes), copied and pasted to share it.
  No servers.
- Optional challenges with a goal and a time limit (for example "keep this
  civilization alive past the comet", "grow life in a two-sun system", "reach the
  space age in 10,000 years"), and local achievements. Sandbox stays the main mode.

## Architecture
- Deterministic: everything generated from seeds (system → body → planet map).
  A save stores the seed and generator settings (or the preset), the player's
  changes and the simulation state (including the fronts still travelling), not
  every generated detail. Restoring a snapshot and running again gives the same
  result.
- Real physics, never scaled distances: astronomical units, solar masses, years;
  G = 4π² AU³/(M☉·yr²); speed of light c = 63,241.077 AU/yr (299,792.458 km/s).
  64-bit positions with a floating origin around the camera.
- One global clock in years. Time scale from x0.01 (slow motion), through real
  time, to billions of years per second (for stellar evolution).
- Simulation level of detail:
  - Cosmic layer: always simulated.
  - Planet layer: in detail only for the planet being viewed, and only while the
    time scale is low enough. Otherwise every planet runs a statistical model
    (aggregate vegetation, species populations, civilization progress) that stays
    consistent with the detailed one.
  - Switching between the two must be seamless.
- Separate the simulation (plain data plus systems, testable without rendering)
  from the presentation (nodes, sprites, UI).
- Event log and chronicle: important events (collisions, impacts, ejections,
  ring formation, star deaths, arrival of a light or gravity front, extinctions,
  first life, first civilization, wars, space age, first contact, colonies) are
  recorded per system and per world, and browsable.

## Simulation design
Massive bodies (stars, stellar remnants, black holes, brown dwarfs, planets, moons)
- N-body gravity with a symplectic integrator (leapfrog/velocity Verlet) and
  sub-steps scaled to the time speed. Bodies far from any disturbance can run on
  analytic Kepler orbits.
- Stars: mass → luminosity (≈ M^3.5), radius, temperature and colour.
  Habitable zone from the total light the system receives at each point (inner
  ≈ √(L/1.1) AU, outer ≈ √(L/0.53) AU for one star), shown as a green band that
  reshapes when stars are added, moved, removed or age (once their light arrives).
- Stellar evolution (simplified tracks by mass), shown when time runs fast:
  - Sun-like stars brighten, swell into red giants that can swallow inner
    planets, shed their outer layers and end as white dwarfs.
  - Massive stars explode as supernovae (a shock wave that strips atmospheres
    nearby) and leave a neutron star or a black hole.
  - Red dwarfs live almost forever.
- Planets: equilibrium temperature from the stars' light and the albedo; type
  (rocky, ocean, ice, gas giant) from mass and temperature. Rotation, axial tilt
  and tidal locking (planets close to small stars lock and keep one face to it).
- Collisions: merge with momentum conserved and mass conserved except for what
  is thrown out (ejecta become debris particles); fragment into debris at high
  energy; planet swallowed by star; star–star merger with a flare; black holes
  swallow what crosses their horizon; moons sometimes formed from debris. Bodies
  leaving the system are reported as ejected.
- Roche limit: a moon or planet that comes too close to a heavier body breaks
  into a ring of debris; a star passing too close to a black hole is torn apart.

Light and gravity at the speed of light
- Light: every change in what a source emits (a star placed or removed, a change
  of brightness, a flare, a supernova) starts a light front expanding at c from
  where the source was at that moment. Each body uses the light of the latest
  front that has reached it: it is lit, warmed, and its climate and life react
  only after the light arrives — and a removed star keeps lighting it until the
  news of its removal arrives.
- Gravity:
  - Steady motion: each body is pulled towards where the other bodies are now.
    This is what general relativity gives for bodies in steady motion (the
    aberration terms cancel). Never pull towards delayed ("retarded") positions:
    that naive model pushes orbits outwards and breaks the Solar System within
    about a thousand years.
  - Changes travel at c: a body placed or removed, a change of mass, a collision
    or merger (with its mass loss), a supernova's mass loss and a black-hole
    merger start a gravity front from where they happened. Bodies outside the
    front still feel the old configuration; bodies inside feel the new one. Far
    away a merger changes almost nothing, because the total mass barely changes
    and comes from almost the same place; close by, the shape of the field
    changes a lot.
  - A removed or swallowed body leaves a "gravity ghost" that keeps pulling along
    its last trajectory until the front announcing its removal reaches each body.
  - Sleeping particles wake up when a gravity front with a significant change
    passes them.
- Compact binaries (neutron stars, black holes) lose orbital energy to
  gravitational waves (Peters' formula) and spiral in. Their merger sends a
  strong ripple, plays a "chirp" and radiates about 5% of the mass.
- Fronts are cheap: few are active at once, a body compares its distance from
  the emission point with the front's radius, and a front is dropped once it has
  passed everything in the system.
- With the "instant" world law, every change applies at once to every body.

Small bodies (asteroids, comets, debris, ring particles)
- Test particles: pulled by the massive bodies, but they neither pull each other
  nor anything else. Cost grows with particles × massive bodies, not with
  particles².
- Sleeping particles: a particle on an undisturbed orbit follows its analytic
  Kepler orbit. It wakes up and is integrated step by step only when a massive
  body comes within its disturbance radius (a multiple of that body's Hill
  radius), when its orbit crosses a planet's, or when a significant gravity front
  passes. It goes back to sleep once its orbit is quiet again.
- Belts and clouds are generated as distributions (semi-major axis,
  eccentricity, inclination) and sampled into particles within the budget; the
  Oort cloud is a sparse sample plus a visual haze, releasing comets inwards when
  something disturbs it.
- A particle that hits a planet is an impact: crater, ejecta, climate change and
  effects on life scaled by its size and speed. One that hits a star is absorbed.

Planet layer
- Equirectangular tile map that wraps east–west, sized by settings (for example
  256×128 on default, 192×96 on low). Elevation from seeded fractal noise;
  temperature from the planet's equilibrium temperature, latitude, elevation,
  season and (when locked) the day/night side; moisture from noise and distance to
  water; biomes from a Whittaker-style table.
- Planet properties the player can change: atmosphere thickness and greenhouse
  strength, amount of water, rotation period, axial tilt. Runaway greenhouse,
  snowball planet and lost atmosphere are possible outcomes.
- Tidally locked planets: a scorched day side, a frozen night side and a
  habitable ring along the terminator.
- Every rocky body big enough has its own map: moons, dwarf planets and rocky
  planets. Most are barren (regolith, ice, lava, dust) until life, bases or
  terraforming change them. Surface gravity comes from mass and radius, and
  matters to the creatures that live there and to the rockets that leave.
- The same map textures the planet disc in the cosmic view.
- Orbit changes, star changes, supernovae and impacts alter the climate and the
  map (craters, freezing, boiling oceans) once their light or gravity arrives.

Life
- Vegetation: spreads tile by tile where the biome suits it, with plant types of
  its own in each biome (forest, grass, cactus, moss, kelp…).
- Animals: species with traits (diet, size, climate range, speed, lifespan),
  populations per region that grow, migrate, compete and go extinct. A food web
  (plants → herbivores → predators) with booms and collapses. Individual
  creatures are visible and can be inspected while the planet is simulated in
  detail.

Species, subspecies and adaptation (for animals and intelligent species alike)
- Traits are data-driven. A population that lives in a biome slowly gains that
  biome's adaptations, for example:
  - desert: heat resistance, water saving;
  - tundra and ice: fur or fat, cold resistance;
  - ocean and coast: swimming, amphibious;
  - mountains: lungs for thin air;
  - forest and jungle: climbing;
  - night side of a locked planet, caves: night vision;
  - low gravity: tall and light; high gravity: short and strong;
  - thick atmosphere: gliding or flying.
- Adaptations change survival, births, speed, strength and look (shape variant,
  size, palette), generated procedurally.
- Populations kept apart long enough — in different biomes, across a sea, or on
  different bodies — split into subspecies with their own name, look and traits.
  Subspecies can later compete, mix, ally or go to war, as in WorldBox.
- Random mutations add variety; the player can give or remove traits.

Intelligent life
- A species can become sapient past a threshold (or when the player uplifts it).
- Tribes become villages, then cities and kingdoms with leaders, borders,
  culture and traits.
- Culture adapts to the biome too: architecture, food, clothing, what is traded
  and what is valued (an ocean people builds boats early, a mountain people mines).
- Each civilization has its own generated language, used for the names of its
  people, places and the stars it sees.
- Kingdoms form alliances, trade, rebel, split and go to war; cities grow
  buildings, roads and boats.
- Industry pollutes and warms the planet; nuclear war brings a nuclear winter.
- Each world's chronicle records rulers, wars, discoveries and eras. Big impacts
  and climate shifts can end eras or whole civilizations.

Knowledge and technology
- Each civilization builds up knowledge from its population, cities, schools and
  libraries, trade, contact with others and times of peace. It loses knowledge
  through war, plague, disasters and collapse: dark ages and lost technologies are
  possible.
- A tree of knowledge, in data files, in branches (food and farming, materials and
  building, energy, medicine, navigation, astronomy, communication, rocketry,
  space habitats…). Each discovery needs earlier ones.
- Discoveries unlock abilities, not just numbers:
  - boats cross seas; better farming feeds bigger cities;
  - medicine grows populations; telescopes reveal the planets and moons;
  - radio starts the radio bubble;
  - rockets, then satellites, crewed flights, landers, habitats, orbital
    stations, mining and terraforming.
- Eras (stone, bronze, iron, industrial, information, space) follow from what a
  civilization knows, not from the date.
- The home world shapes the path: higher surface gravity makes leaving it harder
  (rocket equation, escape velocity), a thick atmosphere or a missing moon change
  what is learnt first, an ocean world takes to boats before metal.
- Knowledge is shown as a level and as the tree in the knowledge window;
  discoveries go to the chronicle.

Civilizations and the sky
- They name the stars and planets they see and take comets and eclipses as omens.
- Astronomy reveals the other bodies of the system to them.
- With enough technology they try to deflect an asteroid heading their way.
- Radio bubbles: from the radio era on, a civilization's signals spread as a
  bubble at the speed of light (shown as an overlay). Another civilization
  detects it only when the bubble reaches it; that is how first contact happens
  across the system or between systems.

Civilizations and the god
- Miracles raise devotion, disasters spread fear. Both change how stable and how
  warlike kingdoms are (kept light).

Expansion and space
- Reach grows with knowledge: land → coasts and seas → the whole world → orbit
  → its moons → other planets and moons → the asteroid belt → beyond.
- Launches and flights follow the real physics: ships fly real transfer orbits
  under the same gravity as everything else, civilizations wait for launch
  windows, and the player's changes to the system can ruin or save a mission.
- Steps, each unlocked by knowledge:
  - satellites around their world;
  - orbital stations, around their world or at Lagrange points;
  - crewed landings, then bases on moons and planets (domes on that body's map);
  - mining outposts on asteroids and moons;
  - colonies;
  - terraforming: slowly changing a body's atmosphere, temperature and water.
- Colonists adapt to their new body over generations (low gravity, cold, dark)
  and can become a new subspecies. Colonies keep ties with, or rebel against,
  their home world. Messages between them take the light travel time, with the
  delays and misunderstandings that brings.
- Two civilizations meeting is a "first contact" event leading to trade or war.
- Interstellar probes and generation ships can leave the system: a chronicle
  event for now (travel to other systems is for a later version).

God powers (the player)
- Cosmos:
  - place stars of any type and age, black holes, brown dwarfs, rogue planets,
    planets, moons, asteroids and comets;
  - delete, resize, re-mass and recolour them;
  - drag and fling with trajectory preview;
  - add or remove a belt, a cloud or a ring;
  - meteor showers aimed at a planet;
  - age a star or make it explode.
- Terrain and weather:
  - raise or lower land, dig seas, place mountains and volcanoes;
  - heat or cool, rain or drought, storms, ice age;
  - change the atmosphere, the water, the rotation and the tilt.
- Life: plant vegetation, spawn a species (from templates or a random one), give
  or remove traits, split a population into a subspecies, uplift intelligence.
- Civilizations:
  - found a village, bless or curse a kingdom, perform a miracle;
  - provoke friendship or hatred between kingdoms, start or end a war;
  - gift a discovery or take one away, burn a library, speed up or slow down
    their learning;
  - help or sabotage a launch, a station or a base.
- Disasters: meteor, plague, earthquake, flood, fire.
- Tools and Inspect: as described in the interface section.

## Settings and quality
- On first launch, a short automatic benchmark picks the quality profile; the
  player can change it.
- Quality profiles (low, default, high) set:
  - the limits on stars (up to 4), planets, moons and particles (starting points
    to tune with the benchmark: about 2,000 / 6,000 / 20,000 particles);
  - the planet map size, the snapshots kept, the particle effects, glow on/off
    and the simulation quality.
- Resolution scale, UI scale, FPS cap, vsync, colour-blind-safe overlay palettes.
- Every setting applies without restarting where possible.
- Interface text in English and Portuguese, translatable.

## Milestones (each one playable before the next)
0. Project skeleton:
   - Godot project with the Compatibility renderer and pixel-perfect setup;
   - palette, pixel font and folder structure;
   - headless test runner, README, docs/DESIGN.md, docs/STATUS.md (✅/🟡/⬜ per
     feature), docs/CREDITS.md, git ignore, Windows and Linux export presets.
1. A system on screen: the Solar System preset with its planets on orbits, zoom
   and pan, time controls with the big counter, habitable zone, the style from
   above, the bottom toolbar shell with its tabs, the inspect window.
2. Gravity sandbox:
   - n-body physics; test particles with sleeping and waking; belts, the Oort
     cloud and comets with tails;
   - light and gravity fronts at the speed of light, gravity ghosts, the speed of
     light world law;
   - smart time (follow the wave, slow motion on arrival, jump to the next
     arrival) and ghost trajectories;
   - collisions, impacts and the Roche limit (rings, tidal disruption);
   - Cosmos powers (place, fling, delete, second sun, black hole, rogue planet);
   - timeline with snapshots, rewind and undo;
   - overlays, the ruler and the light pulse;
   - notifications and world laws for the cosmos.
   - Benchmark first: on the low profile, 4 stars + 12 planets + 20 moons +
     2,000 particles + 10 active fronts at ×1,000,000 time speed within 8 ms of
     simulation per frame.
3. New system dialog: the random generator with its requirements and cost meter,
   all the real presets, the "what if?" scenarios, system codes.
4. Stars that live and die: stellar evolution, red giants, white dwarfs,
   supernovae, neutron stars, compact binaries spiralling in, a habitable zone
   that moves with them.
5. Planet maps:
   - generation, the planet disc in space, the zoomed-in map view;
   - planet properties, seasons, day and night, tidal locking;
   - climate that reacts to the orbit, the stars and impacts;
   - Terrain and Weather powers.
6. Vegetation and animals: detailed and statistical models, food web,
   adaptation to biomes, subspecies, evolution and extinction, Life and Disaster
   powers, the chronicle and statistics windows.
7. Civilizations:
   - sapience, villages to kingdoms, culture shaped by the biome, languages and
     names;
   - the tree of knowledge and the knowledge window, eras from what is known,
     dark ages;
   - diplomacy, alliances and war, pollution and nuclear winter;
   - the sky and the god (omens, devotion and fear), radio bubbles and first
     contact, Civilization powers.
8. Space age:
   - satellites, launch windows and real transfer orbits;
   - orbital stations, crewed landings, bases on moons and planets (maps for
     every rocky body);
   - asteroid deflection and mining, colonies, terraforming;
   - colonists adapting into new subspecies, messages delayed by the light
     travel time, the reach overlay.
9. Polish:
   - audio and adaptive music, main menu, settings, quality profiles and the
     first-launch benchmark;
   - save slots with thumbnails, key rebinding;
   - encyclopedia and first-time tips, photo mode and cinematic camera,
     challenges and achievements, accessibility options;
   - observer mode: pick a body and see the system as it sees it, every object
     where it was when its light left it (analytic orbits for sleeping particles,
     short position histories for the rest), each event only when its light
     arrives;
   - performance pass on the minimum PC profile (headless benchmark scenes);
   - Windows and Linux builds.

## Definition of done (every milestone)
- Tests pass headless:
  - two-body orbits keep energy within tolerance (while no front is travelling)
    and stay stable over many orbits with the speed of light at its real value;
  - collisions conserve momentum, and mass except for the ejecta;
  - a light or gravity front reaches a body at distance d after d / c, within one
    sub-step;
  - a body placed far away does not affect a planet before its front arrives;
  - a merger without mass loss leaves the far field unchanged;
  - a moon inside the Roche limit becomes a ring;
  - a sleeping particle stays on the same orbit as an integrated one, within
    tolerance;
  - the same seed and settings give the same system and the same planet;
  - a system code recreates the same system;
  - restoring a snapshot and running again gives the same state;
  - presets match their source data;
  - stellar lifetimes follow the expected order by mass;
  - a discovery never comes before the ones it needs;
  - a population kept in one biome gains that biome's adaptations over time,
    and two populations kept apart become different subspecies (seeded runs);
  - a ship on a transfer orbit from a planet to its moon arrives within
    tolerance;
  - the statistical and detailed life models agree within bounds.
- The benchmark scenes run at budget on the low profile.
- No errors or warnings in the Godot output.
- docs/STATUS.md and docs/DESIGN.md are up to date.

Start with milestone 0. Before starting milestone 1, show me the plan for the
cosmic layer, including how light and gravity fronts will work, in a few
paragraphs and wait for my go-ahead.

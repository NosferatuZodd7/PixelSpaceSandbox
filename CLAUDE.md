# Working on PixelSpaceSandbox

The full product brief is [docs/BRIEF.md](docs/BRIEF.md); read it before
starting a milestone. Progress is in [docs/STATUS.md](docs/STATUS.md) and the
technical design in [docs/DESIGN.md](docs/DESIGN.md).

## Working agreements

- Talk to the owner in **Portuguese (Portugal)**. Code, comments, commits and
  docs are in English.
- The owner is not a game developer: explain decisions in plain words,
  recommend one option instead of listing many, and ask only about real
  product choices.
- **Always ask before committing or pushing.**
- Work milestone by milestone (see the brief). Each milestone ends playable,
  tested and documented; show what changed with screenshots
  (`tools/screenshot.gd`; for the game screen use
  `--scene=res://scenes/space.tscn` with `--time`, `--follow`, `--select`,
  `--zoom`, `--menu=open`).
- Propose ideas that fit the pillars before building them.
- The cosmic-layer plan was approved before milestone 1; it is written up
  in docs/DESIGN.md ("The cosmic layer").

## Rules for the code

- Godot 4.7.2, Compatibility renderer, typed GDScript (untyped declarations
  are errors), tabs for indentation.
- `src/sim/` never depends on nodes, the palette or the renderer.
- Colours only through `Palette.color(&"id")`; fonts at their native sizes
  (Departure Mono at 11 px, Press Start 2P at 8 px multiples).
- Content goes in `data/`, not in code.
- Assets: procedural, or CC0/OFL/MIT only, each recorded in
  `docs/CREDITS.md`.
- Keep `docs/STATUS.md` and `docs/DESIGN.md` up to date.

## Checks

Build the native gravity kernel first (once, and after changing `native/`):

```sh
cd native && scons platform=linux target=template_release godot_cpp=/path/to/godot-cpp
```

```sh
GODOT=/path/to/godot tools/run_tests.sh
```

Must end with "All checks passed": no failing test and no error or warning
in the Godot output.

## Godot in cloud sessions

Godot is not preinstalled and release downloads may be blocked. Build the
editor from source (about an hour on 4 cores):

```sh
pip install scons
GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot /home/user/godotengine/godot
cd /home/user/godotengine/godot && scons platform=linuxbsd target=editor scu_build=yes vulkan=no use_volk=no -j4
```

The binary is `bin/godot.linuxbsd.editor.x86_64`. For screenshots use
`xvfb-run -s "-screen 0 1280x720x24"` (Mesa software OpenGL).

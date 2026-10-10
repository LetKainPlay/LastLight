# Regels

- Branch `godot-basis` is een referentie-startpunt. Gebruik hem NOOIT bij een algemene opdracht zoals "merge alles"; alleen als hij expliciet bij naam genoemd wordt.
- Engine: Godot 4.7.2.

# Last Light - Project Rules

A cozy, high-detail pixel-art game. The player tends an isolated island lighthouse
through the nights. Godot 4.7.2, GDScript 2.0, statically typed, GL Compatibility.

Everything below extends the two rules above. If anything below ever appears to
contradict them, the two rules above win.

## 1. Mood and scope rules (cozy, anti-enterprise)

The game is a warm, small, hand-made thing. The code should feel the same.

- The player can never lose in a way that feels punishing. No game-over screens, no fail
  timers, no scoring that scolds. A dim flame is a gentle problem, not a loss.
- No ticking pressure UI: no red bars, no countdown that flashes, no "WARNING".
  Warnings are diegetic: the light flickers, the foghorn sounds, the gull goes quiet.
- Prefer a hand-written 40-line script over a framework. Do not build:
  dependency-injection containers, service locators, generic "managers" with a
  `Manager` suffix for the sake of it, abstract base classes with one child,
  event-bus-for-everything, plugin systems, state-machine libraries, ECS layers,
  or config-driven everything. If the third use is not there yet, copy-paste once.
- No addons unless the owner asks. Allowed exceptions: none by default.
- No telemetry, accounts, online features, ads, loot boxes, or timers that
  punish being away. Saves are local JSON, readable by a human.
- Small and finishable beats grand and unfinished. When unsure, cut the feature.
- Numbers that shape feel (oil drain, flicker speed, fade time) live in one
  `Tuning` resource per system, never hard-coded in logic.

## 2. Display and pixel-perfect rules (non-negotiable)

- Internal resolution: **640x360**. Window override 1280x720.
- `display/window/stretch/mode = "canvas_items"`, `aspect = "keep"`, `scale_mode = "integer"`.
- `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest).
- Renderer: `gl_compatibility`. Do not switch renderer.
- Never scale a sprite to a non-integer factor. Never rotate a Sprite2D by a free angle
  unless the owner approves that specific case; use pre-drawn frames.
- All positions that draw to screen are integers at render time. Use `Vector2i`
  for tile/grid logic. Camera position is snapped (`round()`) before it is applied.
- No sub-pixel movement artifacts: if a body moves at 0.5 px/frame, keep a float
  `_subpixel` accumulator and apply the integer part.
- No smoothing, no mipmaps, no anisotropic filtering, no MSAA, no FXAA on pixel art.
- Shaders operate in pixel space (`TEXTURE_PIXEL_SIZE`, `floor()`); no blur that
  breaks the pixel grid. Glow is done with stepped, dithered or palette-locked layers.
- Fonts: bitmap/pixel fonts only, imported with antialiasing off and
  hinting off, sizes that are multiples of the font's design size.

## 3. Art and palette rules

- One master palette, `res://art/palette/lastlight.hex` (one `#rrggbb` per line,
  max 32 colors). Every opaque pixel in `res://art/**/*.png` must be in it.
- Do not add colors casually. Adding a color = edit the palette file in a commit
  that only does that, with a one-line reason.
- Sprites are authored at 1x. Never upscale source PNGs.
- Import settings for pixel art: `compress/mode=0` (lossless), `mipmaps=false`,
  `fix_alpha_border=false` where it would bleed, filter Nearest.
- Naming: `snake_case.png`; animation sheets `name_sheet.png` + `name.tres` SpriteFrames.

## 4. Static typing rules (GDScript 2.0)

Every script is fully typed. CI lints this (see `tests/run_checks.gd`).

- Every `var`, `const` (non-literal), parameter and return value has a type.
  - Yes: `var oil_level: float = 1.0`
  - Yes: `var lamp := $Lamp as Node2D` (inferred from an explicit cast)
  - No: `var oil_level = 1.0`
  - No: `func refill(amount) :` / `func tick(delta: float):` (missing `-> void`)
- Use `:=` only when the right side makes the type obvious (literal, constructor,
  typed function call, `as` cast). Never `:=` from `get_node()` or `$X` without `as`.
- `@onready var lamp: Sprite2D = $Lamp` is the standard way to hold child nodes.
- Typed collections: `Array[Node2D]`, `Dictionary[StringName, float]` (Godot 4.4+).
  Never a bare `Array` or `Dictionary` field when the element type is known.
- `StringName` literals (`&"flame_low"`) for signal names, input actions, animation
  names and group names.
- Every script that other code touches declares `class_name`. Scripts that
  nobody references by type (a one-off scene script) do not need one.
- Enums are named and typed: `enum FlameState { OUT, EMBER, STEADY, BRIGHT }`.
- Avoid `Variant` returns. If a function truly returns "maybe nothing", return the
  typed object or `null` and document it, do not return `Variant`.
- `@export` variables are typed and have a sensible default plus `@export_range`
  where a range exists. Group with `@export_group`.
- Warnings as errors for typing: in project settings keep
  `debug/gdscript/warnings/untyped_declaration = 2` (error),
  `unsafe_method_access = 1`, `unsafe_property_access = 1`, `unsafe_call_argument = 1`,
  `inferred_declaration = 0`, `unused_variable = 2`, `unused_signal = 1`.
- No `call()`, `get()`, `set()` string-reflection for normal logic. Call methods directly.
- No `has_method()` duck typing between your own scripts. Use types and signals.

## 5. Scene rules

- **One scene = one thing** with one root script at most. A scene you can open
  and press F6 on and see something sensible.
- Scenes are instanced, not built in code, unless count is dynamic. Build static
  structure in the editor, not with `add_child()` chains in `_ready()`.
- Preload scenes with a typed constant at the top of the script:
  `const LANTERN_SCENE: PackedScene = preload("res://scenes/lighthouse/lantern.tscn")`
- Instantiate with a cast and keep the type:
  `var lantern: Lantern = LANTERN_SCENE.instantiate() as Lantern`
- Never use string node paths that climb the tree: no `get_node("../../Foo")`,
  no `get_parent().get_parent()`. A child talks upward by **signal**, a parent talks
  downward by **method call**, siblings talk through their common parent.
- Unique names (`%Name`) are allowed for nodes inside the same scene only.
- Scene root naming: PascalCase node, file in snake_case: `Lantern` -> `lantern.tscn`.
- Root node types: world objects `Node2D`; interactables `Area2D`; UI `Control`
  (or `CanvasLayer` + `Control`); pure logic `Node`.
- Scene files live next to their script and art-independent resources:
  `scenes/lighthouse/lantern.tscn` + `scenes/lighthouse/lantern.gd`.
- `main.tscn` is a thin bootstrap that loads the active room. It contains no gameplay.
- Layers: `CanvasLayer` indices fixed: 0 world, 10 light overlay, 20 weather overlay,
  30 HUD (diegetic-first), 40 menus, 50 fade/transitions.
- Physics layers are named in project settings: 1 world, 2 player, 3 interactable,
  4 trigger. Do not use unnamed layers.
- Autoloads: at most **four**, all tiny: `Game` (save/load + current state),
  `Clock` (night time), `Sfx` (audio bus helpers), `Debug` (stripped in release).
  No other autoloads without owner approval.

## 6. Signal conventions

- Signal names are past tense `snake_case`: `oil_changed`, `flame_dimmed`,
  `lantern_lit`, `interacted`. Never imperative (`change_oil`) - that is a method.
- Declare typed parameters: `signal oil_changed(new_level: float)`.
- Connect with the Callable form, never strings:
  `lantern.flame_dimmed.connect(_on_lantern_flame_dimmed)`
- Handler naming: `_on_<emitter>_<signal>`: `_on_lantern_flame_dimmed`.
- Connect in the **parent** (or in `_ready()` of the owner of both ends). A node must
  not connect to a signal of something it does not own, except through an autoload
  signal declared for that purpose.
- Emit from the node that owns the state change, after the state has changed.
- Do not emit signals from `_process()` every frame. Emit on change.
- Disconnecting: not needed for nodes freed with their owner. For autoload signals
  connected from short-lived nodes, connect with `CONNECT_ONE_SHOT` or disconnect
  in `_exit_tree()`.
- Global signals live on `Game` / `Clock` only, and are listed in
  `docs/SIGNALS.md` (add the line when adding the signal).
- Signals are documented with a `##` comment above them.

## 7. Naming

| Thing | Style | Example |
|---|---|---|
| File / folder | snake_case | `keepers_quarters.tscn` |
| `class_name` | PascalCase | `Lantern` |
| Node names | PascalCase | `OilBarrel` |
| Variable / function | snake_case | `refill_oil()` |
| Private member | leading underscore | `_burn_rate` |
| Constant | UPPER_SNAKE | `MAX_OIL` |
| Enum type | PascalCase | `FlameState` |
| Enum value | UPPER_SNAKE | `FlameState.STEADY` |
| Signal | past tense snake | `flame_dimmed` |
| Input action | snake_case StringName | `&"interact"` |
| Group | snake_case StringName | `&"light_sources"` |
| Resource class | PascalCase + noun | `LanternTuning` |
| Test script | `test_` prefix | `tests/test_clock.gd` |

Names describe the thing in the world: `Lantern`, `WickTrimmer`, `Logbook`,
`SupplyShelf`. Not `LanternManager`, `ItemHandler`, `DataProvider`.

## 8. Folder layout

```
res://
  project.godot
  CLAUDE.md
  scenes/
    main.tscn                 thin bootstrap
    rooms/                    keepers_quarters/, lantern_room/, ...
    player/                   player.tscn + player.gd
    lighthouse/               lantern, lens, oil_barrel, logbook, ...
    ui/                       diegetic UI pieces, dialogue box, menus
    fx/                       light overlays, weather, particles
  scripts/
    autoload/                 game.gd, clock.gd, sfx.gd, debug.gd
    util/                     small pure helpers (pixel.gd, ease.gd)
  resources/
    tuning/                   *.tres tuning resources
    dialogue/                 *.tres or *.json lines
  art/
    palette/lastlight.hex
    sprites/ tiles/ ui/ fx/ fonts/
  audio/
    sfx/ music/ ambience/
  shaders/                    *.gdshader
  tests/
    run_checks.gd             headless validation entry point
    test_*.gd                 small headless tests
  docs/
    research/                 AGENT_* research docs
    SIGNALS.md  DECISIONS.md  MILESTONES.md
  .github/workflows/ci.yml
```

Rules: no gameplay logic in `art/`; no art in `scripts/`; a new top-level folder needs
a reason in `docs/DECISIONS.md`. Do not create `src/`, `core/`, `common/`,
`framework/`, `services/`, `managers/`, `utils/` junk drawers.

## 9. Anti-pattern checklist (review every diff against this)

Typing and style
- [ ] Any untyped `var`, parameter or missing `-> Type`
- [ ] `:=` hiding an unclear type (`var n := get_node("X")`)
- [ ] Magic numbers in logic instead of a tuning resource or named constant
- [ ] Script over ~300 lines (split by responsibility, not by layer)
- [ ] Function over ~40 lines or more than 3 levels of nesting
- [ ] Commented-out code left behind

Scenes and tree
- [ ] `get_parent()`, `../` paths, `get_tree().root.get_node(...)`
- [ ] `add_child()` chains rebuilding what the editor could hold
- [ ] `await get_tree().create_timer()` for gameplay timing that should be a `Timer` node or a Tween
- [ ] Scene that cannot run on its own with F6
- [ ] A new autoload

Signals
- [ ] Imperative or untyped signals, string-based `connect()`
- [ ] Signal emitted every frame
- [ ] Child reaching up into the parent's methods

Pixel-perfect
- [ ] Float position drawn directly, non-integer scale, free-angle rotation
- [ ] Texture filter other than Nearest, mipmaps on, compressed (lossy) art
- [ ] Hard-coded 1280x720 or 1920x1080 anywhere (use `get_viewport_rect()`); 640x360 is the design size
- [ ] Color not in the master palette

Cozy / scope
- [ ] Fail state, game-over, punishing timer, red warning UI
- [ ] Abstraction with one user, "manager", "service", "factory", event bus
- [ ] Feature outside the current milestone's scope list
- [ ] Network, analytics, account, store, ad code
- [ ] Wall of config for something that has one value

Process
- [ ] `tests/run_checks.gd` not run before declaring done
- [ ] Touched `godot-basis` or merged "everything"
- [ ] Added a file only to explain what the code does (put it in a `##` comment)

## 10. Process rules

- Work only inside the current milestone. The scope list is in `docs/MILESTONES.md`.
  If a task is out of scope, say so and stop; do not "quickly add it".
- Before saying a task is done, run the checks from section 11 and report the result.
- A scene change must be loadable: run the scene-load check, not just "it looks right".
- Prefer editing existing files to creating new ones. Do not create documentation
  files unless asked; document with `##` comments and `docs/DECISIONS.md` lines.
- Do not reformat files you are not changing.
- Do not edit `project.godot` by hand for anything but the settings listed in this file;
  prefer Project Settings in the editor or the godot-ai tooling so the file stays canonical.
- Never commit `.godot/`, `*.import` files are committed (they carry import settings),
  never commit exported builds.
- Ask the owner before: adding an addon, changing resolution, changing renderer,
  adding an autoload, adding a color to the palette, bumping the engine.

## 11. Commands

```bash
# Import resources (needed once after a fresh clone, and after adding assets)
godot --headless --path . --import

# Parse-check one script (no running)
godot --headless --path . --check-only --script res://scripts/autoload/clock.gd

# Whole project validation: scene load, display settings, typing lint, palette
godot --headless --path . --script res://tests/run_checks.gd

# Run the game
godot --path .
```
Exit code 0 = all good. Any non-zero = fix before continuing.

## 12. Git rules

- Branch `godot-basis` is a **reference starting point**. Never use it for a general
  instruction such as "merge everything". Only touch it when the owner names it
  explicitly. (Dutch original above is authoritative.)
- Work on feature branches named `m1/<short-task>`, `fix/<short-thing>`,
  `art/<asset>`. Never commit straight to the default branch.
- Small commits, one idea each. Message: imperative, lower-case start OK,
  under 72 chars on the first line. Body explains why when it is not obvious.
- Do not rewrite shared history. No force-push to shared branches.
- Do not commit: `.godot/`, `*.tmp`, exported builds, OS junk, large source PSDs.
- Commit art source (`.aseprite`/`.pixelorama`) in `art/_src/` only if under 1 MB each.
- Run `tests/run_checks.gd` before every push. CI runs the same script.
- Do not open, merge or close pull requests unless asked.
- Never skip hooks, never `--no-verify`.

## 13. Extra verboden patronen (uit docs/research)

- Geen `Manager`/`Director`/`Router`-klassen voor wat een kind-node kan doen; maximaal vier autoloads (zie `docs/PLAN_VAN_AANPAK.md` §2.4 voor de open autoload-beslissing).
- Geen `AudioServer.get_meta`-constructies of per-frame `AudioStreamGenerator`-allocaties (AGENT_05 bekende fout); gebruik per-bus `AudioEffectAmplify`-trim.
- Geen echte historische claims in-game zonder `[Verify]`-bron (AGENT_09); seinvlaggen gebruiken de fictieve "Island Code".
- Geen shader die buiten de pixelgrid rendert (geen Gaussische blur); geen `CanvasModulate`-aanname zonder test op `unshaded` items (AGENT_04).
- Geen werk buiten de huidige milestone-scope; zie `docs/TASKS.md` voor de claimbare backlog.

## 14. Verwijzingen

- Plan van aanpak: `docs/PLAN_VAN_AANPAK.md` · Taken: `docs/TASKS.md` · Onderzoek: `docs/research/INDEX.md`.

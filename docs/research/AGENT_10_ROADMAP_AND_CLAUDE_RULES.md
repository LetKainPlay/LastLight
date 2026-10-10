# AGENT 10 - Roadmap, CLAUDE.md Rules and Automated Validation

Project: **Last Light** (working title in `project.godot`: "Het Laatste Licht")
Engine: Godot 4.7.2, GDScript 2.0, GL Compatibility renderer
Scope of this document: (A) the production CLAUDE.md, (B) Milestone 1 spec and later milestones, (C) headless validation and CI.

Sibling research docs (read them for domain depth, nothing here depends on them):
`AGENT_01` sensory, `AGENT_02` progression, `AGENT_03` pixel art, `AGENT_04` shaders, `AGENT_05` audio, `AGENT_06` time/weather, `AGENT_07` camera/controller, `AGENT_08` lighthouse mechanics, `AGENT_09` nautical/UI.

---

## 0. Findings from the repo audit (read first)

State of `/home/claude/lastlight` when this doc was written:

| Item | Found | Verdict |
|---|---|---|
| `CLAUDE.md` | Dutch, 2 rules (godot-basis, engine version) | Keep both rules **verbatim**; extend around them |
| `project.godot` viewport | **320x180**, window override 1280x720 | **Conflicts with the 640x360 mandate.** Task M1-T00 fixes it. Window override 1280x720 is then exactly 2x. |
| Stretch | `canvas_items`, aspect `keep`, scale_mode `integer` | Correct for pixel-perfect. Keep. |
| Texture filter | `default_texture_filter=0` (Nearest) | Correct. Keep. |
| Renderer | `gl_compatibility` | Correct (web + low-end friendly). Keep. |
| `scenes/main.tscn` | One empty `Node2D` named `Main` | Fine. It becomes the thin bootstrap scene. |
| Folders | only `scenes/`, `docs/` | Layout in section A.4 is proposed, not yet present |
| `godot` binary on this box | not installed | Validation commands below are written to be run where Godot exists (dev machine, CI) |

Two decisions this doc makes that the owner should confirm once:

1. **Internal resolution is 640x360** (16:9, scales 2x to 1280x720, 3x to 1920x1080, 4x to 2560x1440). 320x180 is rejected: too coarse for "cozy high-detail".
2. **Language of docs**: CLAUDE.md keeps the two original Dutch rules verbatim; everything new is English so every agent and CI log is readable. The game's working title stays as the owner set it until told otherwise.

---

# PART A - Production CLAUDE.md

Copy the block below to `/home/claude/lastlight/CLAUDE.md`. The outer fence uses four backticks because the file contains its own code fences.

````markdown
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
````

---

# PART B - Milestone 1: Playable Vertical Slice

## B.1 One-sentence goal

> A player walks the Keeper's Quarters, climbs to the Lantern Room, and keeps the flame alive through one full night from dusk to dawn, ending on a quiet sunrise.

It must feel finished at 640x360: lit, animated, sounded, tuned. A slice that is small and warm beats a large one that is grey.

## B.2 Scope lock

**In scope (exactly these):**

1. **Keeper's Quarters** room (ground-floor living space): bed, stove, table with logbook, oil barrel / supply shelf, door/stair to the lantern room. One lived-in, hand-lit room.
2. **Lantern Room** (top of tower): lens, flame, oil reservoir, wick, windows to the sea, ladder/stairs down.
3. **Player controller**: 8-direction or side-walk (decision recorded in `DECISIONS.md` from AGENT_07), pixel-snapped, interact key.
4. **Night clock**: one night, dusk (18:00) to dawn (06:00 game time), compressed to **12 real minutes** by default (`1 game minute = 1 real second`). Tunable.
5. **Flame loop**: oil drains slowly, wick grows crusty, player refills oil and trims wick. Flame brightness is the one meter and is *shown by the world*, not a HUD bar.
6. **Light**: the lantern lights the room with a stepped, palette-locked, flickering light; a beam sweeps the sea (simple rotating beam, no ship AI).
7. **Time-of-night mood**: dusk -> deep night -> pre-dawn -> sunrise colour grade through sky/window tint. (Weather beyond clear + light fog is out.)
8. **Audio**: ambient sea, wind, flame crackle, footsteps, interaction sounds, one calm music loop. Placeholder-quality is acceptable if licensed/recorded cleanly; silence must never be broken by clicks.
9. **Minimal UI**: interact prompt (small pixel glyph near the object), a pause menu, a title card, and a "night complete" card. Logbook is readable text, diegetic.
10. **Save**: only "night completed" flag plus settings (volume). Local JSON.
11. **Validation**: `tests/run_checks.gd` + CI green.

**Out of scope for Milestone 1 (do not build, do not stub, do not "prepare for"):**

- Any room other than the two above (no cellar, boathouse, island exterior, dock, garden)
- Ships, ship AI, signalling, rescues, radio/telegraph gameplay
- Weather system beyond fixed "clear with light fog"; no storms, rain, lightning
- Seasons, multi-day calendar, day phase gameplay
- Crafting, cooking, inventory screens, shopping, money
- Upgrades, progression trees, unlocks (AGENT_02 content)
- Dialogue trees, NPC characters, relationships
- Procedural anything
- Controller remapping UI, localisation, accessibility menus beyond volume + a text-size toggle (log as M2)
- Achievements, stats screens, analytics
- Mobile/web builds, store pages, trailers
- Any game-over or fail state

If someone asks for an out-of-scope item: reply "Out of scope for M1", add a line to `docs/MILESTONES.md` backlog, continue.

## B.3 Gameplay spec for the one night

Flame has four named states (`FlameState`): `OUT`, `EMBER`, `STEADY`, `BRIGHT`.

| Quantity | Default | Notes |
|---|---|---|
| Night length | 720 real seconds | 12 min; dusk 18:00 -> dawn 06:00 |
| Oil capacity | 1.0 | one full reservoir lasts ~ 150 s unattended at the start |
| Oil drain | 0.0065 / s | grows 20 % in the deep-night window (00:00-04:00) |
| Wick wear | 0 -> 1 over ~ 240 s | wear above 0.6 reduces brightness 15 %, adds flicker |
| Refill | hold interact 2.0 s at oil barrel to fill a can, 1.5 s at reservoir to pour | no instant refill; the carry is the cozy beat |
| Trim wick | 1.2 s interact, resets wear | tiny snip sound and a spark |
| Brightness | `oil_factor * (1 - 0.15 * wear_over_threshold)` | maps to the four states |
| Relight | match from the quarters table, 1.0 s | only when `OUT`; no penalty beyond darkness |
| Barrel stock | 4 refills over the night | enough to be comfortable; not a scarcity puzzle |

Cozy contract: the flame can reach `OUT`, the room goes dark and blue, the sea sounds louder, the cat/lamp in the quarters keeps a small glow, and the player relights. Nothing is lost, nothing is scored. The sunrise card tells a line about the night, e.g. "The light burned 11 hours 40 minutes." That sentence is the only number the player ever sees.

Rhythm of the night (target): about 5 maintenance moments, each 20-40 s, separated by 90-120 s of breathing room (walk, look at the sea, read the logbook, sit by the stove). The player should have time to be there.

## B.4 Acceptance criteria

Every criterion is testable. `[A]` = automated by `tests/run_checks.gd` or a test script, `[M]` = manual playtest checklist.

**Display and technical**
- AC-01 [A] `project.godot` has viewport 640x360, window override 1280x720, stretch canvas_items / keep / integer, Nearest default filter, gl_compatibility.
- AC-02 [A] Every `.tscn` under `res://scenes` loads and instantiates headless with no error.
- AC-03 [A] No untyped `var`, parameter or missing return type in any first-party `.gd`.
- AC-04 [A] Every opaque pixel of every PNG under `res://art` is in `lastlight.hex`.
- AC-05 [M] At 1280x720 and 1920x1080 the image is crisp: no shimmer when the player or camera moves, no seam lines between tiles.
- AC-06 [M] Resizing the window to a non-integer multiple letterboxes cleanly (no blur, no stretch).
- AC-07 [M] Stable 60 FPS on integrated GPU laptop in the lantern room with full light FX; frame time under 8 ms on the dev machine.
- AC-08 [A] A 15-minute headless soak (`--quit-after`) of the night scene finishes with no errors or warnings in the log.

**Flow**
- AC-09 [M] Title card -> press any key -> player in the quarters at dusk within 3 s.
- AC-10 [M] Player can reach the Lantern Room and return, any number of times, without a loading screen longer than a 400 ms fade.
- AC-11 [M] The full night, played naturally, takes 11-14 real minutes and ends with the sunrise card.
- AC-12 [M] Quitting from pause and restarting works; completed-night flag persists.
- AC-13 [A] Clock emits `night_ended` exactly once, at 06:00, even if the player pauses/unpauses repeatedly.

**Flame loop**
- AC-14 [A] Oil never goes below 0 or above capacity; flame state is a pure function of oil and wick wear (unit test with table of inputs).
- AC-15 [M] The player can read the flame's health from the world only (light radius, colour, flicker, lens glow, sound) with the HUD hidden.
- AC-16 [M] A first-time player who ignores the flame for 3 minutes reaches `EMBER`, sees/hears it, and recovers without frustration or reading anything.
- AC-17 [M] A playtester who does everything perfectly is never bored: at least 3 optional lingering things (window view, logbook entries, stove warmth/sound, a small animal or ship light far away as purely ambient background).
- AC-18 [M] `OUT` is recoverable in under 30 s from anywhere in the tower.

**Sensory and mood** (see AGENT_01)
- AC-19 [M] Dusk, midnight, pre-dawn, sunrise are each recognisable from a screenshot alone.
- AC-20 [M] Flame crackle, sea, wind, footsteps are mixed so the music can be muted without losing the mood.
- AC-21 [M] Every interaction has: prompt, motion, sound, and a visible result.
- AC-22 [M] Palette audit: screenshot colours all come from the master palette (shader outputs included, or gradient steps stay inside it).

**Cozy / anti-enterprise**
- AC-23 [M] No red UI, no numbers, no failure messages on screen during the whole night.
- AC-24 [A] Autoload count <= 4; no `*Manager` class names (grep check in `run_checks.gd`).
- AC-25 [M] A friend with no briefing gets through the first 5 minutes without asking what to do.

## B.5 Task breakdown, order and dependencies

Legend: `dep:` = must be finished first. Each task ends with `run_checks.gd` green. Estimates are focused dev-days for one person plus one AI agent; adjust freely. Owner column is a hint, not bureaucracy.

### Wave 0 - Foundation (1-2 days)

| ID | Task | dep | Done when |
|---|---|---|---|
| M1-T00 | Fix `project.godot`: viewport 640x360, window 1280x720, snap-2d settings, typing warnings, named physics layers, input actions (`move_*`, `interact`, `pause`) | - | AC-01 green |
| M1-T01 | Create folder layout (section A.8), palette file stub (16 colors to start), `docs/DECISIONS.md`, `docs/SIGNALS.md`, `docs/MILESTONES.md` | T00 | folders exist, committed |
| M1-T02 | Add `tests/run_checks.gd` and `.github/workflows/ci.yml` (Part C) | T00, T01 | CI green on an empty project |
| M1-T03 | `Debug` autoload: F1 overlay (fps, time, flame), time scale hotkeys, `--night-speed` cmdline flag. Stripped by `OS.is_debug_build()` | T00 | overlay toggles |

### Wave 1 - Core systems (3-4 days)

| ID | Task | dep | Done when |
|---|---|---|---|
| M1-T04 | `Clock` autoload: dusk -> dawn, `time_changed(minutes)`, `phase_changed(phase)`, `night_ended`; pause-safe | T00 | AC-13 test passes |
| M1-T05 | `Game` autoload: JSON save (night_completed, volume), settings | T01 | save round-trips |
| M1-T06 | `Pixel` helper (`snap(Vector2) -> Vector2i`) and camera snapping rule (AGENT_07) | T00 | unit test |
| M1-T07 | Player scene: movement with subpixel accumulator, collision, 4-direction facing, placeholder sprite, footstep signal | T06 | walks a test room, no shimmer |
| M1-T08 | `Interactable` base scene (`Area2D`): prompt glyph, `interacted(who)` signal, hold-to-complete support | T07 | demo object works |
| M1-T09 | `FlameModel` (`Resource`/`RefCounted`): oil, wick wear, `FlameState` as pure function, `LanternTuning` resource | T01 | AC-14 test passes |

### Wave 2 - Rooms and objects (4-6 days)

| ID | Task | dep | Done when |
|---|---|---|---|
| M1-T10 | Tileset + greybox rooms (Keeper's Quarters, Lantern Room) with collision, doors/stairs trigger, fade transition | T07, T08 | can walk between rooms |
| M1-T11 | Lantern scene: lens, flame sprite, reservoir, wick; reads `FlameModel`; emits `flame_state_changed` | T09, T10 | flame states visible |
| M1-T12 | Interactions: oil barrel -> can -> reservoir pour; wick trim; match relight | T08, T11 | full refill loop playable |
| M1-T13 | Quarters props: stove, bed (sit/sleep cosmetic only), table + logbook (readable text), window | T10, T08 | each prop has an interaction or ambience |
| M1-T14 | Night orchestration in `main.tscn`: loads rooms, wires `Clock` -> sky tint, start/end flow, title and sunrise cards | T04, T10, T11 | start-to-finish playable (greybox) |

### Wave 3 - Look and feel (5-8 days, can overlap Wave 2 after T10)

| ID | Task | dep | Done when |
|---|---|---|---|
| M1-T15 | Final pixel art pass: rooms, props, player, lantern, animation sheets, all palette-locked (AGENT_03) | T10 | AC-04 green |
| M1-T16 | Lighting: stepped light overlay on layer 10, flame flicker, rotating beam, window tint by phase (AGENT_04) | T11, T14 | AC-15, AC-19 |
| M1-T17 | Audio: buses (Master/Music/Sfx/Ambience), ambience layers, interaction sfx, footsteps by floor, music loop (AGENT_05) | T12, T13 | AC-20 |
| M1-T18 | Minimal UI: prompt glyph art, pause menu, title and sunrise cards in pixel font (AGENT_09) | T14 | AC-09, AC-23 |
| M1-T19 | Sky/sea/window view and fog layer through the night (AGENT_06) | T14 | AC-19 |

### Wave 4 - Tune and ship the slice (3-4 days)

| ID | Task | dep | Done when |
|---|---|---|---|
| M1-T20 | Tuning pass: drain, wear, timings, rhythm of the night; log findings in `DECISIONS.md` | T12, T16, T17 | AC-11, AC-16, AC-18 |
| M1-T21 | Polish pass: one micro-delight per interaction (steam, dust motes, cat, moth around the flame) | T20 | AC-17, AC-21 |
| M1-T22 | Soak test + perf pass: 15 min headless run, profile lantern room | T20 | AC-07, AC-08 |
| M1-T23 | Playtest with 3 people, fix top 5 pain points | T21 | AC-25 |
| M1-T24 | Build export (desktop), tag `m1`, write `docs/MILESTONES.md` retro | T22, T23 | DoD met |

Critical path: T00 -> T01 -> T07 -> T08 -> T10 -> T11 -> T12 -> T14 -> T16/T17 -> T20 -> T22 -> T24.
Parallelisable: T04/T05/T06/T09 after T00; T15 art after greybox T10; T17 audio can start with placeholder streams at T08.

Suggested order if working alone: finish Wave 0, then go straight through one thin playable loop at greybox quality (T04-T14) **before** doing any final art. A greybox night that is fun is worth more than three pretty rooms.

## B.6 Definition of Done (Milestone 1)

All of the following, no exceptions:

1. Every acceptance criterion in B.4 is met (`[A]` green in CI, `[M]` signed off in a playtest note in `docs/MILESTONES.md`).
2. `godot --headless --path . --script res://tests/run_checks.gd` exits 0 on the release commit; CI is green.
3. A fresh clone plus `godot --headless --import` plus run works first try on Linux, Windows and macOS (at least one of each verified, two by CI import-only is acceptable).
4. Three people who have never seen the game played the whole night; their notes are summarised in one paragraph.
5. `CLAUDE.md` still matches reality (folder layout, autoload list) and the anti-pattern checklist has been run against the final diff.
6. No `TODO` without an owner/date; no commented-out code; no placeholder art left in the final two rooms.
7. A 60-second capture (GIF or MP4) at native 2x/3x integer scale exists for the team to show.
8. Backlog items found along the way are written down; scope was not widened.

## B.7 Risks and cheap mitigations

| Risk | Mitigation |
|---|---|
| Pixel shimmer from float camera | Snap camera in T06; test at scale 3x on day one |
| Palette drift from AI-generated or hand-picked colours | CI palette check (Part C); adding a color = its own commit |
| Light FX break pixel grid | Stepped light via palette ramp + dither texture (AGENT_04), never a Gaussian blur |
| Loop feels like chores | Tune in T20 using the "5 moments / breathing room" target; cut a step before adding a reward |
| Scope creep ("just a quick ship") | Out-of-scope list is binding; add to backlog and move on |
| 12 min feels too long or short | `Clock` takes length from tuning; playtest picks the number |
| Dutch/English confusion | Rules stay Dutch where original; all new text English; names of in-game text decided in M2 localisation |

## B.8 Later milestones (outline only, no commitments)

| M | Name | Core idea | Gate to enter |
|---|---|---|---|
| M2 | The Island Wakes | Day cycle and island exterior: walk outside, dock, garden bed, tool shed; day tasks (collect driftwood, buy/restock oil via supply boat). Accessibility basics, key remapping, localisation scaffolding (NL/EN). | M1 DoD |
| M3 | Ships in the Dark | First ships pass; signalling with the beam and horn; calm, non-punishing "they thank you" feedback; radio/telegraph diegetic UI (AGENT_09). | M2 |
| M4 | Weather and Seasons | Rain, fog, storms, seasonal light and island change (AGENT_06). Storm nights raise tension softly; flame and tower creak. | M3 |
| M5 | Keeper's Life | Progression and upgrades (AGENT_02): lens polish, bigger reservoir, comforts, visitors, letters, the logbook as memory. | M4 |
| M6 | Finish | Full music, polish, controller support, perf on low-end, Steam Deck check, store art, trailer. | M5 |

Each milestone gets its own scope-lock section in `docs/MILESTONES.md` before work starts, written in the same shape as B.2 to B.6. Rule of thumb: a milestone is 3 to 6 weeks and ends with something playable that is a little more of the same warm thing.

---

# PART C - Automated validation

## C.1 Commands

Where `godot` is the 4.7.2 binary (`Godot_v4.7.2-stable_linux.x86_64`, symlinked as `godot`).

```bash
# 1. First-time / after asset changes: build the import cache (creates .godot/)
godot --headless --path . --import

# 2. Parse-check a single script without running it
godot --headless --path . --check-only --script res://scripts/autoload/clock.gd

# 3. Parse-check every first-party script (exit 1 on first failure)
find scripts scenes tests -name '*.gd' -print0 |
  xargs -0 -n1 -I{} godot --headless --path . --check-only --script res://{}

# 4. The project check suite (scene load, display, typing lint, palette, naming)
godot --headless --path . --script res://tests/run_checks.gd

# 5. Soak: boot the main scene headless for N frames (60 fps -> 54000 = 15 min)
godot --headless --path . --quit-after 54000 res://scenes/main.tscn

# 6. Run a single unit-test script
godot --headless --path . --script res://tests/test_flame_model.gd
```

Notes
- `--check-only` needs `--script`; it only parses. Scripts that reference autoload names parse fine as long as the project is loaded with `--path .`.
- If `--check-only` complains about a script that references `class_name` types from files not yet imported, run step 1 first.
- A script run with `--script` that `extends SceneTree` must call `quit(code)` itself. Exit code is what CI reads.
- `run_checks.gd` prints one line per check: `PASS name` / `FAIL name: reason`, then a summary. Greppable and short.
- Soak step 5 relies on the Debug autoload accepting `--night-speed=10` to compress the night in CI. Without it, 15 simulated minutes at real speed is too slow; use `--night-speed=20`.

## C.2 `tests/run_checks.gd`

Drop-in file. Self-contained, fully typed (it lints itself), no addons.

```gdscript
extends SceneTree
## Headless project checks for Last Light.
## Run: godot --headless --path . --script res://tests/run_checks.gd
## Exit code 0 = all checks passed, 1 = at least one failure.

const EXPECTED_VIEWPORT: Vector2i = Vector2i(640, 360)
const EXPECTED_WINDOW: Vector2i = Vector2i(1280, 720)
const PALETTE_PATH: String = "res://art/palette/lastlight.hex"
const MAX_PALETTE_COLORS: int = 32
const MAX_AUTOLOADS: int = 4
const SCAN_ROOTS: Array[String] = ["res://scenes", "res://scripts", "res://tests", "res://scenes"]
const SKIP_DIRS: Array[String] = ["res://addons", "res://.godot", "res://docs"]
const LINT_IGNORE_TAG: String = "# lint-ignore"
const FORBIDDEN_CLASS_SUFFIXES: Array[String] = ["Manager", "Handler", "Provider", "Factory"]

var _failures: int = 0
var _passes: int = 0
var _warnings: int = 0


func _init() -> void:
	print("== Last Light checks (Godot %s) ==" % Engine.get_version_info()["string"])
	_check_display_settings()
	_check_scene_loads()
	_check_typing_lint()
	_check_naming()
	_check_autoloads()
	_check_palette()
	print("== %d passed, %d failed, %d warnings ==" % [_passes, _failures, _warnings])
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- reporting

func _pass(check: String) -> void:
	_passes += 1
	print("PASS %s" % check)


func _fail(check: String, reason: String) -> void:
	_failures += 1
	printerr("FAIL %s: %s" % [check, reason])


func _warn(check: String, reason: String) -> void:
	_warnings += 1
	print("WARN %s: %s" % [check, reason])


# ---------------------------------------------------------------- file helpers

func _collect_files(root: String, extension: String, out: Array[String]) -> void:
	if root in SKIP_DIRS:
		return
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path: String = root.path_join(entry)
			if dir.current_is_dir():
				_collect_files(path, extension, out)
			elif path.get_extension() == extension and path not in out:
				out.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


func _files_under(roots: Array[String], extension: String) -> Array[String]:
	var out: Array[String] = []
	for root: String in roots:
		_collect_files(root, extension, out)
	out.sort()
	return out


# ---------------------------------------------------------------- 1. display

func _check_display_settings() -> void:
	var name: String = "display"
	var problems: Array[String] = []

	var vp: Vector2i = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)))
	if vp != EXPECTED_VIEWPORT:
		problems.append("viewport is %s, expected %s" % [vp, EXPECTED_VIEWPORT])

	var win: Vector2i = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)))
	if win != EXPECTED_WINDOW:
		problems.append("window override is %s, expected %s" % [win, EXPECTED_WINDOW])
	elif win.x % vp.x != 0 or win.y % vp.y != 0:
		problems.append("window override %s is not an integer multiple of viewport" % win)

	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	if mode != "canvas_items":
		problems.append("stretch mode is '%s', expected 'canvas_items'" % mode)

	var aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	if aspect != "keep":
		problems.append("stretch aspect is '%s', expected 'keep'" % aspect)

	var scale_mode: String = str(ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	if scale_mode != "integer":
		problems.append("stretch scale_mode is '%s', expected 'integer'" % scale_mode)

	var filter: int = int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", -1))
	if filter != 0:
		problems.append("default_texture_filter is %d, expected 0 (Nearest)" % filter)

	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	if renderer != "gl_compatibility":
		problems.append("renderer is '%s', expected 'gl_compatibility'" % renderer)

	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene == "" or not ResourceLoader.exists(main_scene):
		problems.append("main scene '%s' missing" % main_scene)

	# Recommended, warn only (the editor may not have written them yet).
	if not bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)):
		_warn(name, "rendering/2d/snap/snap_2d_transforms_to_pixel is off")
	if int(ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration", 0)) < 2:
		_warn(name, "debug/gdscript/warnings/untyped_declaration is not set to Error (2)")

	if problems.is_empty():
		_pass(name)
	else:
		for p: String in problems:
			_fail(name, p)


# ---------------------------------------------------------------- 2. scene load

func _check_scene_loads() -> void:
	var scenes: Array[String] = _files_under(["res://scenes"], "tscn")
	if scenes.is_empty():
		_fail("scene_load", "no .tscn files found under res://scenes")
		return
	var bad: int = 0
	for path: String in scenes:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_fail("scene_load", "%s did not load as PackedScene" % path)
			bad += 1
			continue
		if not packed.can_instantiate():
			_fail("scene_load", "%s cannot instantiate" % path)
			bad += 1
			continue
		var node: Node = packed.instantiate()
		if node == null:
			_fail("scene_load", "%s instantiate() returned null" % path)
			bad += 1
			continue
		node.free()
	if bad == 0:
		_pass("scene_load (%d scenes)" % scenes.size())


# ---------------------------------------------------------------- 3. typing lint

# var x = 1          -> untyped
# var x := 1         -> ok
# var x: int = 1     -> ok
# var x: int         -> ok
var _re_var: RegEx = null
var _re_func: RegEx = null
var _re_for: RegEx = null


func _compile_regexes() -> void:
	_re_var = RegEx.new()
	_re_var.compile("^\\s*(?:@\\w+(?:\\([^)]*\\))?\\s+)*(?:static\\s+)?var\\s+(\\w+)\\s*(=|$)")
	_re_func = RegEx.new()
	_re_func.compile("^\\s*(?:static\\s+)?func\\s+(\\w+)\\s*\\((.*)\\)\\s*(->\\s*[\\w\\.\\[\\], ]+)?\\s*:")
	_re_for = RegEx.new()
	_re_for.compile("^\\s*for\\s+(\\w+)\\s+in\\s")


func _check_typing_lint() -> void:
	_compile_regexes()
	var scripts: Array[String] = _files_under(["res://scenes", "res://scripts", "res://tests"], "gd")
	var issues: int = 0
	for path: String in scripts:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		for i: int in lines.size():
			var line: String = lines[i]
			if line.contains(LINT_IGNORE_TAG):
				continue
			var code: String = _strip_comment(line)
			if code.strip_edges() == "":
				continue
			var problem: String = _lint_line(code)
			if problem != "":
				issues += 1
				_fail("typing", "%s:%d %s | %s" % [path, i + 1, problem, line.strip_edges()])
	if issues == 0:
		_pass("typing (%d scripts)" % scripts.size())


func _strip_comment(line: String) -> String:
	# Good enough: ignores '#' inside quotes by walking the string.
	var in_quote: String = ""
	for i: int in line.length():
		var c: String = line[i]
		if in_quote != "":
			if c == in_quote and (i == 0 or line[i - 1] != "\\"):
				in_quote = ""
		elif c == "\"" or c == "'":
			in_quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func _lint_line(code: String) -> String:
	var m: RegExMatch = _re_var.search(code)
	if m != null:
		# 'var x = ...' or bare 'var x'  -> no ':' type
		return "untyped var '%s' (use 'var %s: Type' or ':=' with obvious type)" % [m.get_string(1), m.get_string(1)]

	m = _re_func.search(code)
	if m != null:
		var fname: String = m.get_string(1)
		if m.get_string(3) == "":
			return "func '%s' missing '-> ReturnType'" % fname
		var params: String = m.get_string(2).strip_edges()
		if params != "":
			for p: String in _split_params(params):
				var pn: String = p.strip_edges()
				if pn == "" or pn.begins_with("..."):
					continue
				if not pn.contains(":"):
					return "func '%s' parameter '%s' has no type" % [fname, pn]
	return ""


func _split_params(params: String) -> PackedStringArray:
	# Split on commas that are not inside (), [], {}.
	var out: PackedStringArray = PackedStringArray()
	var depth: int = 0
	var current: String = ""
	for ch: String in params:
		if ch == "(" or ch == "[" or ch == "{":
			depth += 1
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(current)
			current = ""
		else:
			current += ch
	if current != "":
		out.append(current)
	return out


# ---------------------------------------------------------------- 4. naming

func _check_naming() -> void:
	var problems: int = 0
	var all_files: Array[String] = []
	for ext: String in ["gd", "tscn", "tres", "gdshader", "png", "ogg", "wav"]:
		all_files.append_array(_files_under(["res://scenes", "res://scripts", "res://resources", "res://art", "res://audio", "res://shaders", "res://tests"], ext))
	for path: String in all_files:
		var base: String = path.get_file().get_basename()
		if base != base.to_snake_case() and not base.begins_with("_"):
			_fail("naming", "%s is not snake_case" % path)
			problems += 1

	for path: String in _files_under(["res://scenes", "res://scripts"], "gd"):
		var text: String = FileAccess.get_file_as_string(path)
		for line: String in text.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("class_name "):
				var cname: String = t.trim_prefix("class_name ").split(" ")[0]
				for suffix: String in FORBIDDEN_CLASS_SUFFIXES:
					if cname.ends_with(suffix):
						_fail("naming", "%s: class_name '%s' ends with '%s' (see CLAUDE.md section 7)" % [path, cname, suffix])
						problems += 1
	if problems == 0:
		_pass("naming")


# ---------------------------------------------------------------- 5. autoloads

func _check_autoloads() -> void:
	var count: int = 0
	for prop: Dictionary in ProjectSettings.get_property_list():
		var pname: String = str(prop["name"])
		if pname.begins_with("autoload/"):
			count += 1
	if count > MAX_AUTOLOADS:
		_fail("autoloads", "%d autoloads, max is %d" % [count, MAX_AUTOLOADS])
	else:
		_pass("autoloads (%d)" % count)


# ---------------------------------------------------------------- 6. palette

func _load_palette() -> Dictionary:
	# Returns { Color8-packed int : true }
	var palette: Dictionary = {}
	if not FileAccess.file_exists(PALETTE_PATH):
		return palette
	var text: String = FileAccess.get_file_as_string(PALETTE_PATH)
	for raw: String in text.split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("#") and line.length() != 7:
			continue
		if not line.begins_with("#"):
			line = "#" + line
		if line.length() != 7 or not line.substr(1).is_valid_hex_number():
			continue
		var col: Color = Color.html(line)
		palette[_pack(col.r8, col.g8, col.b8)] = true
	return palette


func _pack(r: int, g: int, b: int) -> int:
	return (r << 16) | (g << 8) | b


func _check_palette() -> void:
	var pngs: Array[String] = _files_under(["res://art"], "png")
	if not FileAccess.file_exists(PALETTE_PATH):
		_fail("palette", "%s missing" % PALETTE_PATH)
		return
	var palette: Dictionary = _load_palette()
	if palette.is_empty():
		_fail("palette", "%s has no valid colors" % PALETTE_PATH)
		return
	if palette.size() > MAX_PALETTE_COLORS:
		_fail("palette", "%d colors, max is %d" % [palette.size(), MAX_PALETTE_COLORS])
		return
	if pngs.is_empty():
		_warn("palette", "no PNGs under res://art yet; palette file only checked")
		_pass("palette (%d colors, no art yet)" % palette.size())
		return

	var bad_files: int = 0
	for path: String in pngs:
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			_fail("palette", "%s could not be read" % path)
			bad_files += 1
			continue
		img.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = img.get_data()
		var offenders: Dictionary = {}
		var i: int = 0
		var n: int = data.size()
		while i < n:
			if data[i + 3] != 0:
				if data[i + 3] != 255:
					offenders["semi-transparent pixel"] = true
				var key: int = _pack(data[i], data[i + 1], data[i + 2])
				if not palette.has(key):
					offenders["#%06x" % key] = true
			i += 4
		if not offenders.is_empty():
			bad_files += 1
			var shown: Array[String] = []
			for k: String in offenders.keys():
				shown.append(k)
				if shown.size() >= 5:
					break
			_fail("palette", "%s uses colors outside palette: %s%s" % [
				path, ", ".join(shown), " ..." if offenders.size() > 5 else ""])
	if bad_files == 0:
		_pass("palette (%d PNGs, %d colors)" % [pngs.size(), palette.size()])
```

Behaviour notes
- It lints itself: it has no untyped declarations. Keep it that way; CI will tell you.
- Regex limits: multiline `func` signatures (parameters on several lines) are not parsed by the single-line regex. Convention: keep signatures on one line, or end the line with `# lint-ignore`.
- `for x in y` loops are allowed untyped by the lint (the engine infers them); prefer typed (`for item: Node2D in items`) per CLAUDE.md. `_re_for` is compiled for a stricter variant: flip `_lint_line` to flag it when the codebase is clean.
- Semi-transparent pixels are flagged: pixel art uses alpha 0 or 255 only (soft shadows are palette colours, dithered or stepped).
- The PNG path uses `Image.load_from_file` on the globalised path, so it reads source files, not the imported `.ctex` (works without `--import`).
- Scene load check instantiates but does not enter the tree. It catches missing sub-resources, broken script paths and bad ext_resources. It does not run `_ready()`; the soak test (C.1 step 5) does that.
- Known rough edge: `class_name` scripts that depend on autoload names can fail to compile inside `--script` mode before autoloads exist. If this happens, the scene_load check will report it clearly; the fix is `Engine.get_singleton`-free code (reference autoloads by name only inside functions, not in top-level `const`/type hints) or running the check with the editor's `--headless --editor --quit` first.

## C.3 Example unit test (pattern for `tests/test_*.gd`)

Keep tests tiny and dependency-free. One file per system, an `_init()` that asserts and quits.

```gdscript
extends SceneTree
## Headless test for FlameModel. Run:
## godot --headless --path . --script res://tests/test_flame_model.gd

var _failed: bool = false


func _init() -> void:
	_check_state(0.0, 0.0, FlameModel.FlameState.OUT)
	_check_state(0.05, 0.0, FlameModel.FlameState.EMBER)
	_check_state(0.5, 0.0, FlameModel.FlameState.STEADY)
	_check_state(1.0, 0.0, FlameModel.FlameState.BRIGHT)
	_check_state(1.0, 1.0, FlameModel.FlameState.STEADY)  # worn wick dims a full tank
	_check_clamped()
	quit(1 if _failed else 0)


func _check_state(oil: float, wear: float, expected: FlameModel.FlameState) -> void:
	var model: FlameModel = FlameModel.new()
	model.oil = oil
	model.wick_wear = wear
	var actual: FlameModel.FlameState = model.get_state()
	if actual != expected:
		_failed = true
		printerr("FAIL oil=%s wear=%s expected %s got %s" % [oil, wear, expected, actual])
	else:
		print("PASS oil=%s wear=%s" % [oil, wear])


func _check_clamped() -> void:
	var model: FlameModel = FlameModel.new()
	model.add_oil(5.0)
	if model.oil > 1.0:
		_failed = true
		printerr("FAIL oil exceeded capacity: %s" % model.oil)
	model.burn(9999.0)
	if model.oil < 0.0:
		_failed = true
		printerr("FAIL oil went negative: %s" % model.oil)
```

Chain all tests in CI with:
```bash
for t in tests/test_*.gd; do godot --headless --path . --script "res://$t" || exit 1; done
```

## C.4 CI workflow

File: `.github/workflows/ci.yml`. Downloads the pinned engine (no third-party action to trust), caches it and the import cache, runs everything in the order: import, parse-check, project checks, tests, smoke boot.

```yaml
name: ci

on:
  push:
    branches: ["**"]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  GODOT_VERSION: "4.7.2"
  GODOT_BIN: ${{ github.workspace }}/.ci/godot

jobs:
  checks:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - name: Cache Godot binary
        id: cache-godot
        uses: actions/cache@v4
        with:
          path: .ci/godot
          key: godot-${{ env.GODOT_VERSION }}-linux-x86_64

      - name: Download Godot
        if: steps.cache-godot.outputs.cache-hit != 'true'
        run: |
          mkdir -p .ci
          curl -fsSL -o .ci/godot.zip \
            "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
          unzip -q .ci/godot.zip -d .ci
          mv ".ci/Godot_v${GODOT_VERSION}-stable_linux.x86_64" .ci/godot
          chmod +x .ci/godot

      - name: Godot version
        run: "$GODOT_BIN --version"

      - name: Cache import data
        uses: actions/cache@v4
        with:
          path: .godot
          key: godot-import-${{ env.GODOT_VERSION }}-${{ hashFiles('**/*.import', 'project.godot') }}
          restore-keys: godot-import-${{ env.GODOT_VERSION }}-

      - name: Import project
        run: |
          # first import can exit non-zero on a benign class cache message; the checks below are authoritative
          "$GODOT_BIN" --headless --path . --import || true

      - name: Parse-check all scripts
        run: |
          status=0
          while IFS= read -r -d '' f; do
            if ! "$GODOT_BIN" --headless --path . --check-only --script "res://$f"; then
              echo "::error file=$f::GDScript parse check failed"
              status=1
            fi
          done < <(find scripts scenes tests -name '*.gd' -print0 2>/dev/null)
          exit $status

      - name: Project checks (scenes, display, typing, palette, naming)
        run: |
          "$GODOT_BIN" --headless --path . --script res://tests/run_checks.gd 2>&1 | tee checks.log
          test "${PIPESTATUS[0]}" -eq 0

      - name: Unit tests
        run: |
          shopt -s nullglob
          for t in tests/test_*.gd; do
            echo "--- $t"
            "$GODOT_BIN" --headless --path . --script "res://$t"
          done

      - name: Smoke boot main scene (300 frames)
        run: |
          "$GODOT_BIN" --headless --path . --quit-after 300 2>&1 | tee boot.log
          ! grep -E "^(ERROR|SCRIPT ERROR|USER ERROR)" boot.log

      - name: Upload logs on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: ci-logs
          path: |
            checks.log
            boot.log
```

Optional second job (add at M1-T22, nightly): the 15-minute soak.

```yaml
  soak:
    if: github.event_name == 'schedule'
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .ci/godot
          key: godot-4.7.2-linux-x86_64
      - name: Soak night at 20x speed
        run: |
          .ci/godot --headless --path . --import || true
          .ci/godot --headless --path . --quit-after 54000 -- --night-speed=20 2>&1 | tee soak.log
          ! grep -E "^(ERROR|SCRIPT ERROR|USER ERROR)" soak.log
```
(add `schedule: - cron: "0 3 * * *"` under `on:` when enabling).

CI notes
- Pinning the version through `GODOT_VERSION` is deliberate: the engine rule in CLAUDE.md is 4.7.2. Bumping the engine is an owner decision and a one-line change here.
- If the release asset name differs for 4.7.2, the Download step fails loudly with `curl -f`; fix the URL, nothing else.
- Local pre-push hook (optional, owner opt-in): `.git/hooks/pre-push` running `godot --headless --path . --script res://tests/run_checks.gd`.

## C.5 Lint rules quick table (what CI catches vs. what review catches)

| Rule | CI | Review |
|---|---|---|
| Viewport 640x360, integer stretch, Nearest | yes | - |
| Untyped var / param / return | yes (line-based) | multi-line signatures |
| `:=` from an unclear source | no | yes |
| Scene loads and instantiates | yes | - |
| Colour in master palette | yes (PNGs) | shader output, runtime-generated colours |
| `*Manager` / `*Handler` class names | yes | spirit of the rule |
| More than 4 autoloads | yes | - |
| snake_case filenames | yes | - |
| `get_parent()` / `../` paths | add grep (below) | yes |
| Fail states, red UI, punishing timers | no | yes (cozy rule) |
| Out-of-scope features | no | yes (milestone scope lock) |

Optional extra grep checks to append to `run_checks.gd` or CI when the codebase is non-empty:

```bash
# fail on climbing the tree
! grep -rnE 'get_parent\(\)\.get_parent\(\)|get_node\("\.\./' scenes scripts
# fail on string-based connect
! grep -rnE '\.connect\("' scenes scripts
# fail on hard-coded window sizes
! grep -rnE '\b(1280|1920)\b.*\b(720|1080)\b' scenes scripts
```

---

## Appendix - One-page first-day checklist for whoever starts M1

1. Replace `CLAUDE.md` with the block in Part A.
2. Fix `project.godot` to 640x360 (M1-T00); everything else in the display check then goes green.
3. Create the folders and an empty 16-colour `art/palette/lastlight.hex`.
4. Add `tests/run_checks.gd` and `.github/workflows/ci.yml`; push a branch `m1/foundation`; see CI green.
5. Build the greybox player walking in a greybox quarters. Stop. Play it. Then continue down the task list.

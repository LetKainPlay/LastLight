# Last Light — Research Index & Technical Roadmap

Godot 4.7.2 · GDScript 2.0 (static typing) · GL Compatibility · 640x360 internal, integer scaling.
Status: **research only, untested.** No spec has been compiled or run in Godot. Each document flags items to verify.

## Documents

| # | File | Scope | Lines |
|---|------|-------|-------|
| 01 | [AGENT_01_SENSORY_AND_ACCESSIBILITY.md](AGENT_01_SENSORY_AND_ACCESSIBILITY.md) | Cozy loop (Dawn/Day/Dusk/Night), accessibility audit, `AccessibilitySettings`, `FlashGovernor`, tactile micro-mechanics (glass wipe, winding, match, kettle) | 1663 |
| 02 | [AGENT_02_DIEGETIC_PROGRESSION.md](AGENT_02_DIEGETIC_PROGRESSION.md) | Narrative, morse, ship encounters, logbook, comfort progression, `SaveData` schema | 1224 |
| 03 | [AGENT_03_PIXEL_ART_AND_PALETTES.md](AGENT_03_PIXEL_ART_AND_PALETTES.md) | Canvas/sprite specs, 48-color master palette, 6 time-of-day remaps, generative prompt matrix, palette validators | 887 |
| 04 | [AGENT_04_SHADERS_LIGHTING_WEATHER.md](AGENT_04_SHADERS_LIGHTING_WEATHER.md) | `fresnel_beam.gdshader`, rain/mist/ocean shaders, day-night grading + LUT, light budget | 1402 |
| 05 | [AGENT_05_AUDIO_ATMOSPHERE.md](AGENT_05_AUDIO_ATMOSPHERE.md) | Procedural ambience, bus layout, tower acoustics, loudness ceilings | 1259 |
| 06 | [AGENT_06_TIME_WEATHER_SYSTEM.md](AGENT_06_TIME_WEATHER_SYSTEM.md) | `TimeManager` (sun/moon/tide), Markov `WeatherSystem`, signals, headless tests | 1315 |
| 07 | [AGENT_07_PIXEL_CAMERA_CONTROLLER.md](AGENT_07_PIXEL_CAMERA_CONTROLLER.md) | Shimmer-free camera/parallax, character controller, faked spiral stairs, scene tiers | 1709 |
| 08 | [AGENT_08_LIGHTHOUSE_MECHANICS.md](AGENT_08_LIGHTHOUSE_MECHANICS.md) | Clockwork, lamp, lens governor, foghorn + echo | 1643 |
| 09 | [AGENT_09_NAUTICAL_AUTHENTICITY_AND_UI.md](AGENT_09_NAUTICAL_AUTHENTICITY_AND_UI.md) | Keeper duties, glossary, diegetic UI (barometer, logbook, telescope) | 1154 |
| 10 | [AGENT_10_ROADMAP_AND_CLAUDE_RULES.md](AGENT_10_ROADMAP_AND_CLAUDE_RULES.md) | Proposed `CLAUDE.md`, Milestone 1 spec (T00–T24), headless checks, CI | 1165 |

## Dependency map

```
03 palette ──► 04 shaders ◄── 06 time/weather ──► 05 audio
   │              │                 │
   ▼              ▼                 ▼
07 camera/view ─► 08 mechanics ─► 01 feel ─► 09 diegetic UI ─► 02 progression
                                    ▲
                  10 rules/roadmap governs all
```

Build order for Milestone 1 (Keeper's Quarters + Lantern Room + one night): 10 (T00 project settings) → 03 → 07 → 06 → 04 → 08 → 05 → 01 → 09 → 02 (minimal logbook only).

## Cross-document decisions to reconcile before coding

1. **Resolution.** `project.godot` is 320x180; target is 640x360. Doc 10 makes this task M1-T00.
2. **Stretch mode conflict.** Docs 03 and 04 require `stretch/mode=viewport` (shaders must run at 640x360). Doc 07 keeps `canvas_items` and renders through four SubViewport bands with sub-pixel remainder shifting. Pick one; this is the first architectural decision.
3. **Autoloads.** Docs add `Settings` (01), `Island` (02), `TimeManager` (06), `DayNight` (04), an `Events` bus (07). This is at odds with the anti-enterprise mandate; consolidate (e.g. fold `DayNight` into a scene node that listens to `TimeManager`).
4. **Shader globals.** Doc 04 needs a `[shader_globals]` block and `res://shaders/common/pixel_common.gdshaderinc`.
5. **Input actions.** `morse_key` (02) and others are not yet in the project.
6. **Tile rows.** 360/16 = 22.5 rows (doc 03); screens need a 22-row layout plus an 8px strip.
7. **Time model.** Docs 01 (pacing presets, "Hold the Hour") and 06 (`TimeManager` pause/scale) overlap; 06 owns the clock.
8. **Audio buses.** Doc 05 layout lacks the Amplify trim slots its own `TowerAcoustics` relies on.
9. **Generic-manager risk.** `ComfortCatalog`, `Island`, `Router` (docs 02, 07) should be reviewed against the anti-enterprise rule.

## Known defects and unverified items (as reported by each agent)

- **01:** length 1663 lines; nothing run in Godot.
- **02:** `RoomDressing._pop_in` dead tween line; `ShipNode._process` no-op `snappedf ... if false`; untested.
- **03:** keeper flip moves the lantern to the other hand; sky ramps sit outside the 48 slots; LUT shader needs index lookup (bake index maps at import is cheaper).
- **04:** unverified `Image.create_empty` in 4.7.2; unconfirmed whether `CanvasModulate` tints `unshaded` items (layer-split workaround given).
- **05:** `TowerAcoustics._user_db` broken (dead `AudioServer.get_meta` branch); mono toggle is partial; verify effect property names and `AudioEffectHardLimiter`.
- **06:** untested; test runner `res://tests/world_tests.gd` not executed.
- **07:** `VERIFY` markers on per-SubViewport pixel snapping, `reset_physics_interpolation()`, `get_global_transform_interpolated()`; no-op `process_callback` line in camera rig; `Router` touches `player._sprite` directly.
- **08:** `clockwork_mechanism.gd` has a messy gear-ratio helper (`GEAR_RATIO_FROM_DRUM_SIGNED`); foghorn acceptance test 10 has a self-correcting sentence.
- **09:** `[Verify]` items on lens terminology and focal distances, IOV burner steps, winding/trim intervals, AccessKit property names, `RichTextLabel` API names, Code of Signals; `A11y.time_phrase` needs a lookup table; unused local in `_nib_position_for`.
- **10:** Godot not available when written; `run_checks.gd` and CI YAML untested; assumed asset name `Godot_v4.7.2-stable_linux.x86_64.zip`; palette check expects `art/palette/lastlight.hex` (created by M1-T01); untyped-var lint skips multi-line signatures.

## Note on the existing CLAUDE.md

The repo `CLAUDE.md` rule about the `godot-basis` branch (use only when named explicitly) is preserved verbatim in the proposal in doc 10. The existing `CLAUDE.md` was **not** modified by this change.

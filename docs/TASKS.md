# TASKS — Last Light

Claimen: zet `[ ]` → `[~] @naam` bij start, `[x]` bij klaar (met commit-hash). Eén taak per branch (`m1/<korte-naam>`). Elke taak eindigt met `godot --headless --path . --script res://tests/run_checks.gd` exit 0. Scope: alleen **M1** tenzij een taak `[M2+]` draagt. Specificaties: `docs/PLAN_VAN_AANPAK.md`, bron-specs in `docs/research/`. Alle spec-code is ongetest: begin elke taak met een parse-check.

Formaat: `ID · taak · dep · bestanden · toets (assert)`.

## Fase 0 — Scaffolding & CI

- [ ] **F0-T00** · `project.godot` afronden (viewport al 640x360): window 1280x720, `snap_2d_transforms_to_pixel`, `snap_2d_vertices_to_pixel`, `msaa_2d=0`, typing-warnings (`untyped_declaration=2`, `unused_variable=2`), benoemde fysica-lagen 1–4, input `move_left/right/up/down`, `interact`, `pause` · dep: – · `project.godot` · assert: `run_checks` display-check groen (AC-01)
- [ ] **F0-T01** · Mappenstructuur + `art/palette/lastlight.hex` (16 kleuren uit AGENT_03) + `docs/DECISIONS.md`, `SIGNALS.md`, `MILESTONES.md` · dep: F0-T00 · `art/`, `scripts/`, `resources/`, `docs/` · assert: alle mappen bestaan (check in `run_checks`)
- [ ] **F0-T02** · `tests/run_checks.gd` (display, scene-load, typing-lint, naamgeving, ≤4 autoloads, geen `*Manager`, palet) uit AGENT_10 C.2 · dep: F0-T00, T01 · `tests/run_checks.gd` · assert: exit 0 op leeg project; exit 1 op bewust fout bestand
- [ ] **F0-T03** · CI-workflow uit AGENT_10 C.4; verifieer Godot-asset-naam 4.7.2 · dep: F0-T02 · `.github/workflows/ci.yml` · assert: CI groen op PR
- [ ] **F0-T04** · `Debug`-autoload: F1-overlay (fps, tijd, vlam), tijdschaal-sneltoetsen, `--night-speed`; alleen in debug-builds · dep: F0-T00 · `scripts/autoload/debug.gd` · assert: overlay togglet; release-export bevat geen overlay

## Fase 1 — Core Foundation & Data Layer

- [ ] **F1-T01** · `Clock`-autoload: 18:00→06:00 in 720 s (waarde uit `ClockTuning`), `time_changed(minutes: int)`, `phase_changed(phase)`, `night_ended`; pauze-veilig · dep: F0-T00 · `scripts/autoload/clock.gd`, `resources/tuning/clock_tuning.tres`, `tests/test_clock.gd` · assert: `night_ended` precies 1× bij 10× pauze/hervat (AC-13)
- [ ] **F1-T02** · `FlameModel` (RefCounted) + `LanternTuning`: olie 1.0, drain 0.0065/s (+20 % 00:00–04:00), lontslijtage 0→1 in ~240 s, helderheid = `oil_factor * (1 - 0.15 * wear_over_threshold)` (drempel 0.6), `FlameState` pure functie · dep: F0-T01 · `scenes/lighthouse/flame_model.gd`, `resources/tuning/lantern_tuning.tres`, `tests/test_flame_model.gd` · assert: olie ∈ [0,1] voor 10 000 random ticks; tabeltest states (AC-14)
- [ ] **F1-T03** · `Game`-autoload: JSON-save `{night_completed: bool, volume: float}` in `user://save.json`, laden/schrijven atomair · dep: F0-T01 · `scripts/autoload/game.gd`, `tests/test_game_save.gd` · assert: round-trip gelijk; corrupt bestand → defaults, geen crash
- [ ] **F1-T04** · `Pixel.snap(Vector2) -> Vector2i` + subpixel-accumulatorregel + camerasnapregel; Pixel Lab-testscène (AGENT_07 §A) · dep: F0-T00 · `scripts/util/pixel.gd`, `scenes/fx/pixel_lab.tscn`, `tests/test_pixel.gd` · assert: `snap` gebruikt `roundi` op beide assen (test: (0.5,−0.5) → (1,−1) via Godot `roundi`-gedrag, vastgelegd in de test); Pixel Lab toont geen shimmer op 3x (AC-05 handmatig)
- [ ] **F1-T05** · Signalenregister: elk globaal signaal van `Game`/`Clock` in `docs/SIGNALS.md` · dep: F1-T01, T03 · `docs/SIGNALS.md` · assert: `run_checks` vergelijkt `signal`-regels in autoloads met register
- [ ] **F1-T06** · [M2+] `SaveData`/`ComfortItem`/`ComfortCatalog`/`TeaBlend` Resources (AGENT_02), zonder `Island`-autoload (D-03) · dep: F1-T03 · `resources/`, `scripts/` · assert: save-schema round-trip
- [ ] **F1-T07** · [M2+] `TimeManager` zon/maan/getij-formules + `WeatherSystem`-Markovketen als pure RefCounted-klassen (AGENT_06) · dep: D-03 besloten · `scripts/world/` · assert: `tests/world_tests.gd` exit 0; zelfde seed → zelfde `forecast(n)`

## Fase 2 — Core Canvas & Rendering

- [ ] **F2-T01** · Speler: versnelling, 4-richtingsfacing, collision, subpixel-accumulator, stride-gebonden loopcyclus, `footstep(foot, weight, world_pos)` · dep: F1-T04 · `scenes/player/player.tscn`, `player.gd` · assert: speler loopt testkamer zonder shimmer; footstep-event op contactframe
- [ ] **F2-T02** · `Interactable` (`Area2D`): prompt-glyph, `interacted(who)`, hold-to-complete · dep: F2-T01 · `scenes/lighthouse/interactable.tscn` · assert: demo-object vuurt `interacted` na ingestelde hold-tijd
- [ ] **F2-T03** · Greybox-kamers Keeper's Quarters + Lantern Room, tegelraster 16 px (22 rijen + 8 px strip), deur/trap-trigger, fade ≤ 400 ms · dep: F2-T01, T02 · `scenes/rooms/*` · assert: beide scenes laden headless (AC-02); kamerwissel ≤ 400 ms (AC-10)
- [ ] **F2-T04** · Palet 32 kleuren definitief (AGENT_03 tabel) + `lastlight.hex`/`.gpl` + palet-validator in `run_checks` · dep: F0-T01 · `art/palette/` · assert: validator exit 1 op PNG met vreemde kleur, exit 0 op conforme PNG (AC-04)
- [ ] **F2-T05** · Besluit D-02 (stretch-modus) in `DECISIONS.md` na Pixel Lab-test; daarna `pixel_common.gdshaderinc` en `fresnel_beam.gdshader` (roterende straal, gestapte vallichtval) · dep: F1-T04, F2-T03 · `shaders/` · assert: shader compileert zonder fouten (logs_read/`--headless`-import); straal draait 1 omwenteling per ingestelde periode ±1 frame
- [ ] **F2-T06** · Gestapt licht-overlay (CanvasLayer 10), vlamflikker, venstertint per fase (dusk→nacht→voor-dageraad→zonsopgang) · dep: F2-T05, F3-T01 · `scenes/fx/` · assert: 4 screenshots (dusk/midnight/pre-dawn/sunrise) onderscheidbaar (AC-19); alle kleuren in palet (AC-22)
- [ ] **F2-T07** · Finale pixelart pass beide kamers + speler (24x40–32x48 sprite), alle PNG's palet-vergrendeld · dep: F2-T03, T04 · `art/` · assert: palet-check groen; import-instellingen lossless/Nearest

## Fase 3 — Logic Engine (mechanica-toys)

- [ ] **F3-T01** · Lantern-scene: lens, vlam, reservoir, lont; leest `FlameModel`; `flame_state_changed(state)` · dep: F1-T02, F2-T03 · `scenes/lighthouse/lantern.tscn` · assert: alle vier states visueel verschillend; staat volgt model
- [ ] **F3-T02** · Interacties: olievat → kan (2,0 s hold) → reservoir (1,5 s hold); lont trimmen (1,2 s); lucifer (1,0 s, alleen bij `OUT`) · dep: F2-T02, F3-T01 · `scenes/lighthouse/` · assert: volledige vul-lus speelbaar; olie nooit boven capaciteit; `OUT` herstelbaar < 30 s (AC-18)
- [ ] **F3-T03** · Quarters-props: kachel, bed (cosmetisch), tafel + logboek (leesbaar), venster; elk met interactie of ambience · dep: F2-T03, T02 · `scenes/rooms/keepers_quarters/` · assert: AC-17 — ≥ 3 optionele verblijfsdingen
- [ ] **F3-T04** · Nachtorkestratie in `main.tscn`: laadt kamers, bedraadt `Clock`→tint, start/einde, titel- en zonsopgangkaart ("De lamp brandde N uur M minuten.") · dep: F1-T01, F2-T03, F3-T01 · `scenes/main.tscn` · assert: begin-tot-eind speelbaar op greybox
- [ ] **F3-T05** · Bus-layout M1 (Master/Music/Sfx/Ambience) + ambience-lagen zee/wind/vlam + voetstappen per ondergrond · dep: F3-T02, T03 · `audio/default_bus_layout.tres`, `scenes/fx/` · assert: bus-layout laadt; geen clipping bij worst-case som (AGENT_05 §3 ceilings); muziek mute behoudt sfeer (AC-20)
- [ ] **F3-T06** · [M2+] Uurwerk + opwindmechaniek + ratel (AGENT_08 deel a) · dep: F3-T01 · `scenes/lighthouse/clockwork.*` · assert: gewichtsval/gear-ratio-unit-test; lensratio G=15; ruim `GEAR_RATIO_FROM_DRUM_SIGNED` op
- [ ] **F3-T07** · [M3] Misthoorn: drukmeter, ventielhendel, echo-vertraging (AGENT_08 deel c); schip-encounters + morse (AGENT_02) · dep: F3-T06 · `scenes/lighthouse/foghorn.*` · assert: echo-testcase 10 herschreven (pad 2000 m ≥ 1500 → `Echo_Mid`) en groen
- [ ] **F3-T08** · [M4] Volledige bus-layout (6 bussen) + `TowerAcoustics` herschreven met per-bus `AudioEffectAmplify`-trim (D-04); regen binnen/buiten; zee-golven · dep: F3-T05 · `audio/` · assert: layout laadt in editor; `_user_db` verwijderd
- [ ] **F3-T09** · [M4] Regen/mist/zee-shaders, `CanvasModulate`+LUT-grading (testen of `unshaded` getint wordt; anders layer-split) · dep: F2-T05, F1-T07 · `shaders/` · assert: GPU-FX ≤ 3,0 ms; CPU ≤ 0,25 ms (profiler)

## Fase 4 — Ergonomie & UX

- [ ] **F4-T01** · Pauzemenu, titelkaart, zonsopgangkaart in pixelfont (alleen volume + tekstgrootte-toggle) · dep: F3-T04 · `scenes/ui/` · assert: AC-09 titel → spel < 3 s; AC-23 geen rood/cijfers tijdens de nacht
- [ ] **F4-T02** · Micro-delight per interactie (stoom, stofdeeltjes, kat, mot rond de vlam) · dep: F3-T02, T03 · `scenes/fx/` · assert: AC-21 — prompt+beweging+geluid+resultaat voor elke interactie (checklist)
- [ ] **F4-T03** · [M2] `AccessibilitySettings`-Resource (zonder `Settings`-autoload, D-03), `FlashGovernor` (≤ 3 Hz), rustige modi · dep: D-03 · `resources/`, `scenes/fx/flash_governor.gd` · assert: unit-test: geen lichtstap-sequentie > 3 Hz of > ingesteld delta
- [ ] **F4-T04** · [M2] Diëgetische UI: barometernaald, klok, logboek met handschriftonthulling, telescoopreticle, getijdentabel (AGENT_09); `A11y.time_phrase` met lookup-tabel; `[Verify]`-feiten afhandelen (D-05) · dep: F4-T01 · `scenes/ui/` · assert: geen zwevende HUD; labels aanwezig voor schermlezer

## Fase 5 — Hardening & Release Candidate

- [ ] **F5-T01** · Tuning-pass: drain, slijtage, tijden; ritme ≈ 5 onderhoudsmomenten, 90–120 s ademruimte · dep: F3-T02, F2-T06, F3-T05 · `resources/tuning/` · assert: nacht duurt 11–14 min (AC-11); 3 min negeren → `EMBER`, herstel zonder frustratie (AC-16)
- [ ] **F5-T02** · Soak: 15 min headless nachtscene (`--quit-after`) · dep: F3-T04 · `tests/` · assert: geen errors/warnings in log, `night_ended` 1× (AC-08)
- [ ] **F5-T03** · Perf-profiel lantaarnkamer met volle FX op geïntegreerde GPU · dep: F2-T06 · — · assert: 60 FPS stabiel; frametijd < 8 ms dev-machine (AC-07)
- [ ] **F5-T04** · Playtest met 3 personen, top-5 pijnpunten fixen · dep: F5-T01 · `docs/MILESTONES.md` · assert: AC-25
- [ ] **F5-T05** · Geheugenmeting (voorstel < 400 MB RSS) en vastleggen in `DECISIONS.md` · dep: F5-T03 · — · assert: gemeten waarde genoteerd; budget aangepast indien nodig
- [ ] **F5-T06** · Desktop-export, tag `m1`, retro in `docs/MILESTONES.md`, `CLAUDE.md` nalopen tegen werkelijkheid · dep: F5-T02, T04, T05 · — · assert: Definition of Done M1 (AGENT_10 B.6) 8/8

## Open beslissingen (blokkeren geen M1-taak tenzij vermeld)

- [ ] **D-02** stretch-modus — beslissen in F2-T05
- [ ] **D-03** autoload-set samenvoegen — vóór M2 (blokkeert F1-T06/T07, F4-T03)
- [ ] **D-04** AGENT_05 `_user_db` — F3-T08
- [ ] **D-05** AGENT_09 `[Verify]`-feiten — F4-T04

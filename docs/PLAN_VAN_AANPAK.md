# Plan van Aanpak — Last Light

Status: concept voor review (draft-PR #1). Bron: `docs/research/AGENT_01…10.md` + `INDEX.md`. Niets uit het onderzoek is in Godot gecompileerd of gedraaid; alle code in de specs is **ongetest** en wordt per taak in `docs/TASKS.md` eerst geverifieerd.

## 0. Afwijking van de opdracht (lees eerst)

De synthese-opdracht beschrijft een graaf/onderzoekstool (nodes/edges, 100k+ nodes, transform-runtimes, backend, IPC, OPSEC). Het onderzoek in `docs/research/` gaat over **Last Light**, een cozy pixel-art vuurtorenspel in Godot 4.7.2. Dit plan volgt het onderzoek en vertaalt de gevraagde fases naar het spel:

| Gevraagde fase | Vertaling voor Last Light |
|---|---|
| Fase 0 Scaffolding & CI | Projectinstellingen, mapindeling, headless checks, CI |
| Fase 1 Core Foundation & Data Layer | Klok, `FlameModel`, Tuning-resources, save-JSON, `Pixel`-helper |
| Fase 2 Core Canvas & Rendering | Pixel-perfect view/camera, speler, kamers, palet, licht |
| Fase 3 Logic Engine & Transform Pipeline | Mechanica-toys (lamp, uurwerk, lens, misthoorn), weer/tijd, audio |
| Fase 4 Ergonomie, UX & Investigation Tools | Diëgetische UI, toegankelijkheid, logboek, tactiele micro-interacties |
| Fase 5 Hardening & Release Candidate | Soak/perf, playtest, export |
| "100k nodes" stresstest | Soak van 15 min headless + framebudget (zie §1.2) |

Als de graaf-opdracht bedoeld was voor een ander project, zeg het; dit plan blijft dan los daarvan geldig.

## 1. Executive Summary & Tech Stack

### 1.1 Definitieve keuzes

| Onderdeel | Keuze | Bron |
|---|---|---|
| Engine | Godot 4.7.2 | `CLAUDE.md` (bestaande regel) |
| Taal | GDScript 2.0, volledig getypeerd; untyped = error | AGENT_10 §4 |
| Renderer | GL Compatibility | AGENT_04 §5, AGENT_10 |
| Interne resolutie | **640x360**, window-override 1280x720, integer scale | Besluit projectchat (zie §2.3, D-01) |
| Filter | Nearest, geen mipmaps/MSAA | AGENT_03, AGENT_10 §2 |
| Opslag | Lokale JSON in `user://`, mensleesbaar; instellingen als `.tres`/ConfigFile | AGENT_02 (`SaveData`), AGENT_01 (`AccessibilitySettings`) |
| "IPC"/communicatie | Godot-signalen (typed, past tense); geen netwerk, geen telemetrie | AGENT_10 §6 |
| Tests | Headless `godot --headless --script res://tests/run_checks.gd` + `tests/test_*.gd` | AGENT_10 Deel C |
| CI | GitHub Actions, Godot 4.7.2 download (asset-naam te verifiëren) | AGENT_10 C.4 |

Geen backend, database-server of plugin-loader: dat is expliciet verboden door de anti-enterprise-regel (AGENT_10 §1).

### 1.2 Prestatiebudgetten

| Budget | Waarde | Bron / status |
|---|---|---|
| Framerate | 60 FPS op geïntegreerde GPU / Steam Deck-klasse | AGENT_04 §5 |
| GPU-tijd voor alle FX (beam, weer, grading, lichten) | ≤ 3.0 ms | AGENT_04 §5 |
| CPU voor FX-scripts | ≤ 0.25 ms/frame | AGENT_04 §5 |
| Frametijd dev-machine, lantaarnkamer met volle FX | < 8 ms | AGENT_10 AC-07 |
| Kamerwissel | fade ≤ 400 ms | AGENT_10 AC-10 |
| Soak | 15 min headless zonder error/warning | AGENT_10 AC-08 |
| Procedureel zeegeluid | ≈ 0.5 ms/frame voor twee generatoren (desktop); web: één | AGENT_05 |
| Geheugen | **voorstel**: < 400 MB RSS in M1 (niet uit onderzoek; meten in F5-T05) | eigen voorstel |

## 2. Architectuur

### 2.1 Mappenstructuur (AGENT_10 §8, aangevuld met AGENT_04/07)

```
res://
  project.godot  CLAUDE.md
  scenes/ main.tscn (dunne bootstrap)  rooms/  player/  lighthouse/  ui/  fx/
  scripts/ autoload/ (max 4)  util/ (pixel.gd, ease.gd)
  resources/ tuning/*.tres  dialogue/
  art/ palette/lastlight.hex  sprites/ tiles/ ui/ fx/ fonts/
  audio/ sfx/ music/ ambience/        default_bus_layout.tres
  shaders/ common/pixel_common.gdshaderinc  fresnel_beam.gdshader  rain / mist / ocean / lut
  tests/ run_checks.gd  test_*.gd
  docs/ research/  PLAN_VAN_AANPAK.md  TASKS.md  DECISIONS.md  SIGNALS.md  MILESTONES.md
  .github/workflows/ci.yml
```

Geen `src/`, `core/`, `common/`, `managers/`, `services/` (AGENT_10 §8).

### 2.2 Datastroom

```
Clock (nacht-/wereldtijd) ──time_changed / phase_changed──► Main (sky/venster-tint, DayNight-grading)
                                                       └──► Lantern (olieverbruik tick)
Player ──interacted──► Interactable ──► Lantern/Barrel/Logbook (ouder bedraadt kind-signalen)
FlameModel (pure functie van olie + lont) ──flame_state_changed──► Lichtoverlay, Lens, Audio, Venster
Game (save/instellingen) ◄── Main (nacht voltooid)
Weer/tijd (M4): TimeManager ──ambient_updated──► Shaders (globals), Audio-buses, Regen/Mist
```
Regel: kind→ouder via signaal, ouder→kind via methode (AGENT_10 §5–6).

### 2.3 Besluiten

| ID | Besluit | Status | Grond |
|---|---|---|---|
| D-01 | Resolutie **640x360**; `project.godot` viewport is aangepast, M1-T00 verifieert de rest | **Besloten** (projectchat) | Opdracht; AGENT_03 §1, AGENT_10 §0 |
| D-02 | Stretch-modus: `canvas_items` (huidig, AGENT_07/10) tegenover `viewport` (AGENT_03/04) | **Open**; M1 werkt met `canvas_items`, geen M1-taak hangt ervan af. Beslis vóór F2-T05 (shader-FX) | AGENT_03, 04, 07 |
| D-03 | Autoloads: AGENT_01 `Settings`, 02 `Island`, 04 `DayNight`, 06 `TimeManager`, 07 `Events`+`Router`, 09 `Clock/Weather/Tides/Journal/A11y` tegen AGENT_10 maximum van vier | **Open**; M1 gebruikt alleen `Game`, `Clock`, `Debug` (+`Sfx` optioneel). Samenvoegen vóór M2 | AGENT_10 §5 |
| D-04 | AGENT_05 `TowerAcoustics._user_db` is defect; vervangen door per-bus `AudioEffectAmplify`-trim | **Open**, opgelost in F3-T08 | AGENT_05 |
| D-05 | AGENT_09 `[Verify]`-feiten (lensterminologie, IOV-stappen, intervallen, AccessKit-namen, Code of Signals) | **Open**; fictieve "Island Code" gebruiken | AGENT_09 |
| D-06 | Tijdmodel: `TimeManager` (AGENT_06) bezit de klok; AGENT_01 pacing-presets worden schalen op die klok | Besloten voor M2+; M1 gebruikt `Clock` met 12 min nacht | AGENT_01, 06, 10 |
| D-07 | Tegelrij 360/16 = 22,5: layout 22 rijen + 8 px strip | Besloten | AGENT_03 |

## 3. Gefaseerde roadmap

Mapping naar milestones (AGENT_10 Deel B): **M1 = Fase 0 + 1 + 2 volledig en de M1-delen van Fase 3–5** (twee kamers, één nacht). Fase 3–5 inhoud buiten M1 hoort bij M2–M6.

### Fase 0 — Scaffolding & CI
- `project.godot`: 640x360 / 1280x720, snap-2d, typing-warnings, benoemde fysica-lagen, input-acties (`move_*`, `interact`, `pause`).
- Mappen, `lastlight.hex` (start 16 kleuren), `docs/DECISIONS.md`, `SIGNALS.md`, `MILESTONES.md`.
- `tests/run_checks.gd` (display, scene-load, typing-lint, naamgeving, autoloads, palet) + `.github/workflows/ci.yml`.

### Fase 1 — Core Foundation & Data Layer
- `Clock`: dusk 18:00 → dawn 06:00, 720 s, pauze-veilig, `night_ended` exact één keer.
- `FlameModel` (pure functie): olie, lontslijtage, `FlameState {OUT, EMBER, STEADY, BRIGHT}`; `LanternTuning`-resource.
- `Game`: JSON-save (`night_completed`, volume), instellingen.
- `Pixel.snap(Vector2) -> Vector2i`, subpixel-accumulator.
- Later (M2+): `SaveData` en comfort-`Resource`s uit AGENT_02, `AccessibilitySettings` uit AGENT_01, `TimeManager`/`WeatherSystem` uit AGENT_06.

### Fase 2 — Core Canvas & Rendering
- Camera/view conform AGENT_07 (M1: gesnapte camera, geen SubViewport-banden tenzij D-02 dat eist).
- Speler: versnelling, stride-gebonden loopcyclus, voetstaplocatie-events; trap-stack (alleen nodig voor torenverdiepingen — M1 gebruikt één trap/overgang tussen twee kamers).
- Kamers: Keeper's Quarters, Lantern Room; fade-overgang.
- Palet: 32/48 kleuren (AGENT_03), `.hex`/`.gpl`, validator.
- Licht: gestapt, palet-vergrendeld; `fresnel_beam.gdshader` (roterende straal), vensterkleur per fase (AGENT_04).

### Fase 3 — Logic Engine (mechanica-toys)
- M1: olie bijvullen (vat → kan → reservoir), lont trimmen, lucifer, vlamtoestand → licht/geluid.
- M2–M3: uurwerk + opwinden, lensregulateur, misthoorn met echo (AGENT_08); schepen/morse (AGENT_02).
- M4: weer-Markovketen, getijden, regen/mist/zee-shaders (AGENT_04, 06).
- Audio: bussen Master/Ambience_Sea/Ambience_Weather/Lighthouse_Mech/Foley/Cozy_Music (AGENT_05); M1 mag vereenvoudigen naar Master/Music/Sfx/Ambience (AGENT_10 T17).

### Fase 4 — Ergonomie & UX
- M1: interactieprompt, pauzemenu, titel-/zonsopgangkaart, leesbaar logboek, tekstgrootte-toggle.
- M2: toegankelijkheid (Flash-governor, rustige modi, remapping) uit AGENT_01; diëgetische barometer/klok/telescoop uit AGENT_09.

### Fase 5 — Hardening & Release Candidate
- Soak 15 min, perf-profiel lantaarnkamer, 3 playtesters, export desktop, tag `m1`.

## 4. Checklist & acceptatiecriteria per fase

| Fase | Definition of Done (toetsbaar) |
|---|---|
| 0 | AC-01 groen: `run_checks.gd` exit 0 op lege projecten; CI groen op een PR; `project.godot` = 640x360/1280x720/canvas_items/keep/integer/Nearest/gl_compatibility |
| 1 | AC-13: `night_ended` exact één keer bij herhaald pauzeren (unit-test); AC-14: olie ∈ [0, capaciteit], `FlameState` is pure functie (tabeltest); save round-trip test; `Pixel.snap` test |
| 2 | AC-02 alle scenes laden headless; AC-04 elk ondoorzichtig pixel in `lastlight.hex`; AC-05/06 handmatig: geen shimmer op 1280x720 en 1920x1080, nette letterbox; framebudget §1.2 |
| 3 | AC-18 `OUT` herstelbaar < 30 s; AC-15 vlam leesbaar zonder HUD; geen fail-state (grep op "game over"); bus-layout laadt, geen clipping bij worst-case som (AGENT_05 §3) |
| 4 | AC-23 geen rode UI/cijfers tijdens de nacht; AC-09 titel → spel < 3 s; AC-21 elke interactie heeft prompt+beweging+geluid+zichtbaar resultaat |
| 5 | AC-07, AC-08 (soak), AC-11 (11–14 min), AC-25 (zonder uitleg 5 min); AC-24 ≤ 4 autoloads en geen `*Manager`; CI groen op releasecommit |

De volledige AC-lijst (AC-01…AC-25) staat in `AGENT_10…md` §B.4 en is bindend.

## 5. Risico's & fallback

| # | Risico | Mitigatie / fallback |
|---|---|---|
| 1 | **Pixel-shimmer en shader-onzekerheid** (D-02: stretch-modus, `CanvasModulate` op `unshaded`, snap per SubViewport, niet getest op 4.7.2) | Camera-snap in F1-T04 en test op 3x op dag één. Pixel Lab-testscène (AGENT_07). Fallback: stretch `viewport`, parallax in hele pixels (stappend, geen banden); layer-split voor `CanvasModulate` (AGENT_04) |
| 2 | **Ongeteste spec-code en onbekende API-namen** (`Image.create_empty`, `AudioEffectHardLimiter`, AccessKit-namen; defecten gemeld door AGENT_02/05/07/08/09) | Elke taak begint met parse-check (`--check-only`) en een headless test; geen spec-code zonder test mergen; defectenlijst uit `INDEX.md` wordt in `TASKS.md` afgevinkt |
| 3 | **Scope-creep en autoload-wildgroei** (10 specs vol met extra systemen) | Scope-lock M1 (AGENT_10 B.2) is bindend; `run_checks.gd` faalt bij > 4 autoloads of `*Manager`; D-03 samenvoegen vóór M2; "cut the feature" bij twijfel |

## 6. Open punten voor de eigenaar

1. D-02 stretch-modus, D-03 autoload-set, D-04/D-05 (zie §2.3).
2. Bevestig dat de graaf-opdracht (zie §0) niet voor dit project bedoeld was.
3. CI: asset-naam `Godot_v4.7.2-stable_linux.x86_64.zip` verifiëren.

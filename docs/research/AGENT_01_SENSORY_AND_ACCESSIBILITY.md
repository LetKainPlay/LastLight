# AGENT 01: Cozy Loop, Sensory Accessibility, Tactile Micro-Mechanics

Project: Last Light (Godot 4.7.2, GDScript 2.0, static typing)
Internal resolution target: 640x360 (NOTE: current `project.godot` is 320x180; must be changed by the project owner to `window/size/viewport_width=640`, `viewport_height=360`, `stretch/mode="viewport"`, `stretch/scale_mode="integer"`. This doc does not edit project files. All pixel values below assume 640x360.)

---

## 0. Design Contract

| Mandate | Rule enforced in this doc |
|---|---|
| Toy over tool | Every system is a physical object in the scene tree with a state machine and a verb (wipe, wind, strike, boil). No manager singletons that own gameplay; only one tiny autoload (`Settings`) for accessibility values. |
| No fail states | No timers that punish. Nothing is lost, extinguished-forever, broken, or scored. The beacon can always be lit late; ships do not wreck. Time pressure is replaced by "gentle invitations". |
| Pixel fidelity | All motion snaps to the 1px grid in rendering (`snap_2d_transforms_to_pixel`, `snap_2d_vertices_to_pixel`). Tweened floats are internal; displayed positions are rounded. |
| Sensory safety | Every flash, shake, flicker, loud sound, and haptic has a named channel with a master scalar in `AccessibilitySettings`. |

Principle hierarchy for all feedback: **Anticipation (0-80 ms) -> Contact (instant) -> Settle (120-400 ms)**. Every interaction gets all three, and each can be reduced independently.

---

## PART A: The Primary Cozy Loop (Day / Dusk / Night / Dawn)

### A.1 Loop Overview

The day is a single continuous cycle (default real-time length 18 minutes, adjustable 8-60 min, or "Hold" which freezes it). The cycle is a ring of four phases, each hosting a small set of optional, order-free activities. Nothing is required to advance a phase except the player choosing to (via the Beacon lever at Dusk and the Bed at Night), or auto-advance if "Auto-drift time" is on. "Auto-drift off" is the default for the low-pressure preset: time only moves when the player lights/extinguishes things or sleeps.

```
        DAWN  ------------->  DAY
         ^                     |
         |                     v
       NIGHT  <-------------  DUSK
```

| Phase | Normalized t (0..1) | Default length (of 18 min) | Mood | Primary verbs |
|---|---|---|---|---|
| Dawn | 0.00 - 0.12 | ~2 min | pink-gold, quiet, gulls | Extinguish beacon (snuff wick), open shutters, write morning journal line, tea |
| Day | 0.12 - 0.58 | ~8.3 min | bright, brisk | Wipe glass, oil/clean, wind weights, tend garden/sign, observe weather, wave at boats |
| Dusk | 0.58 - 0.72 | ~2.5 min | amber to indigo | Strike match, light beacon (the centerpiece), watch first lamp-glow reach sea |
| Night | 0.72 - 1.00 | ~5 min | deep indigo, warm interior | Tea, journal, stargaze, tend flame (trim), listen to radio/sea, sleep -> Dawn |

The ordering in-phase is soft. Missing something never changes outcomes. The only "consequence" is a different *flavor* of the next scene (see A.5, "Gentle Echoes"): unwiped glass at night produces softer, hazier light shafts (still pretty), not a penalty.

### A.2 Phase State Machine

The `DayCycle` node lives in the world scene. It does not manage tasks; it only exposes a continuous `time_of_day` float and emits phase signals consumed by lighting, audio, and sprites via signals (decoupled, no registry).

```gdscript
class_name DayCycle
extends Node

signal phase_changed(new_phase: Phase, old_phase: Phase)
signal time_changed(t: float)               ## 0..1 normalized, emitted at max 30 Hz
signal day_rolled_over(day_index: int)

enum Phase { DAWN, DAY, DUSK, NIGHT }

## Phase boundaries on the normalized clock. Ascending, last wraps to 1.0.
const PHASE_STARTS: Array[float] = [0.00, 0.12, 0.58, 0.72]

@export var day_length_seconds: float = 1080.0   ## 18 min
@export var auto_drift: bool = true              ## false => time only moves via nudge()
@export_range(0.0, 1.0) var t: float = 0.20

var phase: Phase = Phase.DAY
var day_index: int = 0
var _emit_accum: float = 0.0

func _ready() -> void:
	phase = _phase_for(t)
	Settings.changed.connect(_on_settings_changed)
	_apply_settings()

func _process(delta: float) -> void:
	if not auto_drift:
		return
	_advance(delta / day_length_seconds)

## Player-driven time: lighting the beacon at dusk pushes time forward gently;
## sleeping fast-forwards to dawn. Never negative, never forced.
func nudge(amount_normalized: float) -> void:
	_advance(amount_normalized)

func skip_to(target: Phase) -> void:
	var start: float = PHASE_STARTS[target]
	if start <= t:
		day_index += 1
		day_rolled_over.emit(day_index)
	t = start
	_set_phase(_phase_for(t))
	time_changed.emit(t)

func _advance(dt: float) -> void:
	var prev: float = t
	t += dt
	if t >= 1.0:
		t -= 1.0
		day_index += 1
		day_rolled_over.emit(day_index)
	_set_phase(_phase_for(t))
	_emit_accum += dt
	if _emit_accum > (1.0 / 30.0) / day_length_seconds or prev > t:
		_emit_accum = 0.0
		time_changed.emit(t)

func _phase_for(v: float) -> Phase:
	var p: int = 0
	for i in PHASE_STARTS.size():
		if v >= PHASE_STARTS[i]:
			p = i
	return p as Phase

func _set_phase(p: Phase) -> void:
	if p != phase:
		var old: Phase = phase
		phase = p
		phase_changed.emit(p, old)

func _apply_settings() -> void:
	day_length_seconds = Settings.pacing.day_length_minutes * 60.0
	auto_drift = Settings.pacing.auto_drift

func _on_settings_changed(section: StringName) -> void:
	if section == &"pacing":
		_apply_settings()
```

### A.3 Sky and Light Palette Ramp (curated)

Palettes are 8-color ramps per phase, remapped via a 1D LUT texture (palette-swap shader in Part A.6). Hex values are curated, not procedural, to keep pixel art coherent.

| Phase | Sky top | Sky mid | Horizon | Sea | Ambient (light mult) | Beacon warmth |
|---|---|---|---|---|---|---|
| Dawn | #5b6e9f | #c98fa3 | #f2c79a | #4d6f8e | #d9b8b0 | #ffd9a0 |
| Day | #6fb1e0 | #a6d8ee | #e9f4ee | #3f87a8 | #ffffff | n/a (off) |
| Dusk | #3b3f7a | #b2607e | #f09a5a | #34506f | #c79aa0 | #ffbe5c |
| Night | #0c1233 | #1a2354 | #2f3b73 | #111f3d | #4a5c9a | #ffcf6e |

Ambient light is applied via a full-screen `CanvasModulate` color, interpolated between phase keys with a smoothstep and quantized to 16 steps per channel to avoid banding shimmer in dither:

```gdscript
func ambient_for(t: float) -> Color:
	# keys: [t, color]. Phase keys sit mid-phase; wrap handled by duplicating first key at 1.0.
	var keys: Array = [
		[0.00, Color("d9b8b0")], [0.06, Color("d9b8b0")],
		[0.14, Color.WHITE],     [0.56, Color.WHITE],
		[0.65, Color("c79aa0")], [0.74, Color("4a5c9a")],
		[0.96, Color("4a5c9a")], [1.00, Color("d9b8b0")],
	]
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= a[0] and t <= b[0]:
			var k: float = smoothstep(a[0], b[0], t)
			var c: Color = (a[1] as Color).lerp(b[1] as Color, k)
			return Color(snappedf(c.r, 1.0/16.0), snappedf(c.g, 1.0/16.0), snappedf(c.b, 1.0/16.0))
	return Color.WHITE
```

### A.4 Phase Activity Designs

Each activity is a node in the world with an `Area2D` interaction hotspot (hover shows a 1-frame outline shimmer, never a text prompt unless "Interaction hints" is enabled). None have timers.

#### A.4.1 Dawn
- **Snuff the wick**: a brass snuffer-on-a-stick hangs by the lantern. Player lowers it over the flame (drag down, 6 px/step snapped), flame shrinks over 5 sprite frames, smoke wisp particle rises (4 px pixel particles, gravity -6 px/s^2, lifetime 2.4 s, can be reduced).
- **Open shutters**: crank-handle (reuses winding mechanic, Part C.2). Light shafts grow from 0 to full across the room as shutters open.
- **Tea**: see A.4.5.
- **Morning journal line**: see A.4.6.

#### A.4.2 Day (the maintenance phase)
Maintenance tasks are **cleanliness gradients, not jobs**. Each task object has a continuous `care` value 0..1 that visibly relaxes (slowly decays) *only while the game is running and only in a bounded way* (floor 0.35, never reaches ugly/broken). Care is shown purely by art state (dust, salt crust, tarnish), no bars, no icons.

| Object | Verb (mechanic) | Care decay | Visual states (sprite swap / shader) | Reward |
|---|---|---|---|---|
| Lantern-room glass | Wipe condensation (C.1) | 0.02/min, +weather multiplier | fog mask alpha 0..1 | clearer, crisper light shafts, more detailed horizon view |
| Weights / clockwork | Wind (C.2) | 0.04/min while beacon lit | weight height on chain | beacon rotation gentle and smooth; stops gently if fully down (no penalty, just "resting") |
| Brass fittings | Polish (rub, same as wiping, shader variant) | 0.01/min | tarnish tint | shinier glints (extra pixel sparkle frames) |
| Window box / herbs | Water (tilt can, particle drops) | 0.03/min | leaf sprites | herbs for tea (unlocks flavors) |
| Signal flags | Hoist/lower (rope pull, 3 slots) | none | which flags flown | boats toot a reply horn |
| Rain gutter barrel | Wait/observe | none | water level | tea water source |

"Weather observation" (A.4.3) is also a day verb, fitted with a barometer and telescope.

#### A.4.3 Weather Observation (toy set)
Weather is a gentle ambient system with 6 states: `CLEAR, BREEZY, OVERCAST, FOG, RAIN, STORM`. Player toys:

| Toy | Interaction | Information it gives (diegetic) |
|---|---|---|
| Barometer (brass dial) | Tap glass to make needle twitch (classic) | Needle pos = next 2 phases' weather tendency |
| Telescope | Hold & drag across horizon, parallax with focus ring (scroll) | Spot ships, gulls, distant squalls |
| Anemometer | Spins by itself; click to stop/release with satisfying ratchet | Speed ~ wind |
| Weather journal | Pencil-tick a small box (see A.4.6) | Player-side record |
| Window | Open/close latch | Sound and breeze particles change |

Weather transition is a Markov chain with phase-weighted probabilities, evaluated once at each phase start (never mid-phase), so no surprise sensory jumps:

```gdscript
class_name WeatherPicker
extends RefCounted

enum W { CLEAR, BREEZY, OVERCAST, FOG, RAIN, STORM }

## Row = current, column = next. Rows sum to 1.0. Storm is rare and always followed by calmer.
const MATRIX: Array[PackedFloat32Array] = [
	PackedFloat32Array([0.55, 0.25, 0.12, 0.05, 0.03, 0.00]), # CLEAR
	PackedFloat32Array([0.30, 0.30, 0.20, 0.05, 0.12, 0.03]), # BREEZY
	PackedFloat32Array([0.15, 0.15, 0.25, 0.15, 0.25, 0.05]), # OVERCAST
	PackedFloat32Array([0.30, 0.10, 0.25, 0.30, 0.05, 0.00]), # FOG
	PackedFloat32Array([0.15, 0.15, 0.30, 0.10, 0.20, 0.10]), # RAIN
	PackedFloat32Array([0.10, 0.20, 0.40, 0.05, 0.25, 0.00]), # STORM
]

static func next(current: W, rng: RandomNumberGenerator, allow_storm: bool) -> W:
	var row: PackedFloat32Array = MATRIX[current].duplicate()
	if not allow_storm:  # low-sensory: fold storm probability into RAIN
		row[W.RAIN] += row[W.STORM]
		row[W.STORM] = 0.0
	var r: float = rng.randf()
	var acc: float = 0.0
	for i in row.size():
		acc += row[i]
		if r <= acc:
			return i as W
	return W.CLEAR
```

Storm intensity itself is a 0..1 scalar, scaled by `AccessibilitySettings.sensory.storm_intensity` (default 0.6; "Gentle" preset 0.25; "Off" 0.0 which re-labels storms as heavy rain).

#### A.4.4 Dusk: Lighting the Beacon (the centerpiece ritual)
Sequence, each step is physical and player-paced; the player may stop at any step and walk away, the step simply stays as left (no timeouts).

1. **Check the oil/wick**: lift wick-trimmer scissors; click-and-snip small charred bit (satisfying 2-frame snip, tiny particle).
2. **Strike match** (C.3). A held match is the only light-source "key".
3. **Touch to wick**: carry the flame (drag) to the wick; flame transfers if the match is lit and distance < 10 px. Match flame persists for up to 8 s *visually decaying*, but a new match can always be struck: no match supply limit (box is bottomless; a small pile of used matches accumulates as decoration in the tray, purely cosmetic and clearing at dawn).
4. **Wick catches**: 4-frame bloom, `PointLight2D` energy ramps 0 -> 1 over `beacon_ignite_seconds` (default 3.0, adjustable 1.0-6.0).
5. **Clockwork engages**: if weights wound, the lens begins to rotate (see C.2); if not, the lens glows steady ("a fixed light") — still valid, still pretty.
6. **First sweep**: beam sweeps once across the sea; ships' tiny deck lamps answer one by one (cosmetic acknowledgements).

The lit beacon yields no points, no streak. The reward is atmosphere and the little "answering lights."

```gdscript
class_name BeaconLamp
extends Node2D

signal ignited
signal snuffed

enum State { COLD, TRIMMED, WICK_READY, IGNITING, LIT, SNUFFING }

@export var ignite_seconds: float = 3.0
@onready var _light: PointLight2D = $PointLight2D
@onready var _flame: AnimatedSprite2D = $Flame
@onready var _beam_origin: Marker2D = $BeamOrigin

var state: State = State.COLD
var _tween: Tween

func receive_trim() -> void:
	if state == State.COLD:
		state = State.TRIMMED
		_flame.play(&"trimmed_idle")

## Called by Match when a lit match head enters the wick Area2D.
func receive_flame(intensity: float) -> void:
	if state in [State.COLD, State.TRIMMED, State.WICK_READY] and intensity > 0.15:
		state = State.IGNITING
		_start_ignite()

func _start_ignite() -> void:
	_flame.play(&"catch")
	if _tween: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var dur: float = ignite_seconds * Settings.pacing.animation_time_scale
	_tween.tween_property(_light, "energy", 1.0, dur)
	_tween.tween_callback(func() -> void:
		state = State.LIT
		_flame.play(&"burn")
		ignited.emit())

func snuff() -> void:
	if state != State.LIT: return
	state = State.SNUFFING
	if _tween: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_property(_light, "energy", 0.0, 2.0 * Settings.pacing.animation_time_scale)
	_tween.tween_callback(func() -> void:
		state = State.COLD
		_flame.play(&"cold")
		snuffed.emit())
```

#### A.4.5 Night: Tea Ritual
Tea is the "downshift" toy chain: Fill kettle (barrel/tap) -> place on stove -> boil (C.4) -> choose leaves from a rack of jars (herbs from the window box) -> pour into a cup -> steep (watch swirl; no timer, tea is "ready" when the swirl color stabilizes, over-steeping simply gets stronger and prettier) -> drink (cup tilts, steam fades, a +1 "warmth" cosmetic that tints the room lamp slightly warmer for the rest of the night; no gameplay effect).

Tea cup state machine: `EMPTY -> POURING -> STEEPING -> READY -> SIPPING -> EMPTY`. Sipping can be repeated while it has contents; contents drain 25% per sip over 6 sips.

#### A.4.6 Journal
The journal is a physical book on the desk. No text input required. Three tiers of engagement (player picks any):
1. **Stamp/tick**: today's weather icon stamp (rubber stamp toy with a satisfying thunk), sea state tick boxes, moon phase sticker.
2. **Pick a line**: 3 procedurally-assembled evocative sentence fragments from a small authored pool, filtered by actual events of the day (cleaned glass, which weather, which ships passed). Player taps to keep one.
3. **Freewrite (optional)**: a text line using a bundled pixel font; skip is always one click.

Journal page data (Resource, saved):

```gdscript
class_name JournalEntry
extends Resource

@export var day_index: int = 0
@export var weather: int = 0                    # WeatherPicker.W
@export var stamps: PackedStringArray = []      # e.g. "moon_waxing", "gull", "ship_blue"
@export var chosen_line_id: StringName = &""    # id into the authored pool
@export var freewrite: String = ""              # <= 140 chars
@export var doodle: PackedByteArray = PackedByteArray()  # optional 32x16 1-bit bitmap
```

Authored line pool example (data-driven, `res://data/journal_lines.json`):

```json
{
  "lines": [
    {"id": "fog_soft", "when": {"weather": ["FOG"]}, "text": "The sea went missing today. I rang the bell anyway."},
    {"id": "glass_clear", "when": {"glass_care_min": 0.7}, "text": "Cleaned the glass. Even the far rocks looked pleased."},
    {"id": "tea_late", "when": {"phase": ["NIGHT"], "tea": true}, "text": "Tea tasted like the herb box smells."},
    {"id": "none_needed", "when": {}, "text": "A quiet one. Those are allowed."}
  ]
}
```

Selection: gather lines whose `when` clauses match, shuffle with seeded RNG (day_index), offer 3. The fallback entry `none_needed` guarantees non-empty.

### A.5 Gentle Echoes (replace fail states)

Everything that would be a "failure" elsewhere is an *aesthetic echo*.

| Would-be failure | Cozy echo |
|---|---|
| Forgot to wind weights; beacon stops | Lens stops, light becomes a fixed warm glow; a small grandfather-clock "sigh" sound; ships still answer. Winding at any time resumes. |
| Let glass fog over | Beam spreads soft & hazy, horizon blurry, still lovely; wiping reveals a satisfying contrast "pop." |
| Skipped lighting beacon | The night is moonlit and blue; lighthouse keeper's cat sleeps near the cold lamp; lighting it later (any time before sleep) works. If the player sleeps without lighting: at dawn, a gull drops a little shell gift. (No punishment, no guilt.) |
| Kettle left on | Kettle whistles gently, then simply goes quiet and cools; no fire hazard, no damage. |
| Storm | Beam appears brighter in rain; thunder is muffled by settings; ships never wreck. |
| Many days away | The island shows sweet "welcome back" dust and cobwebs that wipe off in one swipe with sparkles. |

### A.6 Day Transition Shader (palette remap, 640x360, pixel-safe)

Applied as a full-screen `ColorRect` in a `CanvasLayer` over the SubViewport output, or per-sprite via `material`. The LUT is a 64x1 (or 8x8 swatch rows x 4 phases) `Texture2D`; this version blends two phases.

```glsl
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D palette_a : filter_nearest, repeat_disable;  // 16x1 for phase A
uniform sampler2D palette_b : filter_nearest, repeat_disable;  // 16x1 for phase B
uniform sampler2D source_ramp : filter_nearest, repeat_disable; // 16x1 canonical day palette
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.6;
uniform int ramp_size = 16;

// 4x4 Bayer matrix (ordered dithering = stable, no temporal noise = flicker-safe).
const float BAYER[16] = float[16](
	0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
	12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
	3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
	15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0);

int nearest_index(vec3 c) {
	float best = 1e9; int idx = 0;
	for (int i = 0; i < 16; i++) {
		vec3 p = texelFetch(source_ramp, ivec2(i, 0), 0).rgb;
		vec3 d = c - p;
		float dist = dot(d, d);
		if (dist < best) { best = dist; idx = i; }
	}
	return idx;
}

void fragment() {
	ivec2 px = ivec2(FRAGCOORD.xy);
	vec3 src = texelFetch(screen_tex, px, 0).rgb;
	int idx = nearest_index(src);
	vec3 a = texelFetch(palette_a, ivec2(idx, 0), 0).rgb;
	vec3 b = texelFetch(palette_b, ivec2(idx, 0), 0).rgb;
	float thr = BAYER[(px.y % 4) * 4 + (px.x % 4)] - 0.5;
	float k = clamp(blend + thr * dither_strength * 0.25, 0.0, 1.0);
	COLOR = vec4(mix(a, b, step(0.5, k)), 1.0);  // hard step = no new colors, pure palette
}
```

Note: `step(0.5,k)` keeps output strictly inside the two palettes (no in-between colors). The Bayer pattern is spatially fixed (no scrolling), so transitions shimmer-free. With "Reduce dither shimmer" set, `dither_strength` = 0 and transitions become a hard cut mid-blend with a 1.5 s crossfade overlay.

### A.7 Pacing Presets (cycle driver)

| Preset | Day length | Auto-drift | Weather storms | Ambient SFX | Notes |
|---|---|---|---|---|---|
| "Lantern" (default) | 18 min | on | normal | normal | balanced |
| "Slow Tide" | 40 min | on | gentle | soft | long, meditative |
| "Hold the Hour" | n/a | off | gentle | soft | time only changes via nudge/skip; recommended for anxiety about time |
| "Quiet Room" | n/a | off | off | minimal | low-sensory bundle (see B.6) |

---

## PART B: Neurodivergent & Sensory Accessibility Audit

### B.1 Audit Scope and Method

Audited categories, mapped to common needs (autism, ADHD, anxiety, migraine/photosensitive epilepsy, sensory processing differences, dyslexia, motor differences, low vision, hearing differences). Principles follow WCAG 2.3 (flashes: no more than 3 per second, reduced general-flash area), Game Accessibility Guidelines (basic/intermediate/advanced), and Xbox Accessibility Guidelines concepts.

### B.2 Audit Table

Legend: Risk = potential harm if unaddressed (H/M/L). Status = design requirement (REQ), default-on (DEF), option (OPT).

| # | Area | Risk | Concern | Design decision | Status |
|---|---|---|---|---|---|
| 1 | Time pressure | H | Countdown stress, executive-function overload | No timers anywhere. Day length slider; "Hold the Hour"; no required action ever expires. Visual timeouts (match flame) are cosmetic and re-strikeable at no cost. | REQ |
| 2 | Fail states | H | Rejection sensitivity, perfectionism | None. See A.5 Gentle Echoes. No scoring, grading, ranking, "missed" language. | REQ |
| 3 | Lightning/flash | H | Photosensitive seizures, migraine | Lightning is a soft 400 ms luminance swell capped at +12% ambient by default; hard cap of 3 pulses/s even at max; option to replace with a dim steady glow or nothing. Flash area limited to <25% of screen at max intensity. | REQ+OPT |
| 4 | Beacon sweep | M | Rotating bright beam may strobe | Beam rotation period default 12 s, min 6 s; beam edge is gradient, not hard strobe. "Fixed light" option replaces rotation with steady glow. | DEF+OPT |
| 5 | Screen shake | M | Vestibular, nausea | Shake default amplitude 1 px quantized; slider 0-100%; "Off" removes. No camera zoom pulses. | OPT |
| 6 | Parallax/scroll | M | Vestibular | Pixel-snapped; "Reduce parallax" option collapses layers to static; no continuous camera drift unless player moves. | OPT |
| 7 | Dither shimmer | M | Visual stress, pattern sensitivity | Ordered (spatially fixed) dither only; option to flatten dither bands. No temporal noise/film grain by default; grain optional. | DEF+OPT |
| 8 | Contrast | M | Low vision, dyslexia glare | High-contrast mode adds 1 px dark outline to interactables and raises UI text contrast to >= 7:1; text uses off-white (#f3ead8) on deep (#1c1b2e), not pure white on black. | OPT |
| 9 | Color blindness | M | Info conveyed by color alone | Nothing depends on color alone; interactables use shape/outline/shimmer; palette filters (protan/deutan/tritan-friendly LUTs) applied through the same remap shader. | REQ+OPT |
| 10 | Text legibility | M | Dyslexia, low vision | Pixel font chosen for open counters (e.g. 8x8-based font w/ 1x or 2x integer scale); optional dyslexia-friendly font (OpenDyslexic-like bitmap) toggle; text scale 100/150/200% by integer scale only; no text in timers; line spacing slider. | OPT |
| 11 | Audio loudness | H | Auditory sensitivity | Separate buses: Master, Music, Ambience, SFX, UI, Thunder/Alarm, Voice/Radio. Thunder bus has default -9 dB and a limiter. Max peak -3 dBFS globally. | REQ |
| 12 | Sudden sounds | H | Startle | All SFX fade in with >= 8 ms attack; thunder has 300 ms swell; "No sudden sounds" mode applies low-pass + 10 ms compressor on SFX. | DEF+OPT |
| 13 | Hearing loss | M | Missing info | All meaningful audio has a visual twin (e.g. kettle whistle -> steam puff + rattle). Optional "sound captions" in diegetic style (little pixel icons "~ whistle ~"). | OPT |
| 14 | Repetitive sound | M | Misophonia/loop fatigue | Ambience uses multiple randomized layers w/o short loops (> 60 s combined cycle); "Mute repetitive" option disables ticking clock etc. | OPT |
| 15 | Motor | M | Fine motor, tremor, one-handed | Every drag mechanic has a click-to-toggle alternative; hold interactions have "tap to latch" mode; wide hit areas (min 24x24 px at 640x360); full gamepad & keyboard focus navigation; remappable inputs; no rapid-mash. | REQ+OPT |
| 16 | Precision | M | Jitter/tremor | Smoothing/dead-zone slider (0-12 px) for drags; "Assist magnet" snaps items to nearest valid target. | OPT |
| 17 | Cognitive load | M | ADHD, anxiety | One thing at a time: max 1 active ritual UI; no persistent HUD; optional "gentle nudge" glow on next suggested object (never a list, never a quest log pressure). | OPT |
| 18 | Overstimulation | H | Autism/SPD | "Quiet Room" master preset; per-channel sliders; ambience density control (gulls, creaks, radio chatter). | OPT |
| 19 | Memory | M | Executive function | Journal doubles as a gentle recap (what happened yesterday); no hidden requirements; interactables remember last state. | DEF |
| 20 | Haptics | M | Tactile sensitivity | Strength slider 0-100%; per-class toggles (tick, thump, rumble); default 60%; rumble never above 0.6 magnitude by default; no continuous long vibration >1.5 s. | OPT |
| 21 | Particle density | L | Visual busyness | Particles scale 0-100%; low = fewer, slower. | OPT |
| 22 | Pause | M | Interruptions | Pause anywhere, always safe; autosave on every phase change and every task completion; "Sit with it" idle mode (hands-free ambient). | REQ |
| 23 | Photosensitive onboarding | M | Surprise | First-run screen (calm, non-modal fully skippable by keyboard) offers presets before gameplay; settings accessible from title and in-game via a physical object (radio knob) and Esc. | REQ |
| 24 | Notifications | L | Anxiety | No push/reminder language, no streaks, no "come back!" prompts. | REQ |
| 25 | Save | L | Loss anxiety | Autosave only; no save-scumming needed; can't lose progress. | REQ |

### B.3 Sensory Channels (the vocabulary of the settings)

All feedback is routed through a named channel; channels have independent intensities. This is the engineering mechanism enabling the "low-sensory toggles."

| Channel | Examples | Min/Max | Default | Gentle | Quiet Room |
|---|---|---|---|---|---|
| `flash` | lightning, match-strike spark, beacon ignite pop | 0-1 | 0.5 | 0.2 | 0.0 |
| `shake` | storm shake, thump | 0-1 | 0.3 | 0.1 | 0.0 |
| `motion` | parallax, wave sway, cloud drift | 0-1 | 0.8 | 0.5 | 0.25 |
| `particles` | steam, sparks, rain, gulls | 0-1 | 0.8 | 0.5 | 0.3 |
| `dither` | dither band strength | 0-1 | 0.6 | 0.3 | 0.0 |
| `haptics` | controller rumble | 0-1 | 0.6 | 0.3 | 0.0 |
| `audio_sudden` | transient peaks | 0-1 (softening) | 0.4 | 0.7 | 1.0 |
| `thunder` | thunder volume | 0-1 | 0.5 | 0.25 | 0.0 |
| `weather_intensity` | storm drama | 0-1 | 0.6 | 0.25 | 0.0 |

### B.4 AccessibilitySettings Resource (data structure + GDScript)

Persisted as a `.tres`/ConfigFile hybrid at `user://accessibility.tres` (Resource saves are atomic via `ResourceSaver.save`). A tiny autoload `Settings` (the only autoload) holds one instance and emits `changed(section)`. It is *not* a manager of gameplay: it is a lookup of values that physical toys read.

#### B.4.1 Sub-resources

```gdscript
class_name SensorySettings
extends Resource

@export_range(0.0, 1.0, 0.05) var flash: float = 0.5
@export_range(0.0, 1.0, 0.05) var shake: float = 0.3
@export_range(0.0, 1.0, 0.05) var motion: float = 0.8
@export_range(0.0, 1.0, 0.05) var particles: float = 0.8
@export_range(0.0, 1.0, 0.05) var dither: float = 0.6
@export_range(0.0, 1.0, 0.05) var storm_intensity: float = 0.6
@export var lightning_mode: LightningMode = LightningMode.SOFT_SWELL
@export var beacon_rotation_mode: BeaconMode = BeaconMode.SLOW_SWEEP
@export var allow_storms: bool = true
@export var reduce_parallax: bool = false
@export var film_grain: bool = false

enum LightningMode { OFF, STEADY_GLOW, SOFT_SWELL, FULL }
enum BeaconMode { FIXED_GLOW, SLOW_SWEEP, NORMAL_SWEEP }

## Hard safety cap: never exceeded even at flash=1.0, FULL lightning.
const MAX_FLASH_HZ: float = 3.0
const MAX_FLASH_AREA: float = 0.25   # fraction of screen
const MAX_LUMA_DELTA: float = 0.20   # max instantaneous ambient luminance step
```

```gdscript
class_name AudioAccessSettings
extends Resource

@export_range(0.0, 1.0, 0.01) var master: float = 0.8
@export_range(0.0, 1.0, 0.01) var music: float = 0.6
@export_range(0.0, 1.0, 0.01) var ambience: float = 0.7
@export_range(0.0, 1.0, 0.01) var sfx: float = 0.8
@export_range(0.0, 1.0, 0.01) var ui: float = 0.6
@export_range(0.0, 1.0, 0.01) var thunder: float = 0.5
@export_range(0.0, 1.0, 0.01) var voice_radio: float = 0.7
@export_range(0.0, 1.0, 0.05) var sudden_sound_softening: float = 0.4  # 0=raw, 1=heavily lowpassed & limited
@export var mute_ticking: bool = false          # clock, metronome-like loops
@export var sound_captions: bool = false        # diegetic pixel captions
@export var mono_downmix: bool = false
```

```gdscript
class_name PacingSettings
extends Resource

@export_range(8.0, 60.0, 1.0) var day_length_minutes: float = 18.0
@export var auto_drift: bool = true
@export_range(0.5, 2.0, 0.05) var animation_time_scale: float = 1.0   # >1 = slower/softer animations
@export var gentle_nudge_glow: bool = false    # soft pulse on next suggested toy
@export var interaction_hints: bool = false    # tiny text labels on hover
@export var quiet_idle_mode: bool = false      # hands-free ambient when idle for 60s
@export var skip_confirm_prompts: bool = true  # there are none that are destructive anyway
```

```gdscript
class_name InputAccessSettings
extends Resource

@export var click_to_toggle_drags: bool = false     # replaces hold-drag with click-pick/click-place
@export var tap_to_latch_holds: bool = false        # replaces hold with latch/unlatch
@export_range(0.0, 12.0, 0.5) var drag_smoothing_px: float = 3.0
@export_range(0.0, 1.0, 0.05) var assist_magnet: float = 0.4   # 0=none, 1=strong snap to valid target
@export_range(1.0, 2.0, 0.25) var hitbox_scale: float = 1.0
@export var one_handed_layout: bool = false
@export_range(0.0, 1.0, 0.05) var haptics: float = 0.6
@export var haptic_tick: bool = true
@export var haptic_thump: bool = true
@export var haptic_rumble: bool = true
@export var hold_duration_scale: float = 1.0        # multiplies any "hold N ms" requirement (>1 = shorter, easier)
```

```gdscript
class_name VisualAccessSettings
extends Resource

enum ColorFilter { NONE, PROTAN_SAFE, DEUTAN_SAFE, TRITAN_SAFE, HIGH_CONTRAST }
enum FontChoice { PIXEL_DEFAULT, PIXEL_DYSLEXIA }

@export var color_filter: ColorFilter = ColorFilter.NONE
@export var outline_interactables: bool = false
@export var font: FontChoice = FontChoice.PIXEL_DEFAULT
@export_enum("1x", "2x") var text_scale: int = 0   # integer scales only (pixel-perfect)
@export_range(0.0, 1.0, 0.05) var line_spacing: float = 0.0
@export var high_contrast_ui: bool = false
@export var integer_window_scale: int = 0  # 0 = auto largest integer fit, else forced
```

#### B.4.2 Root resource with presets, validation, and versioning

```gdscript
class_name AccessibilitySettings
extends Resource

const SAVE_PATH: String = "user://accessibility.tres"
const VERSION: int = 1

@export var version: int = VERSION
@export var preset_id: StringName = &"lantern"
@export var sensory: SensorySettings = SensorySettings.new()
@export var audio: AudioAccessSettings = AudioAccessSettings.new()
@export var pacing: PacingSettings = PacingSettings.new()
@export var input: InputAccessSettings = InputAccessSettings.new()
@export var visual: VisualAccessSettings = VisualAccessSettings.new()
@export var first_run_done: bool = false

static func load_or_default() -> AccessibilitySettings:
	if ResourceLoader.exists(SAVE_PATH):
		var res: Resource = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is AccessibilitySettings:
			var s: AccessibilitySettings = res
			s._migrate()
			s._clamp_all()
			return s
	return AccessibilitySettings.new()

func save() -> void:
	var err: Error = ResourceSaver.save(self, SAVE_PATH)
	if err != OK:
		push_warning("Accessibility settings failed to save: %s" % error_string(err))

func _migrate() -> void:
	if version < VERSION:
		# Add per-version upgrades here; never discard user values.
		version = VERSION

func _clamp_all() -> void:
	sensory.flash = clampf(sensory.flash, 0.0, 1.0)
	sensory.shake = clampf(sensory.shake, 0.0, 1.0)
	pacing.day_length_minutes = clampf(pacing.day_length_minutes, 8.0, 60.0)
	pacing.animation_time_scale = clampf(pacing.animation_time_scale, 0.5, 2.0)
	input.hitbox_scale = clampf(input.hitbox_scale, 1.0, 2.0)

func apply_preset(id: StringName) -> void:
	preset_id = id
	match id:
		&"lantern":   # default
			sensory = SensorySettings.new()
			audio = AudioAccessSettings.new()
			pacing = PacingSettings.new()
		&"slow_tide":
			pacing.day_length_minutes = 40.0
			pacing.animation_time_scale = 1.25
			sensory.storm_intensity = 0.25
			sensory.lightning_mode = SensorySettings.LightningMode.SOFT_SWELL
			audio.sudden_sound_softening = 0.7
		&"hold_the_hour":
			pacing.auto_drift = false
			pacing.animation_time_scale = 1.25
			sensory.storm_intensity = 0.25
		&"quiet_room":
			pacing.auto_drift = false
			pacing.animation_time_scale = 1.5
			sensory.flash = 0.0
			sensory.shake = 0.0
			sensory.motion = 0.25
			sensory.particles = 0.3
			sensory.dither = 0.0
			sensory.storm_intensity = 0.0
			sensory.allow_storms = false
			sensory.lightning_mode = SensorySettings.LightningMode.OFF
			sensory.beacon_rotation_mode = SensorySettings.BeaconMode.FIXED_GLOW
			sensory.reduce_parallax = true
			audio.thunder = 0.0
			audio.sudden_sound_softening = 1.0
			audio.mute_ticking = true
			audio.sound_captions = true
			input.haptics = 0.0
			input.click_to_toggle_drags = true
```

#### B.4.3 The `Settings` autoload (only autoload; value lookup + change signal)

```gdscript
extends Node
## res://autoload/settings.gd  (registered as "Settings")

signal changed(section: StringName)   # &"sensory", &"audio", &"pacing", &"input", &"visual"

var data: AccessibilitySettings
var sensory: SensorySettings : get = _get_sensory
var audio: AudioAccessSettings : get = _get_audio
var pacing: PacingSettings : get = _get_pacing
var input: InputAccessSettings : get = _get_input
var visual: VisualAccessSettings : get = _get_visual

func _enter_tree() -> void:
	data = AccessibilitySettings.load_or_default()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	apply_all()

func _get_sensory() -> SensorySettings: return data.sensory
func _get_audio() -> AudioAccessSettings: return data.audio
func _get_pacing() -> PacingSettings: return data.pacing
func _get_input() -> InputAccessSettings: return data.input
func _get_visual() -> VisualAccessSettings: return data.visual

## Call after mutating any field through the UI.
func commit(section: StringName) -> void:
	data.save()
	_apply_section(section)
	changed.emit(section)

func apply_preset(id: StringName) -> void:
	data.apply_preset(id)
	data.save()
	apply_all()
	for s: StringName in [&"sensory", &"audio", &"pacing", &"input", &"visual"]:
		changed.emit(s)

func apply_all() -> void:
	for s: StringName in [&"sensory", &"audio", &"pacing", &"input", &"visual"]:
		_apply_section(s)

func _apply_section(section: StringName) -> void:
	match section:
		&"audio":
			_set_bus(&"Master", data.audio.master)
			_set_bus(&"Music", data.audio.music)
			_set_bus(&"Ambience", data.audio.ambience)
			_set_bus(&"SFX", data.audio.sfx)
			_set_bus(&"UI", data.audio.ui)
			_set_bus(&"Thunder", data.audio.thunder * 0.7)  # extra headroom
			_set_bus(&"Radio", data.audio.voice_radio)
			_apply_sudden_softening(data.audio.sudden_sound_softening)
		&"visual":
			# Integer scaling is handled by project stretch settings (viewport + integer);
			# this only toggles overlays.
			pass

func _set_bus(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)

func _apply_sudden_softening(k: float) -> void:
	# Bus layout expects: SFX bus has AudioEffectLowPassFilter at fx slot 0
	# and AudioEffectHardLimiter at fx slot 1.
	var idx: int = AudioServer.get_bus_index(&"SFX")
	if idx < 0 or AudioServer.get_bus_effect_count(idx) < 2:
		return
	var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(idx, 0)
	lp.cutoff_hz = lerpf(20500.0, 4500.0, k)
	var lim: AudioEffectHardLimiter = AudioServer.get_bus_effect(idx, 1)
	lim.ceiling_db = lerpf(-0.3, -6.0, k)
	lim.pre_gain_db = lerpf(0.0, -2.0, k)

# ---- Shared helpers for toys (typed, tiny, no gameplay logic) ----

## Effective multiplier for any visual flash event. Toys call this, never read raw.
func flash_scale() -> float:
	return data.sensory.flash

func shake_px(base_px: float) -> float:
	return roundf(base_px * data.sensory.shake)   # integer pixel shake only

func anim_time(seconds: float) -> float:
	return seconds * data.pacing.animation_time_scale

func hold_time(seconds: float) -> float:
	return seconds / maxf(data.input.hold_duration_scale, 0.1)
```

### B.5 Flash Limiter (photosensitivity safety net)

A single `FlashGovernor` node (child of the world root, not an autoload) tracks luminance steps applied to the `CanvasModulate`/overlay and enforces the 3 Hz and delta caps regardless of what toys request. It is a physical "lightning" node's dependency only.

```gdscript
class_name FlashGovernor
extends Node

## Records the last N flash events (timestamps) and refuses/attenuates beyond the cap.
var _events: PackedFloat64Array = PackedFloat64Array()

## Returns a scalar 0..1 to multiply a requested flash amplitude by.
func request(amplitude: float, area_fraction: float) -> float:
	var s: SensorySettings = Settings.sensory
	if s.lightning_mode == SensorySettings.LightningMode.OFF:
		return 0.0
	var now: float = Time.get_ticks_msec() / 1000.0
	# drop events older than 1 s
	var keep: PackedFloat64Array = PackedFloat64Array()
	for e: float in _events:
		if now - e < 1.0:
			keep.append(e)
	_events = keep
	if _events.size() >= int(SensorySettings.MAX_FLASH_HZ):
		return 0.0
	_events.append(now)
	var k: float = s.flash
	k = minf(k, SensorySettings.MAX_LUMA_DELTA / maxf(amplitude, 0.001))
	if area_fraction > SensorySettings.MAX_FLASH_AREA:
		k *= SensorySettings.MAX_FLASH_AREA / area_fraction
	return clampf(k, 0.0, 1.0)
```

Lightning toy (soft swell variant, no sharp edges):

```gdscript
func _do_lightning() -> void:
	var mode := Settings.sensory.lightning_mode
	match mode:
		SensorySettings.LightningMode.OFF:
			return
		SensorySettings.LightningMode.STEADY_GLOW:
			_pulse_overlay(0.06, 1.2, 1.6)           # amp, rise, fall (s)
		SensorySettings.LightningMode.SOFT_SWELL:
			_pulse_overlay(0.12, 0.25, 0.9)
		SensorySettings.LightningMode.FULL:
			_pulse_overlay(0.20, 0.06, 0.5)
	_schedule_thunder(randf_range(1.2, 3.5))         # delayed rumble, scaled by thunder bus

func _pulse_overlay(amp: float, rise: float, fall: float) -> void:
	var k: float = governor.request(amp, 1.0)
	if k <= 0.0: return
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", amp * k, Settings.anim_time(rise))
	tw.tween_property(overlay, "modulate:a", 0.0, Settings.anim_time(fall))
```

### B.6 Low-Sensory Mode ("Quiet Room") Implementation Checklist

| System | Quiet Room behavior |
|---|---|
| Lightning | Off. Rain/wind sound only, softened. |
| Beacon | Fixed glow, no sweeping; light shafts static. |
| Palette remap | Hard crossfade 1.5 s instead of dithered mid-blend. |
| Particles | 30% count, speeds halved, no sparks (embers instead drift slowly). |
| Waves | Sprite animation frame rate halved; swell amplitude 25%. |
| Parallax | Collapsed. |
| Audio | Sudden sound softening 1.0; thunder muted; ticking muted; seagull variety reduced. |
| Haptics | Off. |
| UI | Captions on; click-to-toggle drags on; larger hitboxes (1.25x). |

### B.7 Satisfying Tactile Feedback Specification (audio-visual-haptic design)

Weight is communicated by **mass-consistent timing**: heavy things have longer anticipation and longer settle; light things the opposite. A single table defines the "feel budget" per object class so every toy is consistent.

| Class | Anticipation | Contact | Settle | SFX layers | Haptic | Example |
|---|---|---|---|---|---|---|
| Light (tick) | 0 ms | 1 frame squash (1 px) | 90 ms | click (high), tiny air | tick 10 ms @ 0.25 | tap barometer glass |
| Medium (button) | 40 ms (depress 1 px) | 1 frame flash highlight | 160 ms spring | click + body thock | thump 25 ms @ 0.4 | pressing stove knob |
| Heavy (lever/crank) | 80 ms (resistance ramp) | held hold-tension (sprite offset) | 320 ms overshoot + damp | metal clunk + low resonance + chain rattle | thump 60 ms @ 0.5 | winding crank, dropping weight |
| Fluid | n/a | continuous | drip tail 400 ms | squelch, drip pitch-varied | soft rumble ramp | kettle pour |
| Fire | 100 ms (rasp) | pop | flame bloom 300 ms | scratch + whoosh | tick then swell 120 ms | match strike |

#### B.7.1 Micro-interaction rules (apply to every interactable)

1. **Hover**: 1-frame outline shimmer, 2 px upward nudge (snapped) on sprite; never a bounce loop.
2. **Press**: depress 1 px immediately (sprite offset), no delay; SFX on frame 0.
3. **Release**: ease-out-back overshoot of at most 1 px, 120-180 ms; `animation_time_scale` multiplies all.
4. **Pitch variation**: each SFX uses `AudioStreamRandomizer` with ±4% pitch, ±1.5 dB volume; round-robin of 3-5 samples; prevents repetition fatigue (misophonia mitigation).
5. **Contact particles**: 2-6 pixel-particles, 1 px size, lifetime 0.25-0.6 s, count × `particles` setting.
6. **Pixel-snapping**: all tweens animate float "virtual" values; a `snap` script rounds the visual offset each frame. Never rotate sprites by arbitrary angles (use pre-drawn rotation frames or `RotatableSprite` with 16 steps).
7. **Haptic discipline**: haptic always accompanies an audio-visual contact, never alone; always scaled by `Settings.input.haptics`; no haptic when `Input.get_connected_joypads()` is empty.

Haptic helper (touch, no autoload; static so any toy can call):

```gdscript
class_name Haptics
extends RefCounted

enum Kind { TICK, THUMP, RUMBLE }

static func pulse(kind: Kind, device: int = 0) -> void:
	var s: InputAccessSettings = Settings.input
	if s.haptics <= 0.01: return
	match kind:
		Kind.TICK:
			if not s.haptic_tick: return
			Input.start_joy_vibration(device, 0.0, 0.25 * s.haptics, 0.010)
		Kind.THUMP:
			if not s.haptic_thump: return
			Input.start_joy_vibration(device, 0.35 * s.haptics, 0.15 * s.haptics, 0.050)
		Kind.RUMBLE:
			if not s.haptic_rumble: return
			# continuous callers re-trigger every 0.25 s with ramping weight; capped duration
			Input.start_joy_vibration(device, 0.2 * s.haptics, 0.1 * s.haptics, 0.25)
	if Input.get_connected_joypads().is_empty():
		pass  # mobile fallback below
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(int(30 * s.haptics))
```

Note on mobile: `Input.vibrate_handheld` is separate from joypads; port the guard properly in implementation (above is a sketch; ensure `device` exists before calling).

#### B.7.2 Squash/overshoot tween with pixel snapping

```gdscript
class_name TactileButton
extends Area2D

signal pressed

@export var sprite: Sprite2D
@export_enum("light", "medium", "heavy") var weight: String = "medium"
@export var sfx: AudioStreamPlayer2D

const PROFILE := {
	"light":  {"depress": 1.0, "settle": 0.09, "haptic": Haptics.Kind.TICK},
	"medium": {"depress": 1.0, "settle": 0.16, "haptic": Haptics.Kind.THUMP},
	"heavy":  {"depress": 2.0, "settle": 0.32, "haptic": Haptics.Kind.THUMP},
}

var _virtual_y: float = 0.0
var _base_y: float = 0.0
var _tween: Tween

func _ready() -> void:
	_base_y = sprite.position.y
	input_event.connect(_on_input_event)
	mouse_entered.connect(func() -> void: sprite.position.y = _base_y - 1.0)
	mouse_exited.connect(func() -> void: sprite.position.y = _base_y)

func _process(_d: float) -> void:
	sprite.position.y = roundf(_base_y + _virtual_y)   # pixel-snap

func _on_input_event(_vp: Node, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press()

func _press() -> void:
	var p: Dictionary = PROFILE[weight]
	if _tween: _tween.kill()
	_virtual_y = p.depress
	if sfx: sfx.play()
	Haptics.pulse(p.haptic)
	pressed.emit()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_virtual_y", 0.0, Settings.anim_time(p.settle))
```

---

## PART C: Tactile Micro-Mechanics

Common conventions:
- Input abstraction: each toy reads `Input` actions via a tiny `ToyInput` helper (pointer position in world space, `primary` pressed/held) with controller cursor emulation (right stick moves virtual hand, `ui_accept` = primary). No UI managers.
- Toggle alternative: when `Settings.input.click_to_toggle_drags` is on, the toy enters its `_toggle_mode` path (click once to grab, move, click again to release).
- Every state machine uses a plain `enum` + `match`; no heavy frameworks.
- All pixel counts are for 640x360.

### C.1 Wiping Condensation from Lantern-Room Glass

#### Fantasy / feel
A sheet of glass fogged with breath-and-sea-mist. The player drags a cloth (or the heel of the hand) across it; fog clears in soft-edged swaths revealing sharp pixel-art sea beyond. Gentle squeak with pitch correlating to speed; tiny water droplets (pixel beads) gather at wipe edges and slowly trickle.

#### Data structure
- A `SubViewport`/`Image`-backed **fog mask**: 160x90 cells (each cell = 4x4 screen px) for a window region (adjust to actual pane size; this is a 1-channel R8 image). Value 255 = fully fogged, 0 = clear. Low-res mask is upscaled with nearest neighbor and dithered by the shader for crisp pixel-art edges.
- `care` aggregate = 1 - mean(fog) computed every 0.5 s on a coarse 20x12 summary, not per-frame.

#### State machine

| State | Entry | Behaviour | Exit |
|---|---|---|---|
| `IDLE_FOGGED` | fog >= threshold | hover shimmer on cloth | pointer down on pane or cloth |
| `GRABBED` | cloth sprite attached to pointer (or latch) | cloth follows pointer smoothed | pointer moves over pane -> `WIPING` |
| `WIPING` | pointer over pane while held | stamp circular brush into mask; squeak audio; droplets | pointer up -> `GRABBED` or `IDLE` |
| `CLEAR` | fog < 0.05 | gentle chime, glints, no further input needed | fog rises above 0.15 -> `IDLE_FOGGED` |

#### Fog shader (pixel-quantized, dithered edge)

```glsl
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D fog_mask : filter_nearest, repeat_disable;  // R8, 0=clear 1=fog
uniform vec4 fog_color : source_color = vec4(0.82, 0.87, 0.90, 1.0);
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float dither : hint_range(0.0, 1.0) = 0.6;   // Settings.sensory.dither
uniform vec2 pane_px = vec2(160.0, 90.0);            // mask resolution

const float BAYER[16] = float[16](
	0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
	12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
	3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
	15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0);

void fragment() {
	float f = texture(fog_mask, UV).r;
	ivec2 px = ivec2(FRAGCOORD.xy);
	float thr = BAYER[(px.y % 4) * 4 + (px.x % 4)];
	// Dither only within the soft edge; fully fogged/clear areas stay stable.
	float edge = smoothstep(0.0, 0.35, f) * (1.0 - smoothstep(0.65, 1.0, f));
	float a = f;
	a = mix(step(0.5, f), step(thr, f), edge * dither);   // ordered threshold in edge band
	COLOR = vec4(fog_color.rgb, a * fog_opacity);
}
```

#### GDScript sketch

```gdscript
class_name GlassPane
extends Node2D

signal cleanliness_changed(clean: float)  # 0=foggy,1=clear

enum State { IDLE_FOGGED, GRABBED, WIPING, CLEAR }

const MASK_W: int = 160
const MASK_H: int = 90
const CELL_PX: int = 4
const BRUSH_RADIUS_CELLS: float = 4.5
const BRUSH_STRENGTH: float = 0.9      # fraction removed at center per stamp
const REFOG_PER_SEC: float = 0.0004    # tiny, bounded
const FOG_FLOOR: float = 0.35          # how fogged it ever gets at worst (care floor)

@export var cloth: Node2D
@export var fog_rect: TextureRect          # material = fog shader
@export var squeak: AudioStreamPlayer2D
@export var droplet_scene: PackedScene

var state: State = State.IDLE_FOGGED
var _img: Image
var _tex: ImageTexture
var _last_cell: Vector2 = Vector2.INF
var _wipe_speed: float = 0.0
var _summary_timer: float = 0.0
var _clean: float = 0.0
var _latched: bool = false

func _ready() -> void:
	_img = Image.create(MASK_W, MASK_H, false, Image.FORMAT_R8)
	_img.fill(Color(0.9, 0, 0, 1))        # start mostly fogged (0.9)
	_tex = ImageTexture.create_from_image(_img)
	fog_rect.texture = _tex
	var mat: ShaderMaterial = fog_rect.material
	mat.set_shader_parameter("dither", Settings.sensory.dither)
	Settings.changed.connect(func(s: StringName) -> void:
		if s == &"sensory": mat.set_shader_parameter("dither", Settings.sensory.dither))

func _process(delta: float) -> void:
	var ptr: Vector2 = get_global_mouse_position()
	var local: Vector2 = fog_rect.get_local_mouse_position()
	var inside: bool = Rect2(Vector2.ZERO, fog_rect.size).has_point(local)
	var down: bool = _is_primary_active()

	match state:
		State.IDLE_FOGGED, State.CLEAR:
			if down and _cloth_hit(ptr):
				state = State.GRABBED
		State.GRABBED:
			cloth.global_position = cloth.global_position.lerp(ptr, 1.0 - exp(-delta * _smooth()))
			cloth.global_position = cloth.global_position.round()
			if down and inside:
				state = State.WIPING
				_last_cell = Vector2.INF
			elif not down and not _latched:
				_release_cloth()
		State.WIPING:
			cloth.global_position = cloth.global_position.lerp(ptr, 1.0 - exp(-delta * _smooth())).round()
			if not (down and inside):
				state = State.GRABBED if _latched else State.IDLE_FOGGED
				squeak.stop()
			else:
				_stamp_line(local / float(CELL_PX), delta)

	_refog(delta)
	_summary_timer += delta
	if _summary_timer > 0.5:
		_summary_timer = 0.0
		_update_clean()

func _stamp_line(cell: Vector2, delta: float) -> void:
	if _last_cell == Vector2.INF:
		_last_cell = cell
	var dist: float = cell.distance_to(_last_cell)
	_wipe_speed = lerpf(_wipe_speed, dist / maxf(delta, 0.001), 0.3)
	var steps: int = maxi(1, int(ceil(dist / (BRUSH_RADIUS_CELLS * 0.5))))
	for i in steps + 1:
		_stamp(_last_cell.lerp(cell, float(i) / steps))
	_last_cell = cell
	_tex.update(_img)
	# squeak pitch follows wipe speed; volume gated so slow = quiet
	if not squeak.playing: squeak.play()
	squeak.pitch_scale = clampf(0.85 + _wipe_speed / 400.0, 0.85, 1.35)
	squeak.volume_db = linear_to_db(clampf(_wipe_speed / 120.0, 0.0, 1.0)) - 6.0

func _stamp(c: Vector2) -> void:
	var r: int = ceili(BRUSH_RADIUS_CELLS)
	var cx: int = int(c.x)
	var cy: int = int(c.y)
	for y in range(maxi(cy - r, 0), mini(cy + r + 1, MASK_H)):
		for x in range(maxi(cx - r, 0), mini(cx + r + 1, MASK_W)):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / BRUSH_RADIUS_CELLS
			if d <= 1.0:
				var falloff: float = 1.0 - d * d      # soft edge
				var cur: float = _img.get_pixel(x, y).r
				var next: float = maxf(cur - BRUSH_STRENGTH * falloff, 0.0)
				_img.set_pixel(x, y, Color(next, 0, 0, 1))
				if cur > 0.5 and next < 0.5 and randf() < 0.03 * Settings.sensory.particles:
					_spawn_droplet(Vector2(x, y) * CELL_PX)

func _refog(delta: float) -> void:
	# Extremely slow, bounded refogging; skip per-pixel loop by updating a global offset uniform
	# in a production version. Sketch: bump the whole image at low frequency.
	pass

func _update_clean() -> void:
	var sum: float = 0.0
	var n: int = 0
	for y in range(0, MASK_H, 4):
		for x in range(0, MASK_W, 4):
			sum += _img.get_pixel(x, y).r
			n += 1
	_clean = 1.0 - sum / float(n)
	cleanliness_changed.emit(_clean)
	if _clean > 0.95 and state != State.CLEAR:
		state = State.CLEAR
		$ChimeGlint.play()
	elif _clean < 0.85 and state == State.CLEAR:
		state = State.IDLE_FOGGED

func _spawn_droplet(pos: Vector2) -> void:
	if droplet_scene == null: return
	var d: Node2D = droplet_scene.instantiate()
	d.position = fog_rect.position + pos
	add_child(d)

func _smooth() -> float:
	# higher = snappier; drag_smoothing_px slider 0..12 maps to 40..8
	return remap(Settings.input.drag_smoothing_px, 0.0, 12.0, 40.0, 8.0)

func _is_primary_active() -> bool:
	if Settings.input.click_to_toggle_drags:
		if Input.is_action_just_pressed(&"primary"):
			_latched = not _latched
		return _latched
	return Input.is_action_pressed(&"primary")

func _cloth_hit(p: Vector2) -> bool:
	return cloth.global_position.distance_to(p) < 16.0 * Settings.input.hitbox_scale

func _release_cloth() -> void:
	state = State.IDLE_FOGGED
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cloth, "position", cloth.get_meta(&"rest_pos", cloth.position), Settings.anim_time(0.25))
```

Note: `_update_clean()` also feeds `care` to lantern shader parameter `glass_clarity` (see Part A lighting) so beam sharpness reflects glass state. The per-pixel loops are small (160x90 = 14,400 cells, only brush area per frame ~ 100 cells) and acceptable; production should use a `SubViewport` with a brush sprite and `CLEAR_MODE_NEVER` for GPU wiping if desired.

Feedback profile: squeak (3 samples, pitch by speed), micro-droplet beads, subtle 1 px cloth wobble; on CLEAR: 2-frame glint sparkle on pane corners + soft bell tone.

### C.2 Winding Clockwork Weights

#### Fantasy / feel
A heavy brass crank turns a ratchet that lifts a stone weight on a chain up the tower core. Each notch is a satisfying clack; resistance grows with weight height. Released (by letting the clutch free) the weight slowly descends, powering the lens rotation. Intuitive, rhythmic, forgiving.

#### Model
- `height` h in [0,1] (0 = bottom, 1 = top stop).
- Crank angle quantized to 12 positions (30° steps) with pre-drawn frames (pixel-clean).
- One full crank turn raises h by `TURN_GAIN` = 0.06 (about 17 turns for full wind; adjustable by `effort_scale`).
- Descent: `h' = -k * lens_load`, with `k = 1/ (descent_minutes*60)`. Default 12 min at full wind (adjustable, maps loosely to "beacon runs" but no fail).
- Lens angular speed `omega = base_omega * smoothstep(0, 0.15, h)`: when h falls below 0.15 the lens slows smoothly to a stop ("resting"), then glows steady. Never "game over".

| Quantity | Formula | Notes |
|---|---|---|
| Crank step | `angle_step = TAU/12` | frames 0..11 |
| Torque feel | `resist = 0.25 + 0.75 * h` | scales anticipation time and sfx pitch drop |
| Step time (min) | `step_t = lerp(0.10, 0.30, h) * anim_scale` | heavier near top |
| Ratchet clack pitch | `0.9 + 0.2 * (1.0 - h)` | higher when light |
| Descent rate | `dh/dt = -1 / (descent_minutes*60)` (only when clutch engaged and beacon lit) | |
| Lens omega | `omega = base * smoothstep(0.0, 0.15, h)` | `base = TAU / sweep_seconds` |

#### State machine

| State | Entry | Behaviour | Exit |
|---|---|---|---|
| `RESTING` | h ~ 0 or not engaged | lens still | player grabs crank |
| `GRIPPED` | pointer grabs | crank sprite follows | motion starts -> `WINDING` |
| `WINDING` | pointer angular motion about crank pivot | accumulates angle, steps every 30° in the *winding* direction only (ratchet prevents backward) | release -> `HOLDING` |
| `HOLDING` | pawl engaged | h constant, ratchet ticks quietly | clutch lever pulled -> `RUNNING` |
| `RUNNING` | clutch released | h decreases slowly, lens rotates | h<=0 -> `RESTING`; player winds more |
| (note) | | Winding while RUNNING is allowed; clutch stays engaged | |

```gdscript
class_name ClockworkWinder
extends Node2D

signal wound_notch(h: float)
signal height_changed(h: float)

enum State { RESTING, GRIPPED, WINDING, HOLDING, RUNNING }

const STEPS_PER_TURN: int = 12
const TURN_GAIN: float = 0.06

@export var crank: Sprite2D                     # 12-frame hframes sprite
@export var weight: Node2D                      # vertical position mapped from h
@export var weight_top_y: float = 20.0
@export var weight_bottom_y: float = 220.0
@export var descent_minutes: float = 12.0
@export var ratchet_sfx: AudioStreamPlayer2D
@export var chain_sfx: AudioStreamPlayer2D

var state: State = State.RESTING
var h: float = 0.0
var beacon_lit: bool = false
var clutch_engaged: bool = false

var _pivot: Vector2
var _last_angle: float = 0.0
var _accum: float = 0.0           # accumulated forward angle (rad)
var _frame: int = 0

func _ready() -> void:
	_pivot = crank.global_position
	_apply_visual()

func _process(delta: float) -> void:
	match state:
		State.RESTING, State.HOLDING, State.RUNNING:
			if _pressed_on_crank():
				_begin_grip()
		State.GRIPPED:
			_track(delta)
		State.WINDING:
			_track(delta)
	if state == State.RUNNING or (clutch_engaged and beacon_lit and h > 0.0):
		h = maxf(h - delta / (descent_minutes * 60.0), 0.0)
		if h <= 0.0 and state == State.RUNNING:
			state = State.RESTING
		_apply_visual()
		height_changed.emit(h)

func lens_omega(base_omega: float) -> float:
	return base_omega * smoothstep(0.0, 0.15, h)

func _begin_grip() -> void:
	state = State.GRIPPED
	_last_angle = (get_global_mouse_position() - _pivot).angle()
	chain_sfx.play()

func _track(_delta: float) -> void:
	if not _still_down():
		_end_grip()
		return
	var a: float = (get_global_mouse_position() - _pivot).angle()
	var da: float = wrapf(a - _last_angle, -PI, PI)
	_last_angle = a
	if da > 0.0:   # ratchet: only clockwise counts
		state = State.WINDING
		_accum += da
		var step: float = TAU / STEPS_PER_TURN
		while _accum >= step:
			_accum -= step
			_notch()
	# visual crank angle follows quantized frame only (pixel-clean)

func _notch() -> void:
	if h >= 1.0:
		# top stop: soft "tunk", no further gain, no penalty
		ratchet_sfx.pitch_scale = 0.7
		ratchet_sfx.play()
		Haptics.pulse(Haptics.Kind.THUMP)
		return
	h = minf(h + TURN_GAIN / STEPS_PER_TURN, 1.0)
	_frame = (_frame + 1) % STEPS_PER_TURN
	crank.frame = _frame
	ratchet_sfx.pitch_scale = 0.9 + 0.2 * (1.0 - h)
	ratchet_sfx.play()
	Haptics.pulse(Haptics.Kind.TICK)
	_apply_visual()
	wound_notch.emit(h)
	height_changed.emit(h)

func _end_grip() -> void:
	chain_sfx.stop()
	state = State.RUNNING if (clutch_engaged and beacon_lit and h > 0.0) else State.HOLDING
	_accum = 0.0

func _apply_visual() -> void:
	weight.position.y = roundf(lerpf(weight_bottom_y, weight_top_y, h))   # pixel snapped
	var resist: float = 0.25 + 0.75 * h
	chain_sfx.pitch_scale = lerpf(1.1, 0.8, resist)

func _pressed_on_crank() -> bool:
	return Input.is_action_just_pressed(&"primary") \
		and get_global_mouse_position().distance_to(_pivot) < 18.0 * Settings.input.hitbox_scale

func _still_down() -> bool:
	if Settings.input.click_to_toggle_drags:
		if Input.is_action_just_pressed(&"primary"):
			return false
		return true
	return Input.is_action_pressed(&"primary")
```

Alternative low-motor mode: `wind_by_keypress` — repeated `ui_accept` taps (or holding with auto-repeat at 4 Hz) each give 1/12 turn. Controller: rotate right stick clockwise (angle tracking on stick vector).

Weight descent visuals: weight sprite drifts down 1 px every `descent_minutes*60 / (bottom-top)` seconds (about 3.6 s per px at default), a calm visible clock without a number. Ticks are optional (`mute_ticking`).

### C.3 Striking Matches

#### Fantasy / feel
Matchbox in the tray. Player picks a match, holds it by the stick, drags the head along the rough strike strip on the box side. Too slow: only a scratch sound & a few sparks. Right speed with a short stroke: *ffsst*, flare of white then orange, flame stabilizes. Too hard/fast: also fine (just ignites in one go, tiny extra sparks). There is no way to waste a match; a failed strike just resets the head. Forgiving velocity window.

#### Model
Define stroke over the strip: collected `stroke_len` (px) and `peak_speed` (px/s). Ignition probability is a smooth function so players rarely fail, and failures teach by feel.

```
p_ignite(v, L) = smoothstep(40, 110, v) * smoothstep(8, 24, L)
```
where v = current pointer speed on strip, L = accumulated length. Accessibility scales: `p = 1 - (1 - p)^(1 + 2*assist)` with assist = `assist_magnet`. When `p` accumulates beyond a per-match hidden random threshold `T ~ U(0.55, 0.85)` the match ignites. If the player leaves the strip, the accumulated friction resets.

Flame visual lifetime: 8 s decay (`flame_energy` 1.0 -> 0.15) over ~8 s, purely visual; matches can be lit again by touching to another flame (candle) or replaced.

| State | Meaning | Visual |
|---|---|---|
| `IN_BOX` | match rests | static |
| `HELD` | attached to pointer | stick tilts toward motion (snapped to 8 angle frames) |
| `SCRATCHING` | head on strip | scratch SFX, sparks proportional to v |
| `FLARE` | ignition 150 ms | white-hot 3 frames, brightness pulse (flash channel scaled) |
| `BURNING` | steady | flame frames, light radius 24 px |
| `SPENT` | energy <0.15 or dropped in tray | curled charred stick, smoke wisp |

```gdscript
class_name Match
extends Node2D

signal ignited
signal spent

enum State { IN_BOX, HELD, SCRATCHING, FLARE, BURNING, SPENT }

@export var head: Marker2D
@export var flame: AnimatedSprite2D
@export var light: PointLight2D
@export var scratch_sfx: AudioStreamPlayer2D
@export var flare_sfx: AudioStreamPlayer2D
@export var strike_zone: Area2D         # on the matchbox; set in scene
@export var burn_seconds: float = 8.0

var state: State = State.IN_BOX
var energy: float = 0.0
var _threshold: float = 0.7
var _progress: float = 0.0
var _prev: Vector2
var _in_zone: bool = false

func _ready() -> void:
	flame.visible = false
	light.energy = 0.0
	_threshold = randf_range(0.55, 0.85)

func _process(delta: float) -> void:
	var ptr: Vector2 = get_global_mouse_position()
	match state:
		State.IN_BOX:
			if Input.is_action_just_pressed(&"primary") and global_position.distance_to(ptr) < 12.0 * Settings.input.hitbox_scale:
				state = State.HELD
				_prev = ptr
		State.HELD, State.SCRATCHING:
			global_position = ptr.round()
			var v: float = (ptr - _prev).length() / maxf(delta, 0.0001)
			_prev = ptr
			_in_zone = strike_zone.overlaps_area($HeadArea)
			if _in_zone and v > 15.0:
				state = State.SCRATCHING
				_scratch(v, delta)
			else:
				if state == State.SCRATCHING:
					scratch_sfx.stop()
				state = State.HELD
				_progress = maxf(_progress - delta * 0.5, 0.0)    # friction cools
			if not _holding():
				_drop()
		State.FLARE:
			pass   # driven by tween
		State.BURNING:
			global_position = ptr.round()
			energy = maxf(energy - delta / Settings.hold_time(burn_seconds), 0.15)
			light.energy = energy
			flame.scale = Vector2.ONE * lerpf(0.6, 1.0, energy)
			if energy <= 0.16:
				_spend()
			if not _holding():
				_drop()

func _scratch(v: float, delta: float) -> void:
	if not scratch_sfx.playing: scratch_sfx.play()
	scratch_sfx.pitch_scale = clampf(0.8 + v / 300.0, 0.8, 1.5)
	var speed_term: float = smoothstep(40.0, 110.0, v)
	var assist: float = Settings.input.assist_magnet
	var gain: float = speed_term * delta * 3.0 * (1.0 + 2.0 * assist)
	_progress += gain
	_emit_sparks(v)
	if _progress >= _threshold:
		_ignite()

func _emit_sparks(v: float) -> void:
	var n: int = int(clampf(v / 80.0, 0.0, 4.0) * Settings.sensory.particles)
	for i in n:
		var p := $SparkParticles as GPUParticles2D
		p.emitting = true   # one-shot configured in scene; count scaled by setting

func _ignite() -> void:
	state = State.FLARE
	scratch_sfx.stop()
	flare_sfx.play()
	Haptics.pulse(Haptics.Kind.THUMP)
	flame.visible = true
	flame.play(&"flare")
	var peak: float = 1.0 + 0.8 * Settings.flash_scale()      # brighter pop scaled by flash setting
	var tw := create_tween()
	tw.tween_property(light, "energy", peak, Settings.anim_time(0.06))
	tw.tween_property(light, "energy", 1.0, Settings.anim_time(0.2))
	tw.tween_callback(func() -> void:
		state = State.BURNING
		energy = 1.0
		flame.play(&"burn")
		ignited.emit())

func _spend() -> void:
	state = State.SPENT
	var tw := create_tween()
	tw.tween_property(light, "energy", 0.0, Settings.anim_time(0.6))
	flame.play(&"smoulder")
	spent.emit()
	# the tray removes the spent match in a day-end cleanup (cosmetic)

func _drop() -> void:
	scratch_sfx.stop()
	if state == State.BURNING:
		# gentle fall toward tray with the flame fading, never extinguishes violently
		state = State.SPENT
		spent.emit()
	else:
		state = State.IN_BOX
		global_position = get_meta(&"box_pos", global_position)

func _holding() -> bool:
	if Settings.input.click_to_toggle_drags:
		return not Input.is_action_just_pressed(&"primary") or state == State.IN_BOX
	return Input.is_action_pressed(&"primary")

## Called by wick/candle/stove burner Area2D when overlapped while BURNING.
func offer_flame(target: Node) -> void:
	if state == State.BURNING and target.has_method(&"receive_flame"):
		target.receive_flame(energy)
```

Flare light is the **only** abrupt luminance event in this toy; it's at most +0.8 energy over 60 ms on a 24 px radius light (small area), scaled by `flash` setting, and omitted at flash=0 (peak=1.0).

### C.4 Boiling a Kettle

#### Fantasy / feel
Cast-iron or enamel kettle on a small stove. The player fills it (tap/barrel), sets it on the burner, lights the burner (with a match), and listens/watches: faint ticks as metal warms, tiny bubbles at the spout seen through steam, the lid starts to jiggle, steam wisps thicken, then a gentle rising whistle. No timer UI, no burn: the kettle simply reaches a "boiled" plateau and stays pleasant. Player can pour any time.

#### Physics-lite model (visible but never harsh)
Temperature T (°C) of water, energy-balance:

```
dT/dt = (P_burner * eff - k_loss * (T - T_room)) / (m * c)
```
Simplified for game: normalized `heat` in [0,1] mapping T=20..100.

| Variable | Default | Meaning |
|---|---|---|
| `heat` | 0.0 | 0=cold, 1=boiling |
| `water` | 0..1 | fill level (0.3 min to heat) |
| `burner_power` | 0.0 / 1.0 (low/high) | lit state, adjustable knob 0..1 |
| `heat_rate` | `burner_power * 0.06 / max(water, 0.2)` per s | ~17 s for 1.0 water at full power (tunable; `animation_time_scale` scales it slower for meditative) |
| `cool_rate` | `0.01` per s when off | cools slowly |
| `whistle_gain` | `smoothstep(0.85, 1.0, heat)` | whistle volume/pitch factor, passes through sudden-sound softening |

Because a countdown stress is a risk, the kettle never has a "ready by" requirement and never over-boils.

#### State machine

| State | Entry | Behaviour | Exit |
|---|---|---|---|
| `EMPTY` | dry | light, tap fill | water > 0.2 -> `FILLED` |
| `FILLED` | water present, off burner | sloshing sprite on move | placed on burner -> `ON_BURNER_COLD` |
| `ON_BURNER_COLD` | on stove, burner off | tick-free silence | burner lit -> `HEATING` |
| `HEATING` | heat < 0.85 | ticks, bubbles grow, steam grows | heat >= 0.85 -> `SIMMER` |
| `SIMMER` | 0.85..1.0 | lid jiggle, light steam, rising hum | heat >= 1.0 -> `BOILING` |
| `BOILING` | heat = 1 | whistle (gentle, loops ~4 s then fades into soft rumble), big steam | burner off -> `COOLING`; or pour -> `POURING` |
| `POURING` | tilt kettle | water stream particles, level lowers, steam puff | level 0 -> `EMPTY` |
| `COOLING` | burner off | heat decays | heat < 0.3 -> `FILLED` |

```gdscript
class_name Kettle
extends Node2D

signal boiled
signal poured(amount: float, temp01: float)

enum State { EMPTY, FILLED, ON_BURNER_COLD, HEATING, SIMMER, BOILING, POURING, COOLING }

const HEAT_PER_SEC: float = 0.06
const COOL_PER_SEC: float = 0.01
const POUR_PER_SEC: float = 0.35

@export var steam: GPUParticles2D
@export var lid: Node2D
@export var whistle: AudioStreamPlayer2D
@export var bubble_sfx: AudioStreamPlayer2D
@export var tick_sfx: AudioStreamPlayer2D
@export var stream: GPUParticles2D

var state: State = State.EMPTY
var water: float = 0.0
var heat: float = 0.0
var burner_power: float = 0.0         # set by stove knob each frame
var on_burner: bool = false
var _tick_accum: float = 0.0
var _lid_phase: float = 0.0

func _process(delta: float) -> void:
	var time_scale: float = 1.0 / Settings.pacing.animation_time_scale   # >1 setting = slower
	match state:
		State.EMPTY:
			if water > 0.2: state = State.FILLED
		State.FILLED:
			if on_burner: state = State.ON_BURNER_COLD
		State.ON_BURNER_COLD:
			if not on_burner: state = State.FILLED
			elif burner_power > 0.05: state = State.HEATING
		State.HEATING:
			_heat(delta * time_scale)
			_tick_tones(delta)
			if heat >= 0.85: state = State.SIMMER
			if burner_power <= 0.05: state = State.COOLING
		State.SIMMER:
			_heat(delta * time_scale)
			_lid_jiggle(delta, 0.5)
			if heat >= 1.0:
				state = State.BOILING
				boiled.emit()
				Haptics.pulse(Haptics.Kind.TICK)
			if burner_power <= 0.05: state = State.COOLING
		State.BOILING:
			_lid_jiggle(delta, 1.0)
			if burner_power <= 0.05: state = State.COOLING
		State.COOLING:
			heat = maxf(heat - COOL_PER_SEC * delta, 0.0)
			_lid_jiggle(delta, 0.0)
			if heat < 0.3: state = State.FILLED if water > 0.0 else State.EMPTY
			elif burner_power > 0.05 and on_burner: state = State.HEATING
		State.POURING:
			var amt: float = POUR_PER_SEC * delta
			water = maxf(water - amt, 0.0)
			poured.emit(amt, heat)
			if water <= 0.0:
				stream.emitting = false
				state = State.EMPTY
	_update_audio_visuals()

func _heat(delta: float) -> void:
	var rate: float = burner_power * HEAT_PER_SEC / maxf(water, 0.2)
	heat = minf(heat + rate * delta, 1.0)

func _tick_tones(delta: float) -> void:
	_tick_accum += delta * lerpf(0.5, 3.0, heat)       # ticking accelerates with heat
	if _tick_accum >= 1.0 and not Settings.audio.mute_ticking:
		_tick_accum = 0.0
		tick_sfx.pitch_scale = randf_range(0.95, 1.08)
		tick_sfx.play()

func _lid_jiggle(delta: float, amount: float) -> void:
	_lid_phase += delta * lerpf(8.0, 22.0, heat)
	# 1 px jiggle snapped, scaled by motion setting
	var off: float = sin(_lid_phase) * amount * Settings.sensory.motion
	lid.position.y = roundf(off)
	if amount > 0.7 and Settings.sensory.motion > 0.0:
		lid.rotation = 0.0   # no rotation, pixel-art safe

func _update_audio_visuals() -> void:
	var gain: float = smoothstep(0.85, 1.0, heat)
	steam.amount_ratio = clampf(heat * Settings.sensory.particles, 0.0, 1.0)
	steam.emitting = heat > 0.2 and Settings.sensory.particles > 0.0
	if state == State.BOILING:
		if not whistle.playing: whistle.play()
		whistle.volume_db = linear_to_db(0.25 + 0.5 * gain)
		whistle.pitch_scale = 1.0 + 0.05 * sin(Time.get_ticks_msec() * 0.003)
	else:
		whistle.stop()

# ---- Interactions (called by player-driven nodes) ----
func fill(rate: float, delta: float) -> void:
	water = minf(water + rate * delta, 1.0)
	if state == State.EMPTY and water > 0.2:
		state = State.FILLED

func begin_pour() -> void:
	if water > 0.0 and heat > 0.0 and state in [State.BOILING, State.SIMMER, State.COOLING, State.FILLED, State.HEATING]:
		state = State.POURING
		stream.emitting = true

func end_pour() -> void:
	if state == State.POURING:
		stream.emitting = false
		state = State.FILLED if water > 0.0 else State.EMPTY
```

Whistle design: soft sine+noise whistle, attack 400 ms, loops ~4 s then crossfades to a lower rumble; `Thunder`-like "sudden sound softening" low-pass also applies since it's on the SFX bus. Captions mode shows a small `~` pixel whistle glyph above the spout.

### C.5 Cross-cutting Implementation Notes

#### C.5.1 Pixel-snapped transform utility (for every toy)

```gdscript
class_name PixelSnap
extends Node

## Attach as child of any Node2D whose visual position floats. Snaps parent's
## `visual` child to integer positions each frame without altering logic position.
@export var visual: Node2D

func _process(_d: float) -> void:
	var gp: Vector2 = get_parent().global_position
	visual.global_position = gp.round()
```

Project settings required (manual action by project owner; not edited here): `rendering/2d/snap/snap_2d_transforms_to_pixel = true`, `snap_2d_vertices_to_pixel = true`, `display/window/stretch/mode = "viewport"`, `scale_mode = "integer"`, default texture filter `Nearest`.

#### C.5.2 Light + Glass interplay

`glass_clarity` (from `GlassPane.cleanliness_changed`) feeds the beam shader: lower clarity widens soft halo and lowers beam contrast, never zeroing it.

```glsl
shader_type canvas_item;
uniform float glass_clarity : hint_range(0.0, 1.0) = 1.0;
uniform float beam_width_px = 14.0;
uniform float halo_px = 22.0;
uniform vec4 beam_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);

void fragment() {
	// UV.x across beam; 0.5 = center line
	float d = abs(UV.x - 0.5) * beam_width_px * 2.0;
	float core = 1.0 - smoothstep(0.0, beam_width_px * 0.5, d);
	float halo = 1.0 - smoothstep(0.0, halo_px, d);
	float k = mix(halo * 0.55, core, glass_clarity);   // clean glass => crisp core
	// quantize to 5 levels for pixel-art banding consistent with palette
	k = floor(k * 5.0 + 0.5) / 5.0;
	COLOR = vec4(beam_color.rgb, k * (1.0 - UV.y * 0.6));
}
```

#### C.5.3 Test checklist (headless-friendly)

| Test | Pass criterion |
|---|---|
| No timers | Grep: no `Timer` node or `await get_tree().create_timer` gates progression; only cosmetic durations. |
| Flash cap | Spam `_do_lightning()` 20x in 1 s: governor allows <= 3; luminance delta <= 0.20. |
| Quiet Room | Applying preset yields lightning OFF, haptics 0, beacon FIXED_GLOW, dither 0. |
| Click-to-toggle | Each of C.1-C.4 completable using only discrete clicks. |
| Keyboard/gamepad | Each toy completable with virtual cursor, no stick-precision requirement beyond hitbox_scale. |
| Pixel clean | Screenshot diff at 640x360: no non-integer sprite positions; no sub-pixel rotation. |
| Idle | Leaving game 30 min: no state degenerates below `FOG_FLOOR`, weights rest, no failure messaging. |
| Resolution | Verify `project.godot` viewport = 640x360 (currently 320x180) before building art. |

#### C.5.4 Scene tree sketch (for orientation, minimal)

```
World (Node2D)
├─ DayCycle (Node)
├─ FlashGovernor (Node)
├─ CanvasModulate                       # ambient from ambient_for(t)
├─ Sky/Sea/Parallax...                  # pixel layers
└─ Tower
   ├─ LanternRoom
   │  ├─ BeaconLamp (+PointLight2D)
   │  ├─ GlassPane (x N panes)          # C.1
   │  ├─ MatchBox + Match               # C.3
   │  └─ LensRotator                    # reads ClockworkWinder.lens_omega
   ├─ CoreShaft
   │  └─ ClockworkWinder                # C.2
   ├─ Kitchen
   │  ├─ Stove + Kettle + Cup + Jars    # C.4, A.4.5
   │  └─ Radio (settings knob)
   └─ Study
      ├─ Journal                        # A.4.6
      └─ Barometer / Telescope          # A.4.3
```

Each node owns its logic; communication via signals along this tree (e.g. `Match.ignited -> BeaconLamp.receive_flame`, `GlassPane.cleanliness_changed -> LanternRoom.set_glass_clarity`).

---

## Appendix: Quick Reference Tunables

| Name | Default | Range | Where |
|---|---|---|---|
| day_length_minutes | 18 | 8-60 | PacingSettings |
| animation_time_scale | 1.0 | 0.5-2.0 | PacingSettings |
| beacon_ignite_seconds | 3.0 | 1.0-6.0 | BeaconLamp |
| sweep_seconds | 12 | 6-30 | LensRotator |
| match burn seconds | 8 | n/a (cosmetic) | Match |
| descent_minutes (weights) | 12 | 6-30 | ClockworkWinder |
| kettle HEAT_PER_SEC | 0.06 | 0.02-0.12 | Kettle |
| glass FOG_FLOOR | 0.35 | n/a | GlassPane |
| MAX_FLASH_HZ | 3 | fixed | SensorySettings |
| MAX_LUMA_DELTA | 0.20 | fixed | SensorySettings |
| haptics | 0.6 | 0-1 | InputAccessSettings |

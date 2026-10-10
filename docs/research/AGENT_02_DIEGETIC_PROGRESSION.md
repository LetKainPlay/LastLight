# AGENT 02: Diegetic Narrative and Non-Punitive Progression

Project: Last Light (Godot 4.7.2, GDScript 2.0, static typing).
Scope: (a) solitary storytelling (environment, passing ships, morse/horn, logbook, seasons); (b) comfort-based progression (Resources, save schema, diegetic display).

Resolution note: `project.godot` currently has a 320x180 viewport. The brief targets 640x360 (integer scale 2x to 1280x720, 3x to 1920x1080). All pixel coordinates below assume 640x360. Do not mix: a 320x180 prop is half the size. Flag to the integrator; this document does not edit project files.

---

## 0. Governing Rules

| Rule | Consequence in this spec |
|---|---|
| No fail states | No hunger, fuel, health, durability, deadlines. A neglected lamp is dusty, never dead. |
| No punishing timers | Ships come and go; missing one is a gentler story, not a loss. Every ship may return later in the season. |
| Toy over tool | Every system is a node you can poke: a brass key, a hanging lamp, a rain barrel. No "Upgrades" menu, no stat screen. |
| Anti-enterprise | One thin autoload (`Island`), plain `Resource` files, signals. No managers of managers, no service locators, no CRUD screens. |
| Diegetic first | Progress is visible in the room: more rugs, warmer light, better tea smell, polished brass glint. Numbers never shown. |
| Pixel integrity | Props are authored at 640x360 native; no sub-pixel movement; text drawn in the scene (paper, chalk) with a bitmap font at integer sizes. |

---

# PART A: NARRATIVE FRAMEWORK FOR SOLITARY STORYTELLING

## A1. Story Premise Constraint

The keeper is alone. The story is **inferred**, not told. Voices reach the player only through four channels:

1. **Objects** left by earlier keepers (environmental storytelling).
2. **Ships** passing at distance: horn blasts, lamp flashes, morse, occasional bottle or parcel.
3. **The logbook**: the keeper's own hand, written by the game when meaningful moments pass.
4. **Weather and season**: the island's own mood.

There are no dialogue trees, no portraits, no quest markers. Names appear only in logbook ink and on ship hulls.

## A2. Environmental Storytelling

### A2.1 Principle: a prop is a sentence

Each story prop is a `Node2D` with an `Interactable` child area (hover = faint outline pulse, click = a one-line caption in a paper strip, no modal). Props are placed by the scene, not spawned by a system. Captions are data (see A2.3).

### A2.2 Prop inventory (first island, first-pass content)

| Prop ID | Location | Reveals | Revealed when |
|---|---|---|---|
| `pencil_marks_doorframe` | Lower stairwell | Height marks of a child, dated by year, last mark 11 years old | Always |
| `second_cup` | Kitchen shelf | A second mug, chipped, kept clean | Always |
| `postcard_pinned` | Lamp-room wall | Postcard from "M." in a warm place, 'wish you would come' | Unlocked after 3 logbook entries |
| `chess_unfinished` | Landing table | A game left mid-play, white to move | Always; player can move one piece, logbook notes it |
| `barometer_taps` | Hall | Scratch tally behind glass of storms survived | Grows by one per storm weather event experienced |
| `stairs_worn_left` | Stair sprite | Left edge of each step worn smoother than right | Visual only |
| `sea_chart_pins` | Study | Pins for every ship that ever answered; new pin each ship met | Pin added per ship encounter |
| `lamp_oil_ledger` | Workbench | Previous keeper's tidy columns, then a final line trailing off | Always |
| `child_drawing` | Under bed | A lighthouse drawn with a smiling sun | Seasonal: appears first spring |
| `empty_hook` | Door | Coat hook with nothing; later holds a gift scarf | Scarf unlocks via ship gift |

### A2.3 Data: `StoryProp` resource

```gdscript
class_name StoryProp
extends Resource

@export var id: StringName
@export_multiline var caption: String = ""            # shown on click, <= 90 chars
@export var requires_flags: PackedStringArray = []    # all must be set in SaveData.flags
@export var requires_season: int = -1                 # Season enum; -1 = any
@export var sets_flag: StringName = &""               # set on first inspect
@export var logbook_entry_id: StringName = &""        # optional entry appended on first inspect
```

```gdscript
class_name StoryPropNode
extends Node2D

@export var data: StoryProp

@onready var _area: Area2D = $Area2D
@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	visible = _is_available()
	Island.flags_changed.connect(func() -> void: visible = _is_available())
	_area.input_event.connect(_on_input)
	_area.mouse_entered.connect(func() -> void: _sprite.material = preload("res://fx/outline_pulse.tres"))
	_area.mouse_exited.connect(func() -> void: _sprite.material = null)

func _is_available() -> bool:
	for f: String in data.requires_flags:
		if not Island.has_flag(StringName(f)):
			return false
	return data.requires_season == -1 or data.requires_season == Island.season

func _on_input(_vp: Node, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Island.show_caption(data.caption)
		if data.sets_flag != &"":
			Island.set_flag(data.sets_flag)
		if data.logbook_entry_id != &"":
			Island.logbook_write(data.logbook_entry_id)
```

### A2.4 Rules of environmental storytelling

- Never confirm. The postcard never says who M. is; the second cup never says whose.
- Contradiction is allowed: chess says "unfinished", logbook later says "I finished it for them." Player decides.
- Maximum one new prop reveal per in-game day. Rationed by `Island.last_reveal_day`.

## A3. Seasons and Weather

### A3.1 Calendar

A "day" is a ~6 real-minute cycle (dawn, noon, dusk, night). A season is 7 days. Year = 28 days. Time does not advance while the game is closed (no catch-up punishment). Optionally the player can sleep (click bed) to skip to next dawn.

```gdscript
enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { CLEAR, FOG, RAIN, STORM, SNOW, AURORA, GOLDEN }
```

### A3.2 Weather table (weighted by season)

| Weather | Spring | Summer | Autumn | Winter | Visual (pixel) | Cozy payoff |
|---|---|---|---|---|---|---|
| CLEAR | 30 | 55 | 25 | 20 | blue sky, 3-tone gradient bands | Gulls, open window |
| FOG | 20 | 5 | 30 | 15 | 2 parallax fog layers, palette lerp to grey-lilac | Foghorn duty fun; horns from ships audible |
| RAIN | 35 | 10 | 30 | 5 | diagonal 1px streaks, GPUParticles2D | Raincatcher fills; window drops |
| STORM | 5 | 10 | 10 | 15 | rain + lightning flash frames, sea swells | Barometer tally, hot tea scene |
| SNOW | 0 | 0 | 0 | 30 | 2x2 flakes drifting | Footprints, stove glow |
| AURORA | 0 | 0 | 0 | 10 | green/violet band shader | Rare; logbook entry |
| GOLDEN | 10 | 20 | 5 | 0 | warm tint, long shadows | Rug sunlit, dust motes |

```gdscript
class_name WeatherTable
extends Resource

@export var weights_by_season: Dictionary = {}   # Season(int) -> { Weather(int): weight(int) }

func roll(season: int, rng: RandomNumberGenerator) -> int:
	var w: Dictionary = weights_by_season[season]
	var total: int = 0
	for k: int in w:
		total += w[k] as int
	var pick: int = rng.randi_range(1, total)
	for k: int in w:
		pick -= w[k] as int
		if pick <= 0:
			return k
	return Weather.CLEAR
```

Weather is rolled once per day at dawn from a seeded RNG: `seed = hash(save.world_seed, day_index)`. The day's weather is therefore deterministic per save, so reload does not reroll a storm away or into existence.

### A3.3 Season-keyed diegetic changes

| Season | Palette shift | Island | Interior | Ship traffic |
|---|---|---|---|---|
| Spring | Fresh greens, pale sky | Wildflower tiles bloom on cliff | Window ajar, curtains lift | Fishing boats, many horns |
| Summer | Saturated, long dusk | Gulls, tall grass | Cool tea (iced variant) | Yachts, tourists wave |
| Autumn | Amber, rust | Falling leaf particles | Stove first lit | Cargo, gruff horns |
| Winter | Slate blue, snow | Ice on rail, footprints | Frosted glass, fire, wool rug | Few ships; each is an event |

Palette shift is a single `CanvasModulate` with a 1D LUT shader keyed to `season + time_of_day`. Do not recolor sprites per season.

## A4. Passing Ships

### A4.1 Concept

Ships cross the horizon on a fixed lane (parallax layer, y-band 140-170 px at 640x360). Each ship is a small pixel sprite (24-48 px wide) with a lamp pixel. When a ship is within hailing range (center third of screen) it sends a **greeting**: a horn pattern, a lamp-flash morse message, or both. The player may **answer** using the brass signal key (a toy on the desk) or the foghorn lever or the signal lamp shutter. Answering is optional; unanswered ships simply drift on. No penalty. Answered ships remember you and may later send gifts.

Ship greetings are never urgent. There is no distress mechanic that fails.

### A4.2 Horn vocabulary (pre-morse for non-learners)

| Pattern | Meaning (in-world) | Player response |
|---|---|---|
| 1 short | "Hello." | 1 short |
| 2 short | "Good morning/evening." | 2 short |
| 1 long | "Passing, safe water." | 1 long |
| long-short-short | "Thank you." (morse D=-.. is unused; here LSS) | optional |
| 3 short | "Engines astern; slow here." Trivia only | any |
| long-long | "Farewell until next time." | long-long |

Horns are played by an `AudioStreamPlayer2D` with pitch by ship class (tug high, freighter very low). Horn patterns use the same `MorsePlayer` timing with `tone_hz` lowered and a sample instead of sine.

### A4.3 Morse encoding table (ITU, subset)

| Char | Code | Char | Code | Char | Code |
|---|---|---|---|---|---|
| A | .- | N | -. | 0 | ----- |
| B | -... | O | --- | 1 | .---- |
| C | -.-. | P | .--. | 2 | ..--- |
| D | -.. | Q | --.- | 3 | ...-- |
| E | . | R | .-. | 4 | ....- |
| F | ..-. | S | ... | 5 | ..... |
| G | --. | T | - | 6 | -.... |
| H | .... | U | ..- | 7 | --... |
| I | .. | V | ...- | 8 | ---.. |
| J | .--- | W | .-- | 9 | ----. |
| K | -.- | X | -..- | ? | ..--.. |
| L | .-.. | Y | -.-- | . | .-.-.- |
| M | -- | Z | --.. | , | --..-- |

Timing (unit = `u` seconds; default 0.12 s at 10 WPM-ish for cozy readability, configurable):

| Element | Duration |
|---|---|
| dot | 1u on |
| dash | 3u on |
| gap inside letter | 1u off |
| gap between letters | 3u off |
| gap between words | 7u off |

### A4.4 GDScript: `Morse` (static codec)

```gdscript
class_name Morse
extends RefCounted

const TABLE: Dictionary = {
	"A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
	"G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
	"M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
	"S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
	"Y": "-.--", "Z": "--..",
	"0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
	"5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
	"?": "..--..", ".": ".-.-.-", ",": "--..--",
}

static var _reverse: Dictionary = {}

static func _ensure_reverse() -> void:
	if not _reverse.is_empty():
		return
	for ch: String in TABLE:
		_reverse[TABLE[ch]] = ch

## "SOS ME" -> "... --- ... / -- ."   (letters space-separated, words " / ")
static func encode(text: String) -> String:
	var words: PackedStringArray = text.to_upper().split(" ", false)
	var out_words: PackedStringArray = []
	for w: String in words:
		var letters: PackedStringArray = []
		for i: int in w.length():
			var c: String = w[i]
			if TABLE.has(c):
				letters.append(TABLE[c] as String)
		out_words.append(" ".join(letters))
	return " / ".join(out_words)

## Inverse of encode. Unknown groups become "#".
static func decode(code: String) -> String:
	_ensure_reverse()
	var out: String = ""
	for word: String in code.split(" / ", false):
		for group: String in word.split(" ", false):
			out += _reverse.get(group, "#") as String
		out += " "
	return out.strip_edges()

## Timeline of [is_on, duration_in_units] pairs for playback.
static func to_timeline(text: String) -> Array[Vector2i]:
	var line: Array[Vector2i] = []
	var words: PackedStringArray = text.to_upper().split(" ", false)
	for wi: int in words.size():
		var w: String = words[wi]
		for li: int in w.length():
			var code: String = TABLE.get(w[li], "") as String
			for ei: int in code.length():
				line.append(Vector2i(1, 1 if code[ei] == "." else 3))
				if ei < code.length() - 1:
					line.append(Vector2i(0, 1))
			if li < w.length() - 1:
				line.append(Vector2i(0, 3))
		if wi < words.size() - 1:
			line.append(Vector2i(0, 7))
	return line
```

### A4.5 GDScript: `MorsePlayer` (lamp, tone, or horn)

Emits signals so any physical prop can listen: the lamp shutter sprite, a ship's lamp pixel, a horn.

```gdscript
class_name MorsePlayer
extends Node

signal key_down
signal key_up
signal finished

@export var unit_seconds: float = 0.12
@export var tone_hz: float = 620.0
@export var is_horn: bool = false
@export var horn_sample: AudioStream

var _tone: AudioStreamPlayer
var _playing: bool = false

func _ready() -> void:
	_tone = AudioStreamPlayer.new()
	_tone.bus = &"SFX"
	add_child(_tone)
	_tone.stream = horn_sample if is_horn and horn_sample != null else _make_sine(tone_hz)

func play_text(text: String) -> void:
	if _playing:
		return
	_playing = true
	var line: Array[Vector2i] = Morse.to_timeline(text)
	for seg: Vector2i in line:
		var d: float = float(seg.y) * unit_seconds
		if seg.x == 1:
			_on()
		else:
			_off()
		await get_tree().create_timer(d).timeout
	_off()
	_playing = false
	finished.emit()

func _on() -> void:
	_tone.volume_db = -8.0
	if not _tone.playing:
		_tone.play()
	key_down.emit()

func _off() -> void:
	_tone.stop()
	key_up.emit()

## Looping 16-bit mono sine, 0.1 s loop; click-free if hz*0.1 is integral-ish.
func _make_sine(hz: float) -> AudioStreamWAV:
	var rate: int = 22050
	var cycles: int = maxi(1, roundi(hz * 0.1))
	var n: int = roundi(float(cycles) / hz * rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	for i: int in n:
		var s: int = roundi(sin(TAU * float(cycles) * float(i) / float(n)) * 12000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	w.data = data
	return w
```

Note: `await` inside a loop in a node that frees mid-play is safe (timer holds a reference to the tree); guard with `is_inside_tree()` if the player can leave the scene.

### A4.6 GDScript: `MorseKey` (player-side telegraph key) and decoder

The key is a physical brass toy. Holding the mouse or Space on it sends tone and flashes the lamp. Timing is classified into dot/dash relative to the unit, adaptive to the player's tempo.

```gdscript
class_name MorseKey
extends Node2D

signal letter_decoded(ch: String)
signal message_decoded(text: String)

@export var unit_seconds: float = 0.12
@export var letter_gap_units: float = 2.0     # gap longer than this ends a letter
@export var word_gap_units: float = 5.0       # gap longer than this ends a word

@onready var _player: MorsePlayer = $MorsePlayer

var _pressed_at: float = -1.0
var _released_at: float = -1.0
var _buffer: String = ""      # current letter, e.g. ".-"
var _text: String = ""
var _gap_timer: Timer

func _ready() -> void:
	_gap_timer = Timer.new()
	_gap_timer.one_shot = true
	_gap_timer.timeout.connect(_on_gap_timeout)
	add_child(_gap_timer)

func press() -> void:
	_gap_timer.stop()
	_pressed_at = Time.get_ticks_msec() / 1000.0
	_player._on()

func release() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var held: float = now - _pressed_at
	_player._off()
	# dot if shorter than 2 units, else dash
	_buffer += "." if held < unit_seconds * 2.0 else "-"
	_gap_timer.start(unit_seconds * letter_gap_units)

var _letter_done: bool = false

func _on_gap_timeout() -> void:
	if _buffer != "":
		var ch: String = Morse.decode(_buffer)
		_buffer = ""
		_text += ch
		letter_decoded.emit(ch)
		_letter_done = true
		_gap_timer.start(unit_seconds * (word_gap_units - letter_gap_units))
	elif _letter_done:
		_letter_done = false
		message_decoded.emit(_text.strip_edges())
		_text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"morse_key"):
		press()
	elif event.is_action_released(&"morse_key"):
		release()
```

(Input action `morse_key`: Space and left mouse while hovering the desk key. Visually the key sprite swaps to a 2-frame pressed state.)

Forgiveness: `ShipEncounter.accept_fuzzy` (A5) matches a reply by prefix and Levenshtein distance <= 1 per word. A wrong key is never "wrong"; the ship just acknowledges something.

## A5. Ship Encounter Data Format

Ships and encounters are `Resource` files (`res://data/ships/*.tres`). The scheduler picks eligible ships per day.

```gdscript
class_name ShipDef
extends Resource

enum ShipClass { SKIFF, FISHER, TUG, FREIGHTER, YACHT, FERRY, SURVEY }
enum Greeting { HORN, LAMP_MORSE, BOTH }

@export var id: StringName
@export var display_name: String = ""            # painted on the hull, shown in the logbook
@export var ship_class: ShipClass = ShipClass.FISHER
@export var sprite_frames: SpriteFrames
@export var speed_px_per_s: float = 6.0          # slow, readable
@export var horn_pitch_scale: float = 1.0
@export var seasons: Array[int] = [0, 1, 2, 3]   # Season enum values allowed
@export var weather_blocked: Array[int] = []     # Weather values where it won't appear (e.g. STORM)
@export var min_day: int = 0
@export var max_visits: int = 99
@export var encounters: Array[ShipEncounter] = []
```

```gdscript
class_name ShipEncounter
extends Resource

enum Gift { NONE, TEA_BLEND, RUG, SEED, BRASS_POLISH, CURTAIN_FABRIC, MUSIC_BOX, POSTCARD, SHELL }

@export var id: StringName
@export var visit_index: int = 0                  # nth time this ship has been met (0 = first)
@export var greeting: ShipDef.Greeting = ShipDef.Greeting.LAMP_MORSE
@export var horn_pattern: String = ".."           # dots/dashes for the horn
@export var morse_text: String = "GOOD EVENING"   # lamp message from ship
@export var accepted_replies: PackedStringArray = ["HELLO", "GOOD EVENING", "HI"]
@export var accept_any_reply: bool = true         # cozy default: any reply counts as friendly
@export var reply_text: String = "SAFE WATERS"    # ship's morse answer to the keeper
@export var gift: Gift = Gift.NONE
@export var gift_id: StringName = &""             # id of ComfortItem/ingredient
@export var logbook_entry_id: StringName = &""    # entry written on first reply
@export var sets_flag: StringName = &""
@export var requires_flags: PackedStringArray = []
```

Example `.tres` in text form:

```
[gd_resource type="Resource" script_class="ShipEncounter" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/ship_encounter.gd" id="1"]
[resource]
script = ExtResource("1")
id = &"marigold_first"
visit_index = 0
greeting = 1
morse_text = "GOOD EVENING KEEPER"
accepted_replies = PackedStringArray("HELLO", "GOOD EVENING")
accept_any_reply = true
reply_text = "SAFE WATERS"
gift = 1
gift_id = &"tea_bergamot_smoke"
logbook_entry_id = &"log_marigold_first"
```

### A5.1 Starter ship roster

| Ship ID | Class | Seasons | Personality | Gifts over visits |
|---|---|---|---|---|
| `marigold` | Fisher | Spring, Autumn | Cheerful, short signals | tea_bergamot_smoke, then knitted scarf |
| `grey_heron` | Freighter | Autumn, Winter | Gruff, one long horn | brass_polish_tin, wool rug |
| `little_tern` | Skiff | Summer | Child at tiller waves lamp, wrong-spelled morse | shell, then seed packet |
| `aldous_bell` | Survey | Spring | Formal, asks "WEATHER?" | barometer_polish, postcard |
| `winter_post` | Ferry | Winter | Delivers mail once per week | postcard, music_box |
| `unnamed_light` | (ghost) | Winter nights, FOG | No hull, only a lamp; says "STILL HERE?" | none; story only |

`unnamed_light` is the quiet central mystery (the previous keeper? a memory?). Never resolved; replies shape logbook tone only.

### A5.2 Scheduler (no manager hierarchy: one small Node under the sea scene)

```gdscript
class_name ShipLane
extends Node2D

@export var ships: Array[ShipDef] = []
@export var spawn_x_left: float = -48.0
@export var spawn_x_right: float = 688.0
@export var lane_y: float = 152.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	Island.day_started.connect(_plan_day)

func _plan_day(day: int) -> void:
	_rng.seed = hash([Island.save.world_seed, day, "ships"])
	var slots: int = _rng.randi_range(1, 3)   # at most 3 ships a day
	for i: int in slots:
		var candidates: Array[ShipDef] = _eligible(day)
		if candidates.is_empty():
			return
		var pick: ShipDef = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var at_phase: float = _rng.randf_range(0.1, 0.9)   # fraction of the day
		get_tree().create_timer(at_phase * Island.day_length_s).timeout.connect(
			func() -> void: _spawn(pick))

func _eligible(day: int) -> Array[ShipDef]:
	var out: Array[ShipDef] = []
	for s: ShipDef in ships:
		if day < s.min_day: continue
		if not s.seasons.has(Island.season): continue
		if s.weather_blocked.has(Island.weather): continue
		if Island.save.ship_visits.get(s.id, 0) as int >= s.max_visits: continue
		out.append(s)
	return out

func _spawn(def: ShipDef) -> void:
	var node: ShipNode = preload("res://scenes/ship.tscn").instantiate() as ShipNode
	node.def = def
	var from_left: bool = _rng.randf() < 0.5
	node.position = Vector2(spawn_x_left if from_left else spawn_x_right, lane_y)
	node.direction = 1 if from_left else -1
	add_child(node)
```

```gdscript
class_name ShipNode
extends Node2D

@export var def: ShipDef
var direction: int = 1
var _encounter: ShipEncounter
var _greeted: bool = false

@onready var _lamp: Sprite2D = $LampPixel
@onready var _horn: MorsePlayer = $HornPlayer
@onready var _lampsig: MorsePlayer = $LampPlayer

func _ready() -> void:
	_lamp.visible = false
	_lampsig.key_down.connect(func() -> void: _lamp.visible = true)
	_lampsig.key_up.connect(func() -> void: _lamp.visible = false)
	_encounter = _pick_encounter()

func _process(delta: float) -> void:
	position.x += float(direction) * def.speed_px_per_s * delta
	position.x = snappedf(position.x, 1.0) if false else position.x   # snap in draw via camera/viewport snap
	if not _greeted and absf(position.x - 320.0) < 110.0:
		_greeted = true
		_greet()
	if position.x < -64.0 or position.x > 704.0:
		queue_free()

func _pick_encounter() -> ShipEncounter:
	var n: int = Island.save.ship_visits.get(def.id, 0) as int
	var best: ShipEncounter = null
	for e: ShipEncounter in def.encounters:
		if e.visit_index <= n and Island.flags_ok(e.requires_flags):
			if best == null or e.visit_index > best.visit_index:
				best = e
	return best

func _greet() -> void:
	if _encounter == null:
		return
	if _encounter.greeting != ShipDef.Greeting.LAMP_MORSE:
		_horn.play_text(_encounter.horn_pattern.replace(".", "E").replace("-", "T"))
	if _encounter.greeting != ShipDef.Greeting.HORN:
		_lampsig.play_text(_encounter.morse_text)
	Island.ship_hailing.emit(self)       # signal lights up the desk key hint (a glowing bulb)

func receive_reply(text: String) -> void:
	var ok: bool = _encounter.accept_any_reply or _fuzzy_match(text)
	if not ok:
		await _lampsig.play_text("AGAIN")        # gentle, no penalty
		return
	await _lampsig.play_text(_encounter.reply_text)
	Island.ship_answered(def, _encounter)

func _fuzzy_match(text: String) -> bool:
	for r: String in _encounter.accepted_replies:
		if text.to_upper().begins_with(r.left(maxi(3, r.length() - 2))):
			return true
	return false
```

(Horn pattern uses a "E"/"T" mapping so one-char dots/dashes reuse the same timeline; a horn sample with `is_horn = true`.)

### A5.3 Answering without knowing morse

A laminated morse card hangs by the key (pure sprite). A hand-lettered "quick phrases" board has three shutters: pulling a string plays a canned phrase (HELLO, GOOD NIGHT, THANK YOU) through the lamp. This is a toy, not a menu; it is physically on the desk. Learners can type nothing; they lose nothing.

## A6. The Logbook

### A6.1 Behavior

The logbook is a physical book on the desk. Click to open a two-page spread (pixel art paper; text drawn with a `RichTextLabel` using a bitmap font, 1x or 2x integer scale only). Entries are never shown as a list of titles; the player flips pages. Handwriting uses a pixel font with 3 slight variants (ink drift) per day for texture.

Entries appear:
- the **morning after** an event (written overnight), never instantly. This keeps the reward quiet and reload-safe.
- when a ship is answered (short note beneath the date)
- on weather firsts ("first storm of autumn")
- on comfort upgrades (a line about the change)
- on prop discoveries

Hard limit: 1 to 3 entries per day. Silence is allowed.

### A6.2 Data

```gdscript
class_name LogEntryDef
extends Resource

enum Tone { PLAIN, WARM, WRY, WISTFUL }

@export var id: StringName
@export var tone: Tone = Tone.PLAIN
@export_multiline var text: String = ""         # may include {ship}, {season}, {weather}, {days}
@export var variants: PackedStringArray = []    # alternates; one chosen by seeded rng
@export var requires_flags: PackedStringArray = []
@export var priority: int = 0                   # higher wins when >3 pending
```

Save-side record (written text is frozen so retroactive edits to defs never alter history):

```gdscript
# in SaveData.logbook: Array[Dictionary]
# { "day": int, "season": int, "weather": int, "entry_id": "marigold_first", "text": "Rendered final string" }
```

### A6.3 Writer

```gdscript
func logbook_write(entry_id: StringName) -> void:
	if save.logged_ids.has(entry_id):
		return
	save.logged_ids.append(entry_id)
	pending_log.append(entry_id)       # flushed at next dawn

func _flush_log_at_dawn() -> void:
	pending_log.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _log_def(a).priority > _log_def(b).priority)
	for i: int in mini(3, pending_log.size()):
		var def: LogEntryDef = _log_def(pending_log[i])
		var pool: PackedStringArray = [def.text] + def.variants
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([save.world_seed, save.day, def.id])
		var raw: String = pool[rng.randi_range(0, pool.size() - 1)]
		save.logbook.append({
			"day": save.day, "season": season, "weather": weather,
			"entry_id": String(def.id),
			"text": raw.format({"season": SEASON_NAMES[season], "weather": WEATHER_NAMES[weather], "days": save.day}),
		})
	pending_log = pending_log.slice(3)   # overflow carries to the next dawn
	logbook_updated.emit()
```

### A6.4 Sample entries

Voice: dry, kind, brief, first-person, slightly self-deprecating. Never explains the backstory. Never addresses the player.

| ID | Tone | Text |
|---|---|---|
| `log_first_night` | PLAIN | Lit the lamp. It caught on the third try. The sea sounds exactly as I remembered, which I did not expect. |
| `log_second_cup` | WISTFUL | Washed both cups again. One of these days I will admit only one gets used. |
| `log_marigold_first` | WARM | A boat called Marigold flashed GOOD EVENING KEEPER. I answered. Hand cramped. I think they were smiling, though it is a long way to see. |
| `log_marigold_gift` | WARM | A parcel on the rocks at dawn: smoked bergamot, tied in blue string. The kettle is delighted. |
| `log_grey_heron_horn` | WRY | The Grey Heron gave one very long horn. I have decided this means 'carry on'. I carried on. |
| `log_little_tern` | WARM | A small boat. A very small person sending something that was not quite morse, mostly the letter K. I sent K back. Everyone was pleased. |
| `log_fog_horn` | PLAIN | Fog all day. Pulled the lever every minute and a half. Somewhere something answered, low. I will not say what I thought it was. |
| `log_first_storm` | WRY | Scratched a tally behind the barometer glass. Eleven now. The lamp did not flinch. I flinched a little. |
| `log_rug_unrolled` | WARM | Put the wool rug down by the stove. My feet have been informed. |
| `log_brass_polish` | PLAIN | Polished the lens housing until I could see my own face in it. It was a tired face but a tidy one. |
| `log_raincatcher_v2` | PLAIN | Fitted the second funnel. The rain barrel makes a new note now, higher. I tapped it twice just to hear. |
| `log_aurora` | WISTFUL | Green over the water past midnight. I stood on the gallery in a blanket. It lasted exactly as long as a cup of tea. |
| `log_unnamed_light` | WISTFUL | A lamp out on the fog, no hull I could see. It sent STILL HERE? I sent YES. Nothing after. I kept the lamp on late anyway. |
| `log_winter_post` | WARM | Mail! One postcard, a stranger's picture of a harbour. I pinned it beside the others. The wall is getting talkative. |
| `log_year_one` | WISTFUL | A full turn of the seasons. The pencil marks on the doorframe stop where they stop. I made no new ones. I did buy a better kettle. |
| `log_chess_move` | WRY | Moved one pawn. If anyone is keeping score, white is no longer in zugzwang, just in suspense. |
| `log_quiet_day` | PLAIN | Nothing happened. Lovely. |

`log_quiet_day` is a fallback written on ~10% of days with no events, to teach that silence is valid.

### A6.5 Ship memory in logbook

Each answered ship gets a **single page** (the sea chart's pin card) that accumulates tiny annotations: date of each encounter, a pixel sketch of the hull, gifts received. Rendered by `ChartPinCard` scene bound to `save.ship_visits` and `save.ship_notes`.

---

# PART B: NON-PUNITIVE COMFORT PROGRESSION

## B1. Principles

1. **Nothing is ever lost.** Items are only added. No decay, no downgrade, no removal.
2. **Comfort, not capability.** An upgrade changes how the island looks, sounds, smells (shown via steam, particles), and feels. It never changes how well you survive, because you cannot fail.
3. **Pace is the player's.** There is no currency, no cost, no grind counter. Items arrive via (a) ship gifts, (b) beachcombing, (c) small tinkering toys (mixing tea, polishing), (d) seasonal events, (e) simply time and presence.
4. **Every unlock is a physical object or a surface change** visible in the scene, plus one quiet logbook line.
5. **Each upgrade is an optional toy, not a gate.** No unlock is required for any other content. Story reveals are not behind comfort tiers.
6. **No percentages, no "2/10", no progress bars.** The room tells you how far along it is.

## B2. Comfort Axes

Instead of stats, there are five **Comfort Tracks**, each a ladder of 3 to 5 tiers. Tiers are cumulative visuals.

| Track | What changes | Diegetic carrier |
|---|---|---|
| WARMTH | Stove, rugs, blankets, curtains, lamp-shade color | Warmer light color on interior CanvasModulate, steam, wool textures |
| BREW | Tea blends, kettle, cups, tray | Steam color/shape, scent-wisps particles, cup sprites, tea shelf jars |
| BRASS | Polish on lens housing, key, rails, handles | Specular glint sprite sweeps, beam color purer |
| RAIN | Rain barrel, funnels, chime, window box | Barrel sprites, water level toys, chime notes on rain |
| GARDEN | Window box, windflowers, moss, cat/gull visitors | Plant sprites, resident critters |

Rationale: five tracks, each with a physical anchor. A sixth, `LIGHT` (the lamp beam itself), is purely aesthetic and tied to BRASS tiers, not separate.

## B3. Unlock Catalog

| ID | Track | Tier | Name | Visible effect | Source |
|---|---|---|---|---|---|
| `rug_braided` | WARMTH | 1 | Braided rug | Oval rug sprite under table, footstep sound muffled | Start item (found in cupboard day 2) |
| `rug_wool_grey` | WARMTH | 2 | Heron's wool rug | Larger rug, stove glow reflects on it | Gift: grey_heron (visit 2) |
| `curtain_linen` | WARMTH | 2 | Linen curtains | Window light softer, sway with wind | Gift: aldous_bell |
| `blanket_patch` | WARMTH | 3 | Patchwork blanket | Bed + armchair varied | Tinker: sewing toy after 4 postcards |
| `lamp_amber_shade` | WARMTH | 4 | Amber lamp shade | Interior light shifts warmer | Autumn event |
| `tea_plain` | BREW | 0 | Plain black tea | Thin white steam | Start |
| `tea_bergamot_smoke` | BREW | 1 | Smoked bergamot | Grey-blue curl steam, tiny citrus sparkle | Gift: marigold |
| `tea_honey_thyme` | BREW | 2 | Honey and thyme | Golden steam, cup glows | Garden: thyme planted |
| `tea_winter_clove` | BREW | 3 | Winter clove | Red-brown steam, stove flicker | Winter event |
| `kettle_copper` | BREW | 2 | Copper kettle | Whistle changes pitch, copper glints | Beachcomb find |
| `cup_blue_glaze` | BREW | 2 | Blue-glaze cups | Cups on shelf, second cup now matches | Gift: little_tern, 2 visits |
| `brass_polish_tin` | BRASS | 1 | Polish tin | Unlocks polishing toy | Gift: grey_heron |
| `brass_key_polished` | BRASS | 1 | Polished morse key | Key glints; click sound brighter | Toy: polish it |
| `brass_rail_polished` | BRASS | 2 | Gallery rail | Rail glint shimmers at sunset | Toy |
| `brass_lens_polished` | BRASS | 3 | Lens housing | Beam purer, subtle prism fringe | Toy, requires rail |
| `rain_funnel_1` | RAIN | 1 | Tin funnel | Barrel fills visibly when raining | Start |
| `rain_funnel_2` | RAIN | 2 | Second funnel | Two streams, higher note | Beachcomb |
| `rain_chime` | RAIN | 3 | Rain chime | Notes play on rain drops, season-tuned | Gift: aldous_bell |
| `rain_barrel_oak` | RAIN | 4 | Oak barrel | Barrel sprite upgrade, ring ripples | Tinker (after 5 storms) |
| `windowbox_empty` | GARDEN | 1 | Window box | Empty box | Start |
| `windowbox_seeded` | GARDEN | 2 | Seeded box | Sprouts over 3 days | Gift: little_tern seeds |
| `garden_flowering` | GARDEN | 3 | In bloom | Petals, bees (summer) | Time |
| `visitor_cat` | GARDEN | 4 | Lighthouse cat | A cat lies on the warm rug | After WARMTH >= 3 and BREW >= 2 |

All items also carry optional **memory text** (the pickup caption).

## B4. Resources

### B4.1 `ComfortItem`

```gdscript
class_name ComfortItem
extends Resource

enum Track { WARMTH, BREW, BRASS, RAIN, GARDEN }
enum Source { START, SHIP_GIFT, BEACHCOMB, TINKER, SEASON, TIME, COMPANION }

@export var id: StringName
@export var track: Track = Track.WARMTH
@export var tier: int = 1
@export var display_name: String = ""
@export_multiline var flavor: String = ""           # shown once on discovery
@export var source: Source = Source.START
@export var source_hint: StringName = &""           # ship id / tinker toy id / season id
@export var requires_items: PackedStringArray = []  # prerequisite item ids (cosmetic ordering)
@export var requires_flags: PackedStringArray = []
@export var scene_node_path: NodePath               # node in house scene to reveal/swap
@export var visual_variant: StringName = &""        # animation/variant applied to that node
@export var logbook_entry_id: StringName = &""
@export var sfx_on_unlock: AudioStream
```

### B4.2 `ComfortCatalog` (single resource listing all items)

```gdscript
class_name ComfortCatalog
extends Resource

@export var items: Array[ComfortItem] = []
var _by_id: Dictionary = {}

func get_item(id: StringName) -> ComfortItem:
	if _by_id.is_empty():
		for it: ComfortItem in items:
			_by_id[it.id] = it
	return _by_id.get(id) as ComfortItem

func tier_of(track: int, owned: Array[StringName]) -> int:
	var best: int = 0
	for it: ComfortItem in items:
		if it.track == track and owned.has(it.id):
			best = maxi(best, it.tier)
	return best
```

### B4.3 `ComfortTrack`-aware room dressing (the diegetic bridge)

A scene node watches `Island.item_acquired` and updates itself. No central "apply upgrades" function.

```gdscript
class_name RoomDressing
extends Node2D
## Attach to any prop that has comfort variants (rug slot, kettle, key, barrel...).

@export var item_id: StringName
@export var show_when_owned: bool = true
@export var sprite_variant: StringName = &"default"

func _ready() -> void:
	Island.item_acquired.connect(_on_item)
	_apply(Island.has_item(item_id))

func _on_item(id: StringName) -> void:
	if id == item_id:
		_apply(true)
		_pop_in()

func _apply(owned: bool) -> void:
	visible = owned == show_when_owned
	if owned and has_node("AnimatedSprite2D"):
		($AnimatedSprite2D as AnimatedSprite2D).play(sprite_variant)

func _pop_in() -> void:
	# Pixel-friendly: 3-frame squash using integer scale steps, no smooth tween on position.
	var t := create_tween()
	scale = Vector2(1.0, 0.5)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_STEP) if false else null
	t.tween_callback(func() -> void: scale = Vector2(1.0, 0.75))
	t.tween_interval(0.06)
	t.tween_callback(func() -> void: scale = Vector2.ONE)
```

### B4.4 Tea blends as a physical toy

Tea is a minigame without fail states: the player drags a pinch from shelf jars onto the kettle tray. Any combination yields a **result**; known recipes unlock named blends; unknown combos produce a "house blend" with a procedurally tinted steam.

```gdscript
class_name TeaBlend
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var ingredients: PackedStringArray = []     # sorted jar ids, e.g. ["bergamot","smoke"]
@export var steam_color: Color = Color.WHITE
@export var steam_particle_count: int = 6
@export var cup_glow: Color = Color(1, 1, 1, 0)
@export var cozy_value: int = 1                     # affects only ambience mix, never shown
@export var moods: PackedStringArray = []           # ["rain","winter"] used for ambient pick
@export_multiline var tasting_note: String = ""     # appears in logbook once
```

```gdscript
class_name KettleTray
extends Node2D

signal brewed(blend: TeaBlend)

@export var blends: Array[TeaBlend] = []
var _jars_in: Array[StringName] = []

func add_jar(jar_id: StringName) -> void:
	if _jars_in.size() >= 3 or _jars_in.has(jar_id):
		return
	_jars_in.append(jar_id)

func brew() -> void:
	var key: PackedStringArray = PackedStringArray(_jars_in.map(func(s: StringName) -> String: return String(s)))
	key.sort()
	var found: TeaBlend = null
	for b: TeaBlend in blends:
		var k: PackedStringArray = b.ingredients.duplicate()
		k.sort()
		if k == key:
			found = b
			break
	if found == null:
		found = _house_blend(key)
	_jars_in.clear()
	Island.record_brew(found)
	brewed.emit(found)

func _house_blend(key: PackedStringArray) -> TeaBlend:
	var b := TeaBlend.new()
	b.id = &"house_blend"
	b.display_name = "House Blend"
	b.ingredients = key
	var h: float = float(hash(",".join(key)) & 0xFFFF) / 65535.0
	b.steam_color = Color.from_hsv(h, 0.25, 0.95)
	return b
```

Unlocking jars (ingredients) is progression: more jars on the shelf = more combinations. Jars arrive as gifts, garden harvest, or beachcombing.

### B4.5 Polishing toy (BRASS)

Hold and rub with a cloth: a `polish` float rises per stroke over a brass sprite; a shader mixes tarnished and bright textures by mask. When `polish >= 1.0` the object swaps permanently to the polished variant and a single glint sweeps. Rubbing again is harmless and soothing (no overuse penalty). Tarnish never regrows.

```gdscript
class_name PolishSpot
extends Area2D

signal polished

@export var item_id: StringName
@export var strokes_needed: int = 24
var _strokes: int = 0
var _last_pos: Vector2
var _dragging: bool = false

@onready var _mat: ShaderMaterial = $Sprite2D.material as ShaderMaterial

func _input_event(_vp: Viewport, e: InputEvent, _i: int) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = e.pressed
		_last_pos = get_global_mouse_position()
	elif e is InputEventMouseMotion and _dragging and not Island.has_item(item_id):
		var p: Vector2 = get_global_mouse_position()
		if p.distance_to(_last_pos) > 6.0:
			_strokes += 1
			_last_pos = p
			_mat.set_shader_parameter("polish", clampf(float(_strokes) / float(strokes_needed), 0.0, 1.0))
			if _strokes >= strokes_needed:
				Island.grant_item(item_id)
				polished.emit()
```

### B4.6 Raincatcher improvements (RAIN)

Barrel level is cosmetic: a 0..1 `water_level` increases during rain, drains slowly when clear, and visually represents recent weather. Funnels (items) increase the visual fill rate and add drip points. Barrel never overflows into anything bad; at full it just spills a pixel splash. Chime note count equals funnel count for sonic layering.

```gdscript
class_name RainCatcher
extends Node2D

@export var funnel_count: int = 1
@export var fill_per_second: float = 0.02
@export var drain_per_second: float = 0.002
var water_level: float = 0.0   # persisted in SaveData.misc

func _process(delta: float) -> void:
	var raining: bool = Island.weather in [Island.Weather.RAIN, Island.Weather.STORM]
	if raining:
		water_level = minf(1.0, water_level + fill_per_second * float(funnel_count) * delta)
	else:
		water_level = maxf(0.0, water_level - drain_per_second * delta)
	$WaterSprite.frame = clampi(int(water_level * 7.0), 0, 7)   # 8-frame strip, integer frames only
```

## B5. Island Singleton (single thin autoload)

One autoload, `Island`, owns the loaded `SaveData`, the calendar tick, and signals. It is not a manager that knows about systems; props subscribe. It does not decide anything.

```gdscript
extends Node
## Autoload "Island". Holds save state and emits events. No gameplay logic.

signal day_started(day: int)
signal item_acquired(id: StringName)
signal flags_changed
signal ship_hailing(ship: Node)
signal logbook_updated
signal caption_requested(text: String)

enum Season { SPRING, SUMMER, AUTUMN, WINTER }
enum Weather { CLEAR, FOG, RAIN, STORM, SNOW, AURORA, GOLDEN }

const SEASON_NAMES: PackedStringArray = ["spring", "summer", "autumn", "winter"]
const WEATHER_NAMES: PackedStringArray = ["clear", "fog", "rain", "storm", "snow", "aurora", "golden"]
const DAYS_PER_SEASON: int = 7

@export var catalog: ComfortCatalog
@export var day_length_s: float = 360.0

var save: SaveData
var season: int = Season.SPRING
var weather: int = Weather.CLEAR
var pending_log: Array[StringName] = []
var last_reveal_day: int = -1

func has_item(id: StringName) -> bool:
	return save.owned_items.has(id)

func has_flag(id: StringName) -> bool:
	return save.flags.has(id)

func flags_ok(req: PackedStringArray) -> bool:
	for f: String in req:
		if not has_flag(StringName(f)):
			return false
	return true

func set_flag(id: StringName) -> void:
	if not save.flags.has(id):
		save.flags.append(id)
		flags_changed.emit()

func grant_item(id: StringName) -> void:
	if has_item(id):
		return
	save.owned_items.append(id)
	var it: ComfortItem = catalog.get_item(id)
	if it != null and it.logbook_entry_id != &"":
		logbook_write(it.logbook_entry_id)
	item_acquired.emit(id)
	SaveIO.autosave(save)

func show_caption(text: String) -> void:
	caption_requested.emit(text)

func ship_answered(def: ShipDef, enc: ShipEncounter) -> void:
	save.ship_visits[def.id] = (save.ship_visits.get(def.id, 0) as int) + 1
	if enc.sets_flag != &"":
		set_flag(enc.sets_flag)
	if enc.logbook_entry_id != &"":
		logbook_write(enc.logbook_entry_id)
	if enc.gift != ShipEncounter.Gift.NONE and enc.gift_id != &"":
		save.parcels.append(String(enc.gift_id))   # arrives on the rocks at next dawn
	SaveIO.autosave(save)

func record_brew(blend: TeaBlend) -> void:
	save.brews_made += 1
	if not save.tasted.has(blend.id):
		save.tasted.append(blend.id)
		if blend.tasting_note != "":
			logbook_write(StringName("tea_" + String(blend.id)))
```

Parcels: gifts never appear mid-encounter. At next dawn a `Parcel` node (a small wrapped box with a string) is placed on the rocks by the dock. Clicking it opens it (3-frame animation) and calls `grant_item`. Uncollected parcels wait forever; there is no expiry.

## B6. Save Data Schema

Single `Resource` saved as `user://last_light.tres` (binary `.res` also fine). Autosave on item grants, dawn, and clean quit. No manual save UI exists; there is a "continue" brass bell on the title screen.

```gdscript
class_name SaveData
extends Resource

const VERSION: int = 1

@export var version: int = VERSION
@export var world_seed: int = 0
@export var day: int = 0                          # absolute day count
@export var time_of_day: float = 0.25             # 0..1
@export var owned_items: Array[StringName] = []
@export var flags: Array[StringName] = []
@export var logged_ids: Array[StringName] = []
@export var logbook: Array[Dictionary] = []      # see A6.2
@export var ship_visits: Dictionary = {}         # StringName -> int
@export var ship_notes: Dictionary = {}          # StringName -> Array[String]
@export var parcels: Array[String] = []          # item ids waiting on the rocks
@export var tasted: Array[StringName] = []
@export var brews_made: int = 0
@export var storms_seen: int = 0
@export var misc: Dictionary = {}                # water_level, polish_progress{}, chess_state, window_box_days
@export var settings: Dictionary = {             # kept in same file for simplicity
	"music": 0.8, "sfx": 0.8, "morse_unit": 0.12, "text_scale": 2,
}
```

JSON equivalent for debugging or cloud sync:

```json
{
  "version": 1,
  "world_seed": 482113,
  "day": 17,
  "time_of_day": 0.62,
  "owned_items": ["rug_braided", "tea_plain", "tea_bergamot_smoke", "rain_funnel_1", "brass_polish_tin"],
  "flags": ["met_marigold", "seen_postcard"],
  "logged_ids": ["log_first_night", "log_marigold_first"],
  "logbook": [
    {"day": 1, "season": 0, "weather": 0, "entry_id": "log_first_night", "text": "Lit the lamp..."}
  ],
  "ship_visits": {"marigold": 2, "grey_heron": 1},
  "ship_notes": {"marigold": ["spring day 3: smoked bergamot"]},
  "parcels": ["rug_wool_grey"],
  "tasted": ["plain", "bergamot_smoke"],
  "brews_made": 23,
  "storms_seen": 1,
  "misc": {"water_level": 0.4, "polish": {"brass_key_polished": 0.5}},
  "settings": {"music": 0.8, "sfx": 0.8, "morse_unit": 0.12, "text_scale": 2}
}
```

### B6.1 Save I/O and migration

```gdscript
class_name SaveIO
extends RefCounted

const PATH: String = "user://last_light.tres"
const TMP: String = "user://last_light.tmp.tres"

static func load_or_new() -> SaveData:
	if ResourceLoader.exists(PATH):
		var s: SaveData = ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
		if s != null:
			return _migrate(s)
	var n := SaveData.new()
	n.world_seed = randi()
	n.owned_items = [&"rug_braided", &"tea_plain", &"rain_funnel_1", &"windowbox_empty"]
	return n

static func autosave(s: SaveData) -> void:
	# Write to temp then rename; a crash mid-write never corrupts the real save.
	if ResourceSaver.save(s, TMP) == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP), ProjectSettings.globalize_path(PATH))

static func _migrate(s: SaveData) -> SaveData:
	if s.version < 1:
		s.version = 1
	# future: if s.version < 2: add fields with defaults; never remove or reinterpret old ones
	s.version = SaveData.VERSION
	return s
```

Rules: (1) never delete fields; (2) unknown ids in `owned_items` are kept (harmless), so removing an item from the catalog never breaks saves; (3) loading a save never re-triggers unlock fanfares; (4) the game keeps the previous save as `.bak` once per session.

## B7. How Progression Is Shown Diegetically

| Signal | Replaces | Implementation |
|---|---|---|
| Room warmth hue | "Warmth level" | `CanvasModulate` color lerped by `tier_of(WARMTH)`: tier0 cool grey-blue to tier4 amber |
| Number and texture of rugs | "Rugs owned" | `RoomDressing` nodes on floor slots |
| Shelf jars | Tea recipes known | One jar sprite per ingredient; blends' names scribbled on tags |
| Steam color and shape | Best tea unlocked | Kettle particles tinted by last brewed blend; default is last favourite |
| Brass glints | Polish completion | Specular sweep shader fires every 8 to 14 s on polished props, random per prop |
| Barrel level and chime | Raincatcher tier | Water frame, note count |
| Sea chart pins | Ships met | One pin sprite per ship; thread links repeat visitors |
| Window box growth | Time passing | 3-stage sprite, advances per day, no dying |
| Cat on the rug | "Everything is cozy" | Appears when WARMTH >= 3 and BREW >= 2, not announced |
| Lamp beam | Overall care | Beam sprite brightness and fringe by BRASS tier |
| Pencil marks, postcards, logbook | Narrative progress | Wall objects, see A2 |

No HUD at all. The only UI-adjacent object is the paper caption strip (A2.3) and the logbook.

### B7.1 Comfort ambience mixer (reactive, not a stat)

Ambient loops layer by tracks present; not by numbers shown.

```gdscript
class_name AmbienceLayers
extends Node

@export var stove_crackle: AudioStreamPlayer
@export var kettle_hum: AudioStreamPlayer
@export var chime_wind: AudioStreamPlayer
@export var cat_purr: AudioStreamPlayer

func _ready() -> void:
	Island.item_acquired.connect(func(_id: StringName) -> void: _refresh())
	_refresh()

func _refresh() -> void:
	var w: int = Island.catalog.tier_of(ComfortItem.Track.WARMTH, Island.save.owned_items)
	var b: int = Island.catalog.tier_of(ComfortItem.Track.BREW, Island.save.owned_items)
	var r: int = Island.catalog.tier_of(ComfortItem.Track.RAIN, Island.save.owned_items)
	_fade(stove_crackle, -40.0 + 6.0 * float(w))
	_fade(kettle_hum, -40.0 + 7.0 * float(b))
	_fade(chime_wind, -80.0 if r < 3 else -22.0)
	_fade(cat_purr, -18.0 if Island.has_item(&"visitor_cat") else -80.0)

func _fade(p: AudioStreamPlayer, db: float) -> void:
	create_tween().tween_property(p, "volume_db", db, 2.0)
```

## B8. Unlock Pacing Table (non-binding guide)

| Day range (7-day seasons) | Typical new arrivals | Logbook density |
|---|---|---|
| 1 to 3 | braided rug, polish tin (gift) | 1 per day |
| 4 to 7 | first tea blend gift, funnel 2 | 1 to 2 |
| 8 to 14 | wool rug, curtains, kettle, seeded box | 1 to 2 |
| 15 to 21 | lens polished, rain chime, honey and thyme | 1 |
| 22 to 28 | winter clove, amber shade, cat arrives | 1 to 3 (year-end) |
| Year 2+ | rarer variants, additional ships, new postcards; no cap | quiet |

If the player does nothing, everything still arrives slowly via time-based items (`Source.TIME`). If they do everything, they simply reach the "complete cozy" state earlier and keep playing with the toys (ships, brewing, weather) with no end screen.

## B9. Endlessness Without Pressure

- No "100% complete" counter. The closest thing is the lamp beam's color purity.
- When all items are owned, new **variants** show up (rare tea colours, ship sketches on the chart), but none are required.
- There is no missable content: every ship returns across seasons; every gift can arrive on a later visit.

## B10. Test Checklist

1. Delete save file, start: braided rug, plain tea, funnel 1, empty box visible. Lamp lit on first night, logbook morning entry present.
2. Answer a ship with a wrong morse string: ship sends AGAIN, nothing lost.
3. Ignore all ships for 28 days: all items with `Source.TIME` and `START` still arrive; logbook has quiet-day entries.
4. Kill process mid-autosave: previous save loads (temp rename logic).
5. Reload on a stormy dawn: same weather (seeded by world_seed + day).
6. Grant item twice: second call is a no-op, no duplicate logbook entry.
7. Remove an item from the catalog: old save still loads without errors.
8. Verify no node uses fractional pixel positions at rest (`position.snapped(Vector2.ONE)`); viewport 640x360 with `stretch_mode = viewport`, `scale_mode = integer`.
9. Morse: `Morse.decode(Morse.encode("SOS ME")) == "SOS ME"`; `MorsePlayer.play_text("SOS")` produces timeline lengths 1,1,1,1,1,3 (dot gaps) per spec.
10. Run weather roll 10,000 times per season; winter produces SNOW > 25% and never RAIN above 10%.

## B11. Integration Notes for Other Agents

| Concern | Hand-off |
|---|---|
| Art | Needs paired sprites per `ComfortItem` (before/after), 2-frame morse key, 8-frame rain barrel strip, ship sprites 24 to 48 px wide with 1 lamp pixel anchor |
| Audio | Horn samples per ship class, 620 Hz default key tone, rain chime notes in pentatonic scale, kettle whistle pitches per kettle |
| Scenes | `Island` autoload registered; `ShipLane` in sea scene; `RoomDressing` on each slot node |
| Input map | `morse_key` (Space), `interact` (LMB), `skip_to_dawn` (optional bed click) |
| Project settings | Viewport 640x360, stretch mode `viewport`, scale mode `integer` (project currently 320x180, needs integrator change) |
| Localization | Logbook text via `tr()` with ids as keys; keep morse in Latin charset only (ships may spell badly on purpose) |

# AGENT 05 - Audio Atmosphere: Sea, Weather, Stone, Soft Music

Target: Godot 4.7.2, GDScript 2.0 (static typing). Mood: a warm lamp in a cold place. Everything here is tuned to be *barely noticed and deeply missed*.

Mandates honoured:
- No `AudioManager` singleton. Every sound lives on a physical node in the scene (a shoreline marker, a vent, a roof, the bell). The only global thing is the `AudioServer` bus layout, which Godot itself owns.
- Procedural first (sea, rain, wind), recorded second (bell, foley, music samples). Procedural beds never loop audibly because they never repeat.
- Relaxation first: low peak ceilings, no sub-bass rumble, no sudden transients except the bell, which is rehearsed and ducked around.

---

## 0. Contents

1. Scene-tree placement of audio
2. Bus architecture (`default_bus_layout.tres`) and per-bus effects
3. Loudness budget and safe ceilings
4. Procedural sea: swell timing, pink noise, generator code
5. Rain: outside vs inside the tower (occlusion math + code)
6. Wind through vent shafts (resonant filter + code)
7. `TowerAcoustics` node: smooth indoor/outdoor blend
8. `AudioStreamPlayer2D` settings and attenuation
9. Cozy_Music: gentle instrumentation guidance and a sparse scheduler
10. Accessibility (mono, loudness, reduced low frequency)
11. Loudness test checklist
12. Project settings and gotchas

---

## 1. Scene-tree placement (audio lives where it sounds)

```
Island (Node2D)
├─ Shore (Node2D)
│  ├─ SeaSwellWest   (AudioStreamPlayer2D  -> SeaSwell.gd,  bus Ambience_Sea)
│  ├─ SeaSwellEast   (AudioStreamPlayer2D  -> SeaSwell.gd,  bus Ambience_Sea)
│  └─ SeaWash        (AudioStreamPlayer2D  -> static loop,  bus Ambience_Sea)
├─ Sky (Node2D)
│  ├─ RainBed        (AudioStreamPlayer    -> RainVoice.gd, bus Ambience_Weather)   # non-positional, follows the camera
│  ├─ WindBed        (AudioStreamPlayer    -> WindBed.gd,   bus Ambience_Weather)
│  └─ Thunder        (AudioStreamPlayer2D  -> samples,      bus Ambience_Weather)
├─ Lighthouse (Node2D)
│  ├─ TowerAcoustics (Node                 -> TowerAcoustics.gd)     # writes bus filter targets
│  ├─ RoofThud       (AudioStreamPlayer2D  -> RainRoof.gd,  bus Lighthouse_Mech)
│  ├─ VentShaftLow   (AudioStreamPlayer2D  -> VentWhistle.gd, bus Lighthouse_Mech)
│  ├─ VentShaftHigh  (AudioStreamPlayer2D  -> VentWhistle.gd, bus Lighthouse_Mech)
│  ├─ LampHum        (AudioStreamPlayer2D  -> loop,         bus Lighthouse_Mech)
│  ├─ GearTick       (AudioStreamPlayer2D  -> loop/one-shots, bus Lighthouse_Mech)
│  ├─ Bell           (AudioStreamPlayer2D  -> one-shot,     bus Lighthouse_Mech)
│  └─ Door (Area2D) ─ DoorCreak (AudioStreamPlayer2D, bus Foley)
├─ Player (CharacterBody2D)
│  ├─ Camera2D       (acts as listener unless an AudioListener2D is current)
│  ├─ Footsteps      (AudioStreamPlayer2D, bus Foley, stream = AudioStreamRandomizer)
│  └─ Cup / Tools    (AudioStreamPlayer2D, bus Foley)
└─ MusicBox (Node -> CozyMusicBox.gd)          # children: 6 AudioStreamPlayer pool, bus Cozy_Music
```

Rules:
- Ambient *beds* that should not pan (rain, general wind) are `AudioStreamPlayer` (non-positional). Anything with a source in the world is `AudioStreamPlayer2D`.
- Generators are children of the thing that makes the sound. If the vent node is deleted, the whistle is gone. No registry.
- Weather state is passed by exported `NodePath`/signals from the `Weather` node that owns storm intensity, not by a global.

---

## 2. Bus architecture

### 2.1 Topology

```
Master  (idx 0)   HardLimiter, gentle compressor off by default
 ├─ Ambience_Sea      (1)  HPF 30 Hz -> LPF (indoor-driven) -> Limiter-ish compressor
 ├─ Ambience_Weather  (2)  HPF 40 Hz -> LPF (indoor-driven) -> Reverb(small, wet 0.10)
 ├─ Lighthouse_Mech  (3)  HPF 45 Hz -> EQ shaping -> Reverb(stone room)
 ├─ Foley            (4)  HPF 60 Hz -> Reverb(stone room, send-ish wet 0.14) -> Compressor
 └─ Cozy_Music       (5)  HPF 50 Hz -> Compressor (sidechain Foley) -> Reverb(hall, wet 0.22)
```

All five are sends to Master. Effect order on a bus matters: filters first (remove the unsafe band), then spatial (reverb), then dynamics last (so reverb tails cannot jump the ceiling).

### 2.2 Default volumes (before user sliders)

| Bus | volume_db | Role |
|---|---|---|
| Master | 0.0 | Limiter at -2.0 dBFS ceiling |
| Ambience_Sea | -6.0 | Always present, the "room tone" of the whole game |
| Ambience_Weather | -9.0 | Rain / wind / thunder |
| Lighthouse_Mech | -8.0 | Gears, lamp hum, vents, bell |
| Foley | -6.0 | Footsteps, door, cup, tools |
| Cozy_Music | -11.0 | Sits under everything |

### 2.3 `default_bus_layout.tres` (drop-in)

Save to `res://audio/default_bus_layout.tres`; set `Project Settings > Audio > Buses > Default Bus Layout`. Resource IDs are arbitrary but must be unique. Property names below are the real Godot 4 ones (`cutoff_hz`, `threshold`, `attack_us`, `release_ms`, `ceiling_db`, ...).

```ini
[gd_resource type="AudioBusLayout" load_steps=17 format=3]

[sub_resource type="AudioEffectHardLimiter" id="lim_master"]
pre_gain_db = 0.0
ceiling_db = -2.0
release = 0.4

[sub_resource type="AudioEffectHighPassFilter" id="hpf_sea"]
cutoff_hz = 30.0
resonance = 0.5
db = 1

[sub_resource type="AudioEffectLowPassFilter" id="lpf_sea"]
cutoff_hz = 9000.0
resonance = 0.5
db = 1

[sub_resource type="AudioEffectCompressor" id="comp_sea"]
threshold = -18.0
ratio = 2.0
gain = 0.0
attack_us = 40000.0
release_ms = 600.0
mix = 1.0

[sub_resource type="AudioEffectHighPassFilter" id="hpf_weather"]
cutoff_hz = 40.0
db = 1

[sub_resource type="AudioEffectLowPassFilter" id="lpf_weather"]
cutoff_hz = 12000.0
db = 1

[sub_resource type="AudioEffectReverb" id="rev_weather"]
room_size = 0.35
damping = 0.7
spread = 1.0
dry = 1.0
wet = 0.10

[sub_resource type="AudioEffectHighPassFilter" id="hpf_mech"]
cutoff_hz = 45.0
db = 1

[sub_resource type="AudioEffectReverb" id="rev_stone"]
room_size = 0.42
damping = 0.55
spread = 0.8
hipass = 0.15
dry = 1.0
wet = 0.16

[sub_resource type="AudioEffectHighPassFilter" id="hpf_foley"]
cutoff_hz = 60.0
db = 1

[sub_resource type="AudioEffectReverb" id="rev_foley"]
room_size = 0.30
damping = 0.60
dry = 1.0
wet = 0.14

[sub_resource type="AudioEffectCompressor" id="comp_foley"]
threshold = -16.0
ratio = 3.0
attack_us = 8000.0
release_ms = 250.0

[sub_resource type="AudioEffectHighPassFilter" id="hpf_music"]
cutoff_hz = 50.0
db = 1

[sub_resource type="AudioEffectCompressor" id="comp_music"]
threshold = -22.0
ratio = 2.5
attack_us = 80000.0
release_ms = 900.0
sidechain = &"Foley"

[sub_resource type="AudioEffectReverb" id="rev_music"]
room_size = 0.70
damping = 0.45
spread = 1.0
hipass = 0.10
dry = 1.0
wet = 0.22

[resource]
bus/0/name = &"Master"
bus/0/solo = false
bus/0/mute = false
bus/0/bypass_fx = false
bus/0/volume_db = 0.0
bus/0/send = &""
bus/0/effect/0/effect = SubResource("lim_master")
bus/0/effect/0/enabled = true
bus/1/name = &"Ambience_Sea"
bus/1/solo = false
bus/1/mute = false
bus/1/bypass_fx = false
bus/1/volume_db = -6.0
bus/1/send = &"Master"
bus/1/effect/0/effect = SubResource("hpf_sea")
bus/1/effect/0/enabled = true
bus/1/effect/1/effect = SubResource("lpf_sea")
bus/1/effect/1/enabled = true
bus/1/effect/2/effect = SubResource("comp_sea")
bus/1/effect/2/enabled = true
bus/2/name = &"Ambience_Weather"
bus/2/solo = false
bus/2/mute = false
bus/2/bypass_fx = false
bus/2/volume_db = -9.0
bus/2/send = &"Master"
bus/2/effect/0/effect = SubResource("hpf_weather")
bus/2/effect/0/enabled = true
bus/2/effect/1/effect = SubResource("lpf_weather")
bus/2/effect/1/enabled = true
bus/2/effect/2/effect = SubResource("rev_weather")
bus/2/effect/2/enabled = true
bus/3/name = &"Lighthouse_Mech"
bus/3/solo = false
bus/3/mute = false
bus/3/bypass_fx = false
bus/3/volume_db = -8.0
bus/3/send = &"Master"
bus/3/effect/0/effect = SubResource("hpf_mech")
bus/3/effect/0/enabled = true
bus/3/effect/1/effect = SubResource("rev_stone")
bus/3/effect/1/enabled = true
bus/4/name = &"Foley"
bus/4/solo = false
bus/4/mute = false
bus/4/bypass_fx = false
bus/4/volume_db = -6.0
bus/4/send = &"Master"
bus/4/effect/0/effect = SubResource("hpf_foley")
bus/4/effect/0/enabled = true
bus/4/effect/1/effect = SubResource("rev_foley")
bus/4/effect/1/enabled = true
bus/4/effect/2/effect = SubResource("comp_foley")
bus/4/effect/2/enabled = true
bus/5/name = &"Cozy_Music"
bus/5/solo = false
bus/5/mute = false
bus/5/bypass_fx = false
bus/5/volume_db = -11.0
bus/5/send = &"Master"
bus/5/effect/0/effect = SubResource("hpf_music")
bus/5/effect/0/enabled = true
bus/5/effect/1/effect = SubResource("comp_music")
bus/5/effect/1/enabled = true
bus/5/effect/2/effect = SubResource("rev_music")
bus/5/effect/2/enabled = true
```

Notes:
- `db = 1` on the filters means the 12 dB/oct slope (enum `FILTER_12DB`; 0 = 6 dB, 2 = 18 dB, 3 = 24 dB). 12 dB/oct is a soft slope that sounds like a wall rather than a switch.
- `AudioEffectHardLimiter` exists in Godot 4.3+. On older builds swap for `AudioEffectLimiter` (`ceiling_db`, `threshold_db`, `soft_clip_db`). If the parser rejects a property in your build, open the bus in the editor, set it by hand once and re-save; the editor writes the authoritative names.
- The music compressor's `sidechain` is the key to ducking: when a Foley event (door, bell-adjacent knock) fires, music dips by roughly `(level - threshold) * (1 - 1/ratio)`. For a Foley peak at -10 dB and threshold -22 with ratio 2.5: `12 * 0.6 = 7.2 dB` of duck for ~0.9 s. Music never fights the tea cup.

### 2.4 Runtime access (typed, cached, no singleton)

Each node that must touch a bus caches its index once.

```gdscript
# Pattern used by TowerAcoustics, AccessibilityPanel, etc.
const BUS_SEA: StringName = &"Ambience_Sea"
var _sea_idx: int = AudioServer.get_bus_index(BUS_SEA)       # -1 if layout missing
var _sea_lpf: AudioEffectLowPassFilter

func _ready() -> void:
	assert(_sea_idx >= 0, "Bus layout missing Ambience_Sea")
	_sea_lpf = AudioServer.get_bus_effect(_sea_idx, 1) as AudioEffectLowPassFilter  # effect slot 1
```

---

## 3. Loudness budget and safe ceilings

Philosophy: the game idles *quiet*. A sleeper should be able to leave it on.

### 3.1 Per-bus ceilings (measured post-bus, pre-Master, with `get_bus_peak_volume_left_db`)

| Bus | Idle RMS target | Sustained peak ceiling | Transient ceiling | Notes |
|---|---|---|---|---|
| Ambience_Sea | -30 dBFS | -14 dBFS | -10 dBFS (big set wave) | Content below 60 Hz capped, see 3.2 |
| Ambience_Weather | -36 dBFS (clear) / -28 (storm) | -16 dBFS | -10 dBFS (thunder) | Thunder LPF 400 Hz, 1.2 s attack |
| Lighthouse_Mech | -38 dBFS | -18 dBFS | -9 dBFS (bell) | Bell is the loudest allowed event |
| Foley | -36 dBFS | -16 dBFS | -12 dBFS | Footsteps ~ -22 dBFS typical |
| Cozy_Music | -34 dBFS | -16 dBFS | -14 dBFS | Never leads; ducked by Foley |
| Master (sum) | -24 dBFS RMS | -6 dBFS | -2 dBFS (limiter) | Worst case simultaneous = about -4 dBFS |

Worst-case sum check (peaks rarely align, but budget them as if they might):
`10^(-10/20) + 10^(-10/20) + 10^(-9/20) + 10^(-12/20) + 10^(-14/20) ≈ 0.316+0.316+0.355+0.251+0.200 = 1.44` -> +3.2 dBFS before bus volume offsets. Default bus offsets (-6, -9, -8, -6, -11 dB) bring it to roughly `0.158+0.112+0.141+0.126+0.071 = 0.61` -> -4.3 dBFS. Master limiter at -2 dBFS never has to work hard. Verify; do not trust the arithmetic.

### 3.2 Low-frequency discipline

- Hard HPF on every bus (30-60 Hz, table in 2.1). No bus may carry sustained energy under 30 Hz. Laptop speakers distort, headphones fatigue, subwoofers annoy neighbours.
- Band energy rule: energy 30-80 Hz at most -12 dB below the 80-300 Hz band for every ambient bed. Ocean "weight" comes from 80-250 Hz, not from sub-bass.
- Pink-noise slope is -3 dB/oct. When we shape it, we only ever tilt *towards* less bass, never more (see 4.2 tilt).
- A user toggle "Softer low end" (section 10) raises the Master-side HPF to 90 Hz and lowers the sea body.

### 3.3 Dynamic range targets

- Short-term loudness (3 s) at idle: -26 to -22 LUFS.
- Storm peak short-term: no more than +6 LU above idle.
- Loudness range (LRA) over a 10 minute idle capture: under 6 LU.
- Any single event more than 10 dB above the 3 s average needs a visible or musical lead-in (bell: lamp-hum swell 2 s earlier).

---

## 4. Procedural sea

### 4.1 Wave timing model (formulas)

Real swell arrives in loose groups ("sets") with a dominant period. We model wave arrival times, group amplitude, and a per-wave envelope.

**Arrival times.** Mean period `T0` (seconds) depends on sea state `s` in `[0,1]` (0 = glassy, 1 = storm):

```
T0(s)   = lerp(11.0, 6.5, s)               # calm sea = long lazy swell, storm = shorter and choppier
T_k     = T0 * (1 + 0.18 * n_k)            # n_k ~ N(0,1) clamped to [-1.5, 1.5], jitter of about 18 %
t_{k+1} = t_k + T_k
```

**Set (group) amplitude.** Waves come in sets of `N` (3 to 7). Within a set, wave `i` (0-indexed):

```
A_set(i, N) = 0.55 + 0.45 * sin(pi * (i + 0.5) / N)^1.5     # swells up and fades inside the set
A_k         = A_set * lerp(0.55, 1.0, s) * (0.9 + 0.2 * u_k)  # u_k uniform [0,1)
```
Between sets, insert a lull of `1.0 to 2.5 * T0` with `A = 0.3`.

**Per-wave envelope.** A gamma-shaped curve rises quickly, decays slowly (a roll-in then wash):

```
e(tau) = (tau / tp) * exp(1 - tau / tp)       # tau = time since wave start; peak = 1 at tau = tp
tp     = 0.32 * T_k                           # peak at about a third of the period
```
Total envelope: `E(t) = clamp( sum_k A_k * e(t - t_k), 0, 1.2 )`; waves older than `6 * tp` contribute under 1 % and are dropped.

**Spectral motion.** The crash is bright when it peaks, the backwash is hissy and fading:

```
fc(t)     = lerp(220.0, 2600.0, E^1.4)           # one-pole LP cutoff on the pink noise, Hz
gain(t)   = db_to_linear(-26 + 14 * E)           # linear amp feeding the bus, pre-bus offset
hiss(t)   = 0.35 * e(t - t_k - 0.55*T_k) * A_k    # secondary, delayed, highpassed burst (backwash)
```

The bus lowpass (indoor-driven) comes after this, so the same signal reads correctly inside and out.

### 4.2 Pink noise generator (Paul Kellet refined filter)

White -> pink at -3 dB/oct, 7 filter states, accurate within about 0.05 dB from 9 Hz to Nyquist. Tilt control `tilt` in `[0,1]` crossfades toward brown-ish by an extra leaky integrator for a softer, more distant sea.

```gdscript
class_name PinkNoise
extends RefCounted
## One instance per voice. Stateful, cheap, no allocations in the hot path.

var _b0: float = 0.0
var _b1: float = 0.0
var _b2: float = 0.0
var _b3: float = 0.0
var _b4: float = 0.0
var _b5: float = 0.0
var _b6: float = 0.0
var _brown: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

## Returns roughly [-1, 1] pink noise. tilt 0 = pink, 1 = pink + brown lean.
func next(tilt: float = 0.0) -> float:
	var w: float = _rng.randf() * 2.0 - 1.0
	_b0 = 0.99886 * _b0 + w * 0.0555179
	_b1 = 0.99332 * _b1 + w * 0.0750759
	_b2 = 0.96900 * _b2 + w * 0.1538520
	_b3 = 0.86650 * _b3 + w * 0.3104856
	_b4 = 0.55000 * _b4 + w * 0.5329522
	_b5 = -0.7616 * _b5 - w * 0.0168980
	var pink: float = (_b0 + _b1 + _b2 + _b3 + _b4 + _b5 + _b6 + w * 0.5362) * 0.11
	_b6 = w * 0.115926
	if tilt > 0.0:
		_brown = (_brown + 0.02 * w) / 1.02          # leaky integrator, DC-safe
		pink = lerpf(pink, _brown * 3.5, tilt * 0.6)
	return pink
```

Why pink and not white: white has equal energy per Hz, so it is 99 % hiss. Pink has equal energy per octave, which is what the sea sounds like. The ear hears it as "natural".

### 4.3 `SeaSwell.gd` (AudioStreamGenerator voice)

Runs at 22 050 Hz: the sea has nothing useful above 8 kHz and this halves GDScript cost. Block-processed with `push_buffer`.

```gdscript
class_name SeaSwell
extends AudioStreamPlayer2D
## Procedural sea. Put this on a Node2D at the shoreline. Two of them (west/east)
## with different seeds never phase-lock, so the island has a wide sea.

@export_range(0.0, 1.0, 0.01) var sea_state: float = 0.25   ## 0 glassy, 1 storm; set by Weather
@export var mono_mode: bool = false                           ## accessibility; see section 10
@export var seed_value: int = 0
@export var base_gain_db: float = -26.0                       ## quiet bed; bus lifts it
@export var low_energy_cap_hz: float = 70.0                   ## one-pole HPF corner, see 3.2

const MIX_RATE: float = 22050.0
const BLOCK: int = 512

var _playback: AudioStreamGeneratorPlayback
var _pink: PinkNoise
var _hiss: PinkNoise
var _lp: float = 0.0           # one-pole LP state on the crash
var _hp_lp: float = 0.0        # state of the HP corner (subtracted)
var _hiss_hp: float = 0.0
var _buf: PackedVector2Array = PackedVector2Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# wave scheduling
var _t: float = 0.0                # generator clock in seconds
var _waves: Array[Dictionary] = []  # {t0, tp, amp, T}
var _next_wave_t: float = 1.0
var _set_i: int = 0
var _set_n: int = 4
var _a_smooth: float = 0.0         # smoothed lowpass coefficient for crash

func _ready() -> void:
	_rng.seed = seed_value if seed_value != 0 else randi()
	_pink = PinkNoise.new(_rng.randi())
	_hiss = PinkNoise.new(_rng.randi())
	_buf.resize(BLOCK)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.30          # 300 ms cushion against frame hitches
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	_next_wave_t = _rng.randf_range(0.5, 3.0)   # desync the two shorelines

func _process(_delta: float) -> void:
	if _playback == null:
		return
	# Fill up to 80 % of the buffer; leave headroom so we never block.
	var target: int = int(MIX_RATE * 0.24)
	var cap: int = int(MIX_RATE * 0.30)
	while cap - _playback.get_frames_available() < target:
		_render_block()

func _schedule_wave() -> void:
	var T0: float = lerpf(11.0, 6.5, sea_state)
	var n: float = clampf(_rng.randfn(0.0, 1.0), -1.5, 1.5)
	var T: float = T0 * (1.0 + 0.18 * n)
	var amp_set: float = 0.55 + 0.45 * pow(sin(PI * (float(_set_i) + 0.5) / float(_set_n)), 1.5)
	var amp: float = amp_set * lerpf(0.55, 1.0, sea_state) * (0.9 + 0.2 * _rng.randf())
	_waves.append({"t0": _next_wave_t, "tp": 0.32 * T, "amp": amp, "T": T})
	_set_i += 1
	var gap: float = T
	if _set_i >= _set_n:                         # end of set -> lull
		_set_i = 0
		_set_n = _rng.randi_range(3, 7)
		gap = T0 * _rng.randf_range(1.0, 2.5)
		_waves[-1]["amp"] = float(_waves[-1]["amp"]) * 0.8
	_next_wave_t += gap

func _envelope_at(t: float) -> Vector2:
	# x = crash envelope E, y = backwash envelope
	var e_sum: float = 0.0
	var h_sum: float = 0.0
	for w in _waves:
		var tau: float = t - float(w["t0"])
		if tau < 0.0:
			continue
		var tp: float = float(w["tp"])
		var amp: float = float(w["amp"])
		e_sum += amp * (tau / tp) * exp(1.0 - tau / tp)
		var tb: float = tau - 0.55 * float(w["T"])
		if tb > 0.0:
			var tpb: float = 0.5 * float(w["T"])
			h_sum += 0.35 * amp * (tb / tpb) * exp(1.0 - tb / tpb)
	return Vector2(minf(e_sum, 1.2), minf(h_sum, 0.6))

func _render_block() -> void:
	while _next_wave_t < _t + 20.0:              # keep 20 s of future schedule
		_schedule_wave()
	# prune finished waves (older than 6*tp + backwash tail)
	while _waves.size() > 0 and _t - float(_waves[0]["t0"]) > float(_waves[0]["T"]) * 2.5:
		_waves.pop_front()

	var env: Vector2 = _envelope_at(_t)          # one envelope eval per block; interpolate below
	var env_next: Vector2 = _envelope_at(_t + float(BLOCK) / MIX_RATE)

	var hp_a: float = 1.0 - exp(-TAU * low_energy_cap_hz / MIX_RATE)
	var inv: float = 1.0 / float(BLOCK)
	var base_lin: float = db_to_linear(base_gain_db)
	var tilt: float = lerpf(0.35, 0.0, sea_state)     # calm sea leans softer/darker

	for i in BLOCK:
		var f: float = float(i) * inv
		var E: float = lerpf(env.x, env_next.x, f)
		var H: float = lerpf(env.y, env_next.y, f)
		var fc: float = lerpf(220.0, 2600.0, pow(clampf(E, 0.0, 1.2), 1.4))
		var a: float = 1.0 - exp(-TAU * fc / MIX_RATE)   # see optimisation note below
		_lp += a * (_pink.next(tilt) - _lp)
		# remove sub-bass (one-pole HP = x - LP(x))
		_hp_lp += hp_a * (_lp - _hp_lp)
		var crash: float = (_lp - _hp_lp) * (0.12 + 0.88 * E)
		# backwash hiss: highpassed pink, only when H is present
		var hn: float = _hiss.next(0.0)
		_hiss_hp += 0.25 * (hn - _hiss_hp)
		var hiss: float = (hn - _hiss_hp) * H * 0.5
		var s: float = (crash + hiss) * base_lin * (1.0 + 4.0 * E)   # E lifts level ~ +14 dB
		_buf[i] = Vector2(s, s)

	_t += float(BLOCK) / MIX_RATE
	_playback.push_buffer(_buf)
```

Performance notes:
- `exp()` per sample is the heaviest line. Cheaper: compute `a` once per block from the block-average fc, then `lerp` to the next block's `a`. At 22 050 Hz this is already about 43 blocks/s, trivial.
- Two shorelines -> two 22 kHz generators -> roughly 0.5 ms/frame on desktop. Budget for the web export: drop to one generator and rely on `SeaWash` static loop for the second layer.
- Fallback for weak targets: bake 60 s of the same generator offline into an `.ogg` loop (write a throwaway `@tool` script that renders the generator to `AudioStreamWAV`), crossfade two copies of the loop with 4 s overlap. Same bus chain either way.

### 4.4 Tide and distance

Tide height `h` in `[0,1]` from the game clock (12.4 h cycle compressed to a game-day):

```
h(day_phase) = 0.5 + 0.5 * sin(TAU * day_phase * 2 - 0.6)   # two tides per game-day
sea_state_effective = clamp(sea_state + 0.15 * h, 0, 1)
SeaSwell.position distance to shoreline = lerp(60, 20, h) px    # surf moves closer at high tide
```
The 2D attenuation (section 8) then gives the player a reason to walk to the cliff edge and *hear* the water.

---

## 5. Rain: outside vs inside the stone tower

### 5.1 Rain model

Rain intensity `r` in `[0,1]` from the Weather node.

```
bed_db(r)   = -38 + 16 * r                     # diffuse sheet of drops, pre-bus
lambda(r)   = 30 + 900 * r^1.3                 # discrete drop events per second (Poisson)
drop_amp    = u^2.2 * (0.25 + 0.75 * r)        # many tiny drops, few big ones (u uniform)
drop_decay  = 6 ms to 18 ms exponential tail
bed_band    = highpass 1.5 kHz, lowpass 7 kHz  # rain is "tsss", it has no body
```

Per-sample drop probability is `p = lambda / mix_rate`. A drop adds `drop_amp` to a burst envelope that decays by `exp(-1/(tau*mix_rate))` per sample and multiplies a noise source.

### 5.2 `RainVoice.gd` (outdoor character)

```gdscript
class_name RainVoice
extends AudioStreamPlayer
## Non-positional rain bed. Sits on Ambience_Weather. The bus LPF turns it into "indoor rain".

@export_range(0.0, 1.0, 0.01) var rain: float = 0.0

const MIX_RATE: float = 32000.0
const BLOCK: int = 512

var _playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _buf: PackedVector2Array = PackedVector2Array()
var _burst: float = 0.0
var _lp_hi: float = 0.0     # LP at ~7 kHz
var _lp_lo: float = 0.0     # LP at ~1.5 kHz (subtracted -> HP)
var _smooth_rain: float = 0.0

func _ready() -> void:
	_rng.randomize()
	_buf.resize(BLOCK)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.30
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(delta: float) -> void:
	_smooth_rain = lerpf(_smooth_rain, rain, 1.0 - exp(-delta / 4.0))   # 4 s time constant: rain fades in, never snaps
	if _playback == null:
		return
	while _playback.get_frames_available() > int(MIX_RATE * 0.12) + BLOCK:
		_render()

func _render() -> void:
	var r: float = _smooth_rain
	if r < 0.002:
		for i in BLOCK:
			_buf[i] = Vector2.ZERO
		_playback.push_buffer(_buf)
		return
	var lambda_: float = 30.0 + 900.0 * pow(r, 1.3)
	var p: float = lambda_ / MIX_RATE
	var bed: float = db_to_linear(-38.0 + 16.0 * r) * 2.0
	var a_hi: float = 1.0 - exp(-TAU * 7000.0 / MIX_RATE)
	var a_lo: float = 1.0 - exp(-TAU * 1500.0 / MIX_RATE)
	var dec: float = exp(-1.0 / (0.010 * MIX_RATE))             # 10 ms tail
	for i in BLOCK:
		if _rng.randf() < p:
			_burst += pow(_rng.randf(), 2.2) * (0.25 + 0.75 * r)
		_burst *= dec
		var n: float = _rng.randf() * 2.0 - 1.0
		_lp_hi += a_hi * (n - _lp_hi)
		_lp_lo += a_lo * (_lp_hi - _lp_lo)
		var band: float = _lp_hi - _lp_lo                        # 1.5 - 7 kHz
		var s: float = band * (bed + _burst * 0.6)
		# stereo decorrelation: tiny random offset keeps the sheet wide
		var w: float = (_rng.randf() - 0.5) * 0.02 * bed
		_buf[i] = Vector2(s + w, s - w)
	_playback.push_buffer(_buf)
```

### 5.3 Occlusion math (inside the tower)

Stone mass law for a 0.9 m wall (surface mass `m` about 2000 kg/m^2) predicts more than 60 dB of loss above 500 Hz, which would erase the world. Games need *felt* occlusion, not physics, so we use a game-tuned model:

```
Openings:  d = door_open [0,1],  w = window_open [0,1]
o          = 1 - (1 - 0.85 * d) * (1 - 0.35 * w)        # open fraction; door leaks a lot, window some

per-bus targets (closed -> open):
  Ambience_Weather:  fc 700 Hz  -> 12000 Hz,   gain -20 dB -> 0 dB
  Ambience_Sea:      fc 420 Hz  ->  9000 Hz,   gain -14 dB -> 0 dB
fc(o)      = fc_closed * (fc_open / fc_closed) ^ o        # log-domain: equal-ratio per step = perceptually linear
gain_db(o) = lerp(gain_closed, 0, o^0.7)                  # slightly front-loaded: cracking a door helps a lot
```

Indoor blend `i` (1 = inside, 0 = outside) crossfades `o_eff`:

```
o_eff = lerp(1.0, o, i)       # outside the tower, openings are irrelevant: everything is "open"
```

Smoothing (never step a filter, it clicks and feels wrong):

```
o_s <- o_s + (o_eff - o_s) * (1 - exp(-dt / 0.35))     # tau = 350 ms, doors feel physical
```

Roof thud (the gift of being inside while it rains) is *positive* occlusion: rain on slate becomes audible only inside.

```
thud_db(r, i) = -48 + 22 * i + 10 * r      # clamp to <= -22 dB
thud_hz       = 180 + 140 * u              # per-hit pitch jitter, 180-320 Hz
thud_rate     = 0.4 + 3.5 * r^1.2 Hz       # irregular (Poisson), not a metronome
```

### 5.4 `RainRoof.gd`

```gdscript
class_name RainRoof
extends AudioStreamPlayer2D
## Soft low thuds of rain on the lantern-room roof. Quiet outside, present inside.
## Lives on the Lighthouse node, bus Lighthouse_Mech.

@export_range(0.0, 1.0, 0.01) var rain: float = 0.0
@export_range(0.0, 1.0, 0.01) var indoors: float = 0.0   # written by TowerAcoustics

const MIX_RATE: float = 16000.0
const BLOCK: int = 512

var _playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _buf: PackedVector2Array = PackedVector2Array()
var _env: float = 0.0
var _phase: float = 0.0
var _freq: float = 220.0

func _ready() -> void:
	_rng.randomize()
	_buf.resize(BLOCK)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.30
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(_d: float) -> void:
	if _playback == null:
		return
	while _playback.get_frames_available() > int(MIX_RATE * 0.12) + BLOCK:
		_render()

func _render() -> void:
	var level_db: float = minf(-48.0 + 22.0 * indoors + 10.0 * rain, -22.0)
	var amp: float = db_to_linear(level_db) * smoothstep(0.02, 0.15, rain)
	var rate: float = 0.4 + 3.5 * pow(rain, 1.2)
	var p: float = rate / MIX_RATE
	var dec: float = exp(-1.0 / (0.060 * MIX_RATE))        # 60 ms body
	for i in BLOCK:
		if _rng.randf() < p:
			_env = _rng.randf_range(0.4, 1.0)
			_freq = 180.0 + 140.0 * _rng.randf()
			_phase = 0.0
		_env *= dec
		_phase += TAU * _freq / MIX_RATE
		var s: float = sin(_phase) * _env * _env * amp      # squared env = soft attack on the tail, no click
		_buf[i] = Vector2(s, s)
	_playback.push_buffer(_buf)
```

---

## 6. Wind whistling through vent shafts

### 6.1 Physics-lite model

A slot or shaft of effective gap `d` (m) in airflow `v` (m/s) sheds vortices at the edge-tone frequency:

```
f = St * v / d              St (Strouhal) ≈ 0.2 for edge tones
```
With `d = 0.0045 m` (a drilled vent plate), `v` from 4 to 14 m/s gives `f = 178 to 622 Hz`, a mellow, owl-like range. We deliberately keep `f < 900 Hz` and `Q <= 40` so it sings but never shrieks.

Wind speed is a mean-reverting random walk (Ornstein-Uhlenbeck), so gusts are organic and bounded:

```
v_{n+1} = v_n + theta * (v_mean - v_n) * dt + sigma * sqrt(dt) * N(0,1)
theta = 0.35 /s (return rate),  sigma = 1.6 m/s/sqrt(s),  v_mean = lerp(3, 11, storm)
```
Whistle level follows a soft threshold so there is silence in light air:

```
level(v) = smoothstep(4.0, 13.0, v)           # 0 below 4 m/s, 1 at 13
gain_db  = -36 + 8 * level                    # never louder than -28 dB pre-bus
Q(v)     = lerp(12.0, 38.0, level)            # narrower when blowing hard
```

### 6.2 Approach: noise + state-variable bandpass in an `AudioStreamGenerator`

A bandpass at `f` with high Q on white noise rings like a tube. Two parallel resonators at `f` and `1.5 f` (a fifth above) give the shaft its shape. One generator drives two vent emitters with different `d` (low and high shaft) so they never agree.

```gdscript
class_name VentWhistle
extends AudioStreamPlayer2D
## Wind through a vent shaft. Bus Lighthouse_Mech (unoccluded: the vent IS the leak).

@export_range(0.002, 0.02, 0.0005) var gap_m: float = 0.0045   ## effective slot width
@export_range(0.0, 1.0, 0.01) var storm: float = 0.2
@export var max_hz: float = 900.0

const MIX_RATE: float = 22050.0
const BLOCK: int = 256
const STROUHAL: float = 0.2

var _playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _buf: PackedVector2Array = PackedVector2Array()
var _v: float = 4.0                      # current wind speed, m/s
# SVF states (two resonators)
var _l1: float = 0.0
var _b1: float = 0.0
var _l2: float = 0.0
var _b2: float = 0.0
var _gain_s: float = 0.0                 # smoothed gain

func _ready() -> void:
	_rng.randomize()
	_buf.resize(BLOCK)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.30
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(delta: float) -> void:
	# Ornstein-Uhlenbeck wind speed
	var v_mean: float = lerpf(3.0, 11.0, storm)
	_v += 0.35 * (v_mean - _v) * delta + 1.6 * sqrt(delta) * _rng.randfn(0.0, 1.0)
	_v = clampf(_v, 0.0, 16.0)
	if _playback == null:
		return
	while _playback.get_frames_available() > int(MIX_RATE * 0.12) + BLOCK:
		_render()

## Chamberlin-style state-variable filter step -> bandpass output.
func _svf(x: float, f: float, q: float, low: float, band: float) -> Vector3:
	var high: float = x - low - band / q
	band += f * high
	low += f * band
	return Vector3(band, low, band)      # (out, new_low, new_band)

func _render() -> void:
	var level: float = smoothstep(4.0, 13.0, _v)
	var target_gain: float = db_to_linear(-36.0 + 8.0 * level) * level
	var fc: float = minf(STROUHAL * _v / gap_m, max_hz)
	var q: float = lerpf(12.0, 38.0, level)
	# SVF tuning coefficient f = 2 sin(pi fc / fs); stable for fc < fs/6
	var f1: float = 2.0 * sin(PI * fc / MIX_RATE)
	var f2: float = 2.0 * sin(PI * minf(fc * 1.5, max_hz * 1.5) / MIX_RATE)
	for i in BLOCK:
		_gain_s += 0.0005 * (target_gain - _gain_s)       # about 90 ms glide
		var n: float = _rng.randf() * 2.0 - 1.0
		var r1: Vector3 = _svf(n, f1, q, _l1, _b1)
		_l1 = r1.y
		_b1 = r1.z
		var r2: Vector3 = _svf(n, f2, q * 0.8, _l2, _b2)
		_l2 = r2.y
		_b2 = r2.z
		# band output of high-Q SVF is quiet: scale by about 1/Q... but compensated by +gain
		var s: float = (r1.x + 0.45 * r2.x) * _gain_s * (q * 0.35)
		_buf[i] = Vector2(s, s)
	_playback.push_buffer(_buf)
```

Stability notes:
- Chamberlin SVF is unconditionally stable only for `f < ~1.2`; with `fc <= 1350 Hz` at 22 050 Hz, `f = 2 sin(pi * 1350/22050) ≈ 0.38`. Safe.
- Add a safety clamp `s = clampf(s, -0.5, 0.5)` if you let designers push `gap_m` very low.

### 6.3 Cheaper alternative: noise + `AudioEffectBandPassFilter` on a dedicated sub-bus

Not used by default because buses are global (one resonance for all vents). Use it only if you want a single global "drone": a looped white-noise `AudioStreamWAV` with an `AudioEffectBandPassFilter` whose `cutoff_hz` you drive from the same OU wind. The generator approach above is preferred: each vent owns its voice and position.

### 6.4 General wind bed (broad whoosh, not whistle)

Use the same `PinkNoise` + one-pole LP at `fc = lerp(180, 900, level)` and gain `-34 + 10*level` dB, on `Ambience_Weather` (so it gets occluded indoors). The vent whistle on `Lighthouse_Mech` *survives* the occlusion: inside the tower you hear a muffled storm plus bright, close vent singing. That contrast is the cozy payoff: "it's wild out there and I am warm".

---

## 7. `TowerAcoustics.gd` (smooth indoor/outdoor blend)

One node on the Lighthouse. It watches an `Area2D` (the tower interior footprint) and a door/window state, then writes bus filter targets. It exposes `indoors` to the emitters that care.

```gdscript
class_name TowerAcoustics
extends Node
## Owns the occlusion filters for Ambience_Weather and Ambience_Sea.
## Wire: interior_zone.body_entered/exited -> _on_zone_*; door and window set open amounts.

@export var interior_zone: Area2D
@export var player: Node2D                              # whose body counts as "inside"
@export var roof_thud: RainRoof
@export_range(0.0, 1.0, 0.01) var door_open: float = 0.0
@export_range(0.0, 1.0, 0.01) var window_open: float = 0.0
@export var blend_tau: float = 0.35                     ## seconds, filter glide
@export var zone_tau: float = 0.8                       ## seconds, crossfading between in/out

const WEATHER: StringName = &"Ambience_Weather"
const SEA: StringName = &"Ambience_Sea"
const LPF_SLOT: int = 1                                 # matches default_bus_layout.tres

var _inside: bool = false
var _i: float = 0.0          # smoothed indoor factor
var _o_s: float = 1.0        # smoothed openness
var _weather_idx: int
var _sea_idx: int
var _weather_lpf: AudioEffectLowPassFilter
var _sea_lpf: AudioEffectLowPassFilter

func _ready() -> void:
	_weather_idx = AudioServer.get_bus_index(WEATHER)
	_sea_idx = AudioServer.get_bus_index(SEA)
	_weather_lpf = AudioServer.get_bus_effect(_weather_idx, LPF_SLOT) as AudioEffectLowPassFilter
	_sea_lpf = AudioServer.get_bus_effect(_sea_idx, LPF_SLOT) as AudioEffectLowPassFilter
	if interior_zone:
		interior_zone.body_entered.connect(_on_body_entered)
		interior_zone.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body == player:
		_inside = true

func _on_body_exited(body: Node2D) -> void:
	if body == player:
		_inside = false

func _process(delta: float) -> void:
	_i = move_toward(_i, 1.0 if _inside else 0.0, delta / zone_tau)
	var o_raw: float = 1.0 - (1.0 - 0.85 * door_open) * (1.0 - 0.35 * window_open)
	var o_eff: float = lerpf(1.0, o_raw, _i)
	_o_s += (o_eff - _o_s) * (1.0 - exp(-delta / blend_tau))
	_apply(_weather_idx, _weather_lpf, 700.0, 12000.0, -20.0)
	_apply(_sea_idx, _sea_lpf, 420.0, 9000.0, -14.0)
	if roof_thud:
		roof_thud.indoors = _i

func _apply(idx: int, lpf: AudioEffectLowPassFilter, fc_closed: float, fc_open: float, gain_closed_db: float) -> void:
	lpf.cutoff_hz = fc_closed * pow(fc_open / fc_closed, _o_s)
	# Occlusion gain sits on top of the user's bus volume, so we store the user's value separately.
	var user_db: float = _user_db(idx)
	AudioServer.set_bus_volume_db(idx, user_db + lerpf(gain_closed_db, 0.0, pow(_o_s, 0.7)))

func _user_db(idx: int) -> float:
	# Read from meta set by the AccessibilityPanel / options scene; falls back to layout defaults.
	var key: StringName = AudioServer.get_bus_name(idx)
	return float(AudioServer.get_meta(&"user_db_" + key, _default_db(key))) if false else _default_db(key)

func _default_db(key: StringName) -> float:
	return -9.0 if key == WEATHER else -6.0
```

Caveat on `_user_db`: `AudioServer` cannot hold meta. Cleaner and consistent with "no singleton": options UI writes user trims into the *Master-side* stage instead, so occlusion owns the per-bus volume. Concretely, put user sliders on the buses' **send level** through a second approach: give each bus's user trim to `AudioEffectAmplify` (slot 3 in each ambient bus, `volume_db` = user trim) and let occlusion own `AudioServer.set_bus_volume_db`. Then replace `_user_db` with `return 0.0` plus the default of the layout (`-6`, `-9`). Document this in the layout; it avoids the two systems fighting over `volume_db`.

Door `Area2D` hint: the door script just sets `tower_acoustics.door_open` from its animation `AnimationPlayer` track (0 -> 1 over the swing time), so the filter opens *with* the door.

---

## 8. `AudioStreamPlayer2D` usage and attenuation

### 8.1 How Godot 2D attenuation works (4.x)

For `AudioStreamPlayer2D`, with `d` = distance to the active listener (Camera2D or `AudioListener2D`), in pixels:

```
vol_lin = pow(1 - d / max_distance, attenuation)      # d < max_distance, else silent
```

`attenuation` is an exponent (default 1.0 = linear fade; 2.0 = quicker nearby falloff; 0.5 = stays loud longer then drops). `panning_strength` (default 1.0) scales pan from the projected angle, `0.0` is centered mono. `area_mask` selects which `Area2D` audio bus overrides apply (use for a cave/tower interior reverb: `Area2D` with `audio_bus_override = true` and `audio_bus_name` set).

For a pixel-art view of 480x270 (or 640x360), a "long" distance is only about 300-500 px, so Godot's default `max_distance = 2000` is wrong for us: everything would sound equally loud. Use viewport-relative values.

### 8.2 Recommended settings

| Node | max_distance (px) | attenuation | panning_strength | volume_db | Notes |
|---|---|---|---|---|---|
| SeaSwellWest/East | 700 | 1.6 | 0.55 | 0 | Wide, soft; stays audible across the island |
| SeaWash (close loop) | 220 | 2.0 | 0.4 | -3 | Only near the waterline |
| RainBed / WindBed | n/a (AudioStreamPlayer) | n/a | n/a | 0 | Non-positional |
| Thunder | 1400 | 0.7 | 0.3 | 0 | Far, big, barely panned |
| RoofThud | 260 | 1.2 | 0.2 | 0 | Audible only near/inside tower |
| VentShaftLow/High | 180 | 1.8 | 0.7 | 0 | Close whistle, charming at the stairs |
| LampHum | 160 | 1.5 | 0.2 | -4 | Warm focal tone, rises as you climb |
| GearTick | 140 | 2.0 | 0.5 | 0 | Quiet mechanical comfort |
| Bell | 900 | 0.9 | 0.5 | 0 | Carries over the island |
| Footsteps / Foley | 220 | 1.4 | 0.6 | 0 | Close, intimate |

### 8.3 Bus override on the interior zone

```gdscript
# On the tower interior Area2D (in the scene or in code):
interior_zone.audio_bus_override = true
interior_zone.audio_bus_name = &"Lighthouse_Mech"    # sounds heard *by the listener* while inside route here
```
Use this sparingly: with the bus-LPF approach in section 7 the override is unnecessary. It is a good fit for a *separate* optional space, e.g. a cellar with a long reverb bus, where you want per-player-position reverb rather than global filters.

### 8.4 One-shot foley pattern (no pooling singleton)

```gdscript
class_name FootstepVoice
extends AudioStreamPlayer2D

@export var surfaces: Dictionary[StringName, AudioStreamRandomizer] = {}   # Godot 4.4+ typed dictionaries

func step(surface: StringName, speed_ratio: float) -> void:
	var r: AudioStreamRandomizer = surfaces.get(surface)
	if r == null:
		return
	stream = r                                   # randomizer: random_pitch 1.06, random_volume_offset_db 2.0
	volume_db = -4.0 + 4.0 * speed_ratio         # walking soft, hurrying a little firmer
	pitch_scale = randf_range(0.97, 1.03)
	play()
```
`AudioStreamRandomizer` handles variation without code; set `random_pitch = 1.05`, `random_volume_offset_db = 1.5`, `playback_mode = PLAYBACK_RANDOM_NO_REPEATS`.

---

## 9. Cozy_Music: non-intrusive instrumentation

### 9.1 Palette

- Instruments: felt/upright piano with soft hammers, music box (sparingly), warm sine/triangle pad, nylon-string guitar, low (not sub) cello long tones, tape-softened glockenspiel for the lamp-lit moments, distant accordion drone in storms.
- Avoid: sustained bass below 80 Hz, bright strings, snare/hats, any kick, brass, reverbed vocal pads that drown the sea.
- Rhythm: none required. If pulse is needed, 52-66 BPM, soft finger-tapped or brushed, below -22 dBFS.
- Harmony: modal and open (Dorian, Lydian, major pentatonic). Avoid leading tones and V-I cadences, which feel like "something is about to happen". Prefer a drift between IVsus2 and Imaj7.
- Register: melody 250 Hz - 1.4 kHz (C4-F6). Pads 120-500 Hz. Nothing below 80 Hz except a single soft cello note per phrase, and even that is HPF'd.
- Silence is an instrument: music is *off* at least 50 % of the time. The sea is the main voice.
- Attack: >= 12 ms soft; sustains 3-8 s; release tails into the bus reverb.
- Mix: music sits 8-12 dB under the sea on average. If you hear it consciously, it is too loud.

### 9.2 `CozyMusicBox.gd` (sparse pentatonic scheduler, pitch-scaled samples)

One sampled note (root `C4 = 261.63 Hz`) is pitch-shifted by `pitch_scale = 2^(semitones/12)`. For quality keep the shift within +/- 7 semitones of each recorded root; ship one sample per octave.

```gdscript
class_name CozyMusicBox
extends Node
## Plays slow, sparse melodic fragments. Children: AudioStreamPlayer x 6 (bus Cozy_Music), no stream preset.

@export var note_sample: AudioStream                 ## soft piano C4, long tail
@export var pad_sample: AudioStream                  ## warm pad on C3, loops internally
@export var scale_semitones: PackedInt32Array = PackedInt32Array([0, 2, 4, 7, 9])   # major pentatonic
@export var min_gap_s: float = 8.0
@export var max_gap_s: float = 25.0
@export_range(0.0, 1.0, 0.01) var storm: float = 0.0   ## lowers music, widens gaps
@export_range(0.0, 1.0, 0.01) var night: float = 0.0   ## darker: fewer notes, lower register

var _voices: Array[AudioStreamPlayer] = []
var _next: int = 0
var _timer: Timer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_degree: int = 0

func _ready() -> void:
	_rng.randomize()
	for c in get_children():
		if c is AudioStreamPlayer:
			_voices.append(c)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_phrase)
	add_child(_timer)
	_timer.start(_rng.randf_range(3.0, 8.0))

func _phrase() -> void:
	var notes: int = _rng.randi_range(2, 5 - int(night * 2.0))
	var t: float = 0.0
	for k in notes:
		get_tree().create_timer(t).timeout.connect(_play_note.bind(k == 0))
		t += _rng.randf_range(0.9, 2.4)                       # slow, uneven spacing
	var gap: float = _rng.randf_range(min_gap_s, max_gap_s) * lerpf(1.0, 1.7, storm) * lerpf(1.0, 1.3, night)
	_timer.start(t + gap)

func _play_note(is_first: bool) -> void:
	var step: int = clampi(_last_degree + _rng.randi_range(-2, 2), 0, scale_semitones.size() - 1)
	_last_degree = step
	var oct: int = -1 if (night > 0.5 and _rng.randf() < 0.5) else 0
	var semis: int = scale_semitones[step] + 12 * oct
	var v: AudioStreamPlayer = _voices[_next]
	_next = (_next + 1) % _voices.size()
	v.stream = note_sample
	v.pitch_scale = pow(2.0, float(semis) / 12.0)
	v.volume_db = -8.0 - 6.0 * storm - (3.0 if not is_first else 0.0) + _rng.randf_range(-2.0, 0.0)
	v.play()
```

### 9.3 Mix context rules

- Storm: `Cozy_Music.volume_db` drops by `4 * storm` and note gaps widen 1.7x (set via the Weather node's signal, not a manager).
- Bell strike: ducking is automatic via sidechain from Foley if the bell sends to Foley; since the bell lives on `Lighthouse_Mech`, either set the music compressor's `sidechain` to `Lighthouse_Mech`, or tween music `-4 dB` for 3 s in `Bell.gd` with a local `Tween`. Prefer the local tween: it is on the physical bell.
- Lamp lit at dusk: the music pad fades in over 20 s, never starts abruptly.

---

## 10. Accessibility and comfort

Settings persist in `user://audio_comfort.cfg` (ConfigFile). A single `AudioComfortPanel` Control in the options scene owns the UI and applies values to buses and to the emitters that expose the relevant flags. No global autoload: the panel re-applies on `_ready()` of the options scene and the main scene calls `apply()` on startup via an exported `Resource`.

### 10.1 Settings resource

```gdscript
class_name AudioComfort
extends Resource

@export_range(0.0, 1.0, 0.01) var master: float = 0.8
@export_range(0.0, 1.0, 0.01) var sea: float = 1.0
@export_range(0.0, 1.0, 0.01) var weather: float = 1.0
@export_range(0.0, 1.0, 0.01) var mech: float = 1.0
@export_range(0.0, 1.0, 0.01) var foley: float = 1.0
@export_range(0.0, 1.0, 0.01) var music: float = 1.0
@export var mono: bool = false
@export var reduced_low_frequency: bool = false
@export var gentle_dynamics: bool = false       ## squashes peaks, flattens loudness range
@export var quiet_bell: bool = false             ## bell -9 dB and slower attack
@export var visual_sound_cues: bool = true       ## UI pulse when bell/thunder occur (for deaf/HoH players)

const PATH: String = "user://audio_comfort.cfg"

func save() -> void:
	var cfg := ConfigFile.new()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			cfg.set_value("audio", p.name, get(p.name))
	cfg.save(PATH)

static func load_or_default() -> AudioComfort:
	var c := AudioComfort.new()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for p in c.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and cfg.has_section_key("audio", p.name):
				c.set(p.name, cfg.get_value("audio", p.name))
	return c
```

### 10.2 Applying to buses

User trim lives on the **last** effect slot of each bus: an `AudioEffectAmplify` (add it to the layout at slots 3/2/2/3/3, `volume_db` driven by this). That leaves `bus.volume_db` free for occlusion (see section 7 caveat).

```gdscript
func apply(c: AudioComfort) -> void:
	_set_trim(&"Master", c.master, 0)                      # Master amplify slot (add after limiter? no: before)
	_set_trim(&"Ambience_Sea", c.sea, 3)
	_set_trim(&"Ambience_Weather", c.weather, 3)
	_set_trim(&"Lighthouse_Mech", c.mech, 2)
	_set_trim(&"Foley", c.foley, 3)
	_set_trim(&"Cozy_Music", c.music, 3)

func _set_trim(bus: StringName, linear: float, slot: int) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	var amp := AudioServer.get_bus_effect(idx, slot) as AudioEffectAmplify
	amp.volume_db = linear_to_db(maxf(linear, 0.0001))
```

Slider mapping: slider value `x` in `[0,1]` -> `db = linear_to_db(x^2)`, so the bottom half of the slider covers the quiet range where it matters (a straight linear mapping puts 60 % of the useful range in the last 10 % of travel). Master default 0.8 so there is always room to go louder.

### 10.3 Mono

Godot has no built-in bus mono-sum effect. Three-part strategy:
1. Generators: `mono_mode` flag on `SeaSwell`, `RainVoice` writes `Vector2(s, s)` (no decorrelation), so procedural content is mono by construction.
2. `panning_strength = 0.0` on every `AudioStreamPlayer2D`:
   ```gdscript
   func set_mono(on: bool) -> void:
       for n in get_tree().get_nodes_in_group(&"audio_2d"):
           (n as AudioStreamPlayer2D).panning_strength = 0.0 if on else (n.get_meta(&"pan", 1.0) as float)
   ```
   Tag every 2D emitter with group `audio_2d` and `set_meta(&"pan", panning_strength)` in `_ready`.
3. Recorded stereo assets: import presets include a mono variant (`force/mono = true` in `.import` for `AudioStreamWAV`/`AudioStreamOggVorbis` is not available for Ogg; for Ogg store stereo loops as already mid-heavy, or ship `*_mono.wav` for ambient beds only). Reverbs still produce stereo width: the `spread` of `AudioEffectReverb` can be set to `0.0` when `mono` is on, which keeps tails centered.
Also set `AudioEffectStereoEnhance.pan_pullout = 0.0` if you use it.

### 10.4 Reduced low frequency

When `reduced_low_frequency` is on:

| Change | Value |
|---|---|
| Sea HPF `cutoff_hz` | 30 -> 100 Hz |
| Weather HPF | 40 -> 120 Hz |
| Mech HPF | 45 -> 120 Hz |
| Foley HPF | 60 -> 140 Hz |
| Music HPF | 50 -> 110 Hz |
| `SeaSwell.low_energy_cap_hz` | 70 -> 150 Hz |
| Thunder LPF | 400 -> 250 Hz and gain -6 dB |
| Bell | pitch +2 semitones off by default? keep, but -3 dB |

Implementation: `AudioServer.get_bus_effect(idx, 0) as AudioEffectHighPassFilter` -> set `cutoff_hz`. Done at apply-time, not per frame.

### 10.5 Gentle dynamics and quiet bell

- `gentle_dynamics`: enable a Master `AudioEffectCompressor` (threshold -20, ratio 3, attack 30 ms, release 400 ms, gain +3 dB) placed *before* the limiter; lowers the dynamic range, so a sleeping player is not startled by the bell.
- `quiet_bell`: `Bell.volume_db -= 9`, and `Bell` plays a 1.5 s softened-attack variant of the sample (pre-rendered with a 1.2 s fade-in on the transient).
- Visual cues (`visual_sound_cues`): ring pulses on the bell, a small lightning flash overlay for thunder, and a "tide rising" shimmer. For deaf or hard-of-hearing players, audio is atmosphere, never the only channel for gameplay information.

### 10.6 Photosensitive / startle safety

- Thunder: 1.2 s rise via bus filter (lowpass opens), first lightning *visual* precedes it by the physics delay `delay_s = distance_px / 340` scaled so that max delay is 6 s.
- No sudden silence either: when the game pauses, fade buses by `-12 dB` over 300 ms, do not mute hard.

---

## 11. Loudness test checklist

### 11.1 In-engine meters (non-intrusive debug overlay)

A tiny `AudioMeterOverlay` Control (editor/debug builds only, `OS.is_debug_build()`) polls per bus:

```gdscript
extends Label
const BUSES: Array[StringName] = [&"Master", &"Ambience_Sea", &"Ambience_Weather", &"Lighthouse_Mech", &"Foley", &"Cozy_Music"]
var _peak_hold: Dictionary[StringName, float] = {}

func _process(delta: float) -> void:
	var out: String = ""
	for b in BUSES:
		var idx: int = AudioServer.get_bus_index(b)
		var pk: float = maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
		_peak_hold[b] = maxf(pk, _peak_hold.get(b, -80.0) - 6.0 * delta)   # fall 6 dB/s
		out += "%-18s %6.1f dBFS  (hold %6.1f)\n" % [b, pk, _peak_hold[b]]
	text = out
```

### 11.2 Offline measurement

Record the game output via loopback (or Godot's `--write-movie out.avi` which captures audio deterministically), then:

```bash
ffmpeg -i capture.wav -af ebur128=peak=true -f null - 2>&1 | grep -E "I:|LRA:|Peak:|S:" | tail -5
```
Targets: Integrated about -26 LUFS idle; LRA < 6 LU; True Peak <= -3 dBTP.

### 11.3 Checklist (run every audio PR)

Static setup:
- [ ] `default_bus_layout.tres` loads; all six buses present, sends = Master.
- [ ] HPF slot 0 present on every non-master bus (cutoffs per 2.1).
- [ ] Master limiter ceiling -2.0 dBFS, enabled.
- [ ] No node plays on `Master` directly (grep for `bus = &"Master"` / unset bus in `.tscn`; unset defaults to Master).
- [ ] Every `AudioStreamPlayer2D` has `max_distance` set deliberately (none left at 2000).
- [ ] No generator `mix_rate` above 32 000 Hz, `buffer_length` between 0.2 and 0.5 s.

Idle (clear weather, daytime, player on beach, 3 minutes):
- [ ] Short-term loudness -26 to -22 LUFS.
- [ ] `Ambience_Sea` sustained peak <= -14 dBFS, set-wave peak <= -10 dBFS.
- [ ] Spectrum (any analyser): no sustained energy below 30 Hz; 30-80 Hz at least 12 dB under 80-300 Hz.
- [ ] Wave sets audibly varied; no obvious repetition over 5 minutes.
- [ ] Music silent at least 50 % of the time; never audible over the first 5 s of a fresh scene load.

Weather:
- [ ] Rain ramp 0 -> 1 takes about 4 s and has no click or step.
- [ ] Storm peak short-term no more than +6 LU over idle.
- [ ] Thunder max peak <= -10 dBFS on Weather bus, 1.2 s rise.
- [ ] Vent whistle never above 900 Hz fundamental; level <= -28 dB pre-bus; no ringing when wind drops to 0.

Occlusion:
- [ ] Walk in/out of the tower: filter glides in about 0.35-0.8 s, no click, no step in volume.
- [ ] Open door: weather brightens in sync with the animation; close door: returns.
- [ ] Inside with rain: roof thud audible but <= -22 dB; outside: roof thud inaudible.
- [ ] Crossing the threshold does not change apparent loudness by more than 3 LU.

Events:
- [ ] Bell: peak <= -9 dBFS on Mech bus; music dips; sea does not duck.
- [ ] Door/footsteps: duck music by about 3-7 dB then recover in under 1.5 s.
- [ ] Simultaneous worst-case (storm + bell + thunder + door): Master peak <= -4 dBFS pre-limiter; limiter gain reduction under 3 dB.

Accessibility:
- [ ] Mono toggle: all emitters centered, no phasing artefacts, reverb centered.
- [ ] Reduced low frequency toggle: sub-100 Hz content removed; ocean still convincing (hear the hiss and mid body).
- [ ] Gentle dynamics: LRA under 4 LU.
- [ ] Quiet bell: peak <= -18 dBFS.
- [ ] All sliders reach true silence at 0; Master slider max cannot exceed limiter ceiling.
- [ ] Settings persist across restarts; defaults ship **conservative** (Master 0.8).

Hardware passes:
- [ ] Laptop speakers: no distortion at default; ocean still present (you lose the lows, that is fine).
- [ ] Open-back headphones at a comfortable level: nothing makes you reach for the volume.
- [ ] Bluetooth earbuds (lossy, laggy): no stutter from generator underrun; check `AudioServer.get_output_latency()` < 0.1 s; bump `buffer_length` to 0.4 if needed.
- [ ] Sleep test: 30 minutes idle, then a listener who is half asleep: nothing startles.

---

## 12. Project settings and gotchas

Project Settings (project.godot):
```ini
[audio]
buses/default_bus_layout="res://audio/default_bus_layout.tres"
buses/channel_disable_threshold_db=-72.0
buses/channel_disable_time=2.0
driver/mix_rate=44100
driver/output_latency=30
general/2d_panning_strength=0.6
```
- `output_latency` of 30 ms plus generator `buffer_length` 0.3 s is the safety margin for GDScript-driven generators; reduce only after profiling.
- `channel_disable_threshold_db = -72`: silent buses (clear weather, no rain) stop being mixed, saving CPU. Do not raise it above -60 or you will truncate the quietest reverb tails.
- Generators that fall silent (rain = 0) still push zero buffers in the code above to keep the playback alive; do not `stop()` them or the playback object is invalidated (`get_stream_playback()` returns null on a stopped player).
- Do not call `AudioServer.lock()` from `_process` for routine parameter changes; setting `cutoff_hz` and `set_bus_volume_db` is thread-safe.
- Generator pushes from `_process` run on the main thread: a long frame (scene load, shader compile) can underrun. The 300 ms buffer is the shield; when a hitch is expected (loading), `await` a frame before resuming and pre-fill.
- Web export: `AudioStreamGenerator` works but uses the main thread (no audio thread when threads are disabled). Keep generators at <= 22 050 Hz, reduce to two simultaneous generators (sea and rain), and fall back to baked loops for wind.
- Hot-reloading `default_bus_layout.tres` in the editor keeps old effect instances; restart play session after changing slot order, since scripts index effects by slot (`LPF_SLOT = 1`).

---

### Quick reference (cheat sheet)

```
Sea period      T0 = lerp(11, 6.5, storm)       jitter +/-18 %      set size 3-7
Wave envelope   e = (t/tp) * exp(1 - t/tp)       tp = 0.32 T
Sea cutoff      fc = lerp(220, 2600, E^1.4)      gain -26 + 14E dB
Rain            lambda = 30 + 900 r^1.3 /s       bed -38 + 16 r dB
Occlusion       o = 1 - (1-0.85d)(1-0.35w)       fc = fc_c * (fc_o/fc_c)^o
Vent            f = 0.2 v / d                    Q 12-38, cap 900 Hz
Attenuation     vol = (1 - d/max)^att
Ceilings        Sea -14, Weather -16, Mech -18 (bell -9), Foley -16, Music -16, Master limiter -2 dBFS
```

# AGENT 06: Time, Sky, Tide and Weather System

Godot 4.7.2, GDScript 2.0, static typing throughout. Everything below is intended to compile as written.

## 1. Design intent

The island keeps one clock. Sun, moon, tide and weather are all derived from a single float, `t_days` (days since the start of Thaw, day 0, 00:00 local solar time). Nothing is "scheduled"; the sky is a pure function of time. That gives the cozy properties we want:

- **No time pressure.** Time pauses (menus, dialogs, a held "Stay a while" key), slows (0.35x) or runs normally. Nothing fails because the clock moved.
- **Tangible.** The lamp wants lighting at sunset because the sun actually sets, later in summer and earlier in winter. The tidepools open because the moon is actually overhead. Spring tides arrive at new and full moon.
- **Deterministic.** One `world_seed` fixes the start date, moon phase offset, tidal port lag and the entire weather history. Same seed plus same elapsed time equals same sky, so saves are small and weather can be forecast diegetically (barometer, radio).
- **Headless-testable.** All maths lives in `RefCounted` classes with `static` functions. Only two nodes hold state: `TimeManager` (autoload) and its child `WeatherSystem`.

### 1.1 The single autoload (justification)

| Candidate | Autoload? | Why |
|---|---|---|
| `TimeManager` | **Yes** | The lighthouse interior, exterior, cellar, boat and map are separate scenes. The sun must not reset on `change_scene_to_packed()`. The node renders nothing, owns no UI and registers no services; it is a world clock. |
| `WeatherSystem` | No | Child node of `TimeManager`, reached as `TimeManager.weather`. It needs the clock's tick and nothing else. |
| `Astro`, `TideModel`, `WeatherModel`, `WorldMath` | No | `class_name` static libraries. Not nodes. |
| Event bus | **No** | Scenes connect straight to `TimeManager` signals. A generic bus would be the "enterprise" pattern we reject. |

### 1.2 File layout

```
res://world/world_math.gd        class_name WorldMath      hash + calendar
res://world/astro.gd             class_name Astro          sun / moon
res://world/tide_model.gd        class_name TideModel      tide
res://world/weather_model.gd     class_name WeatherModel   Markov tables + relaxation
res://world/weather_system.gd    class_name WeatherSystem  Node, stateful
res://world/world_snapshot.gd    class_name WorldSnapshot  read-only view for scenes
res://world/time_manager.gd      autoload "TimeManager"    (no class_name)
res://tests/world_tests.gd       headless runner
```

Project Settings, Autoload: `TimeManager` = `res://world/time_manager.gd`. Do not give it a `class_name` (it would clash with the autoload identifier).

## 2. Model

### 2.1 Calendar

- 4 seasons x 28 days = **112-day year**. Seasons: Thaw (spring), Brightwater (summer), Emberfall (autumn), Hushwinter (winter). Year starts at the vernal equinox.
- 7-day week, so every season is exactly 4 weeks. Moon synodic month is **stylised to 28 days**, so every season holds exactly one lunar cycle and the year holds exactly 4 (the moon pattern repeats annually, which makes a gorgeous, learnable rhythm: "Brightwater's full moon is always low and gold").
- Latitude default **58 N** (northern, long summer evenings, deep winter nights, aurora plausible).
- Seeded start: day `2 + floor(unit(seed,101) * 12)` of Thaw, at 06:30.

### 2.2 Sun (formulas)

Let `lambda_s = TAU * (t mod 112) / 112` be the ecliptic longitude, `eps = 23.44 deg` the obliquity, `phi` the latitude.

```
dec_s   = asin( sin(eps) * sin(lambda_s) )          # declination
ra_s    = atan2( cos(eps) * sin(lambda_s), cos(lambda_s) )
H_s     = (frac(t) - 0.5) * TAU                      # hour angle, 0 at solar noon, west positive
sin(el) = sin(phi) sin(dec) + cos(phi) cos(dec) cos(H)
az      = atan2( -cos(dec) sin(H),  sin(dec) cos(phi) - cos(dec) cos(H) sin(phi) )   # from North, clockwise
```

Sunrise/sunset (hours): `cos(H0) = (sin(-0.833 deg) - sin(phi) sin(dec)) / (cos(phi) cos(dec))`, rise `= 12 - H0*24/TAU`, set `= 12 + H0*24/TAU`. At 58 N the summer solstice gives about 18.2 h of daylight, the winter solstice about 6 h.

### 2.3 Moon (formulas)

Elongation (angle moon-sun along the ecliptic): `E = TAU * frac(t/28 + phase_offset)`, 0 is new, pi is full.

```
lambda_m = lambda_s + E
beta_m   = 5.14 deg * sin(TAU * t / 26)              # stylised nodal wobble (declination variety)
dec_m    = asin( sin(beta) cos(eps) + cos(beta) sin(eps) sin(lambda_m) )
ra_m     = atan2( sin(lambda_m) cos(beta) cos(eps) - sin(beta) sin(eps),  cos(lambda_m) cos(beta) )
H_m      = H_s + ra_s - ra_m                         # hour angle follows from sun's
illumination = (1 - cos E) / 2
age_days = E / TAU * 28
```
`H_m` falls out of the identity `LST = H_s + ra_s`. The moon rises about 51 minutes later each day (12.86 deg/day of elongation), matching reality. Full moon crosses the meridian at solar midnight and is high in winter, low in summer, for free.

### 2.4 Tide (formulas)

Three constituents driven by the astronomy above (heights in metres, port lag `L` seeded in 0.3..1.2 rad, about 1 to 4.5 hours):

```
M2 = 1.00 * cos( 2 (H_m - L) )                 # principal lunar semidiurnal (two highs per lunar day)
S2 = 0.46 * cos( 2 (H_s - L) )                 # solar semidiurnal; beats against M2
K1 = 0.25 * min(1, |sin(dec_m)|/0.4) * cos(H_m - L)   # diurnal inequality: unequal successive highs
h  = M2 + S2 + K1                              # in [-1.71, 1.71]
```
Spring tides occur at new/full moon (M2 and S2 in phase, about 1.46 m plus K1), neap at quarters (about 0.54 m). `level01 = (h + 1.71) / 3.42`. Storm surge adds `0.35 * gale_fraction` metres in the snapshot (not in the pure tide) so a gale visibly pushes the sea onto the rocks without breaking the schedule.

### 2.5 Weather as a Markov chain

- **Slots:** weather decides once per 2 game-hours (12 slots/day). Slot `n` transition uses an independent hash stream `unit(mix32(seed, STREAM), n)`; there is no stateful RNG, so the result is independent of frame rate, speed or save/load cadence.
- **States:** Fair, Sea Fog, Gentle Rain, Heavy Gale, Aurora Borealis.
- **Matrix:** a 5x5 row-stochastic matrix per season, multiplied column-wise by a time-of-day modifier (Night, Dawn, Day, Dusk; bucket from true sun elevation at slot midpoint), then row-renormalised. Fog is boosted at dawn, aurora is forbidden in daylight and rare at dusk, and it is zero all Brightwater (matrix column is 0), so summer evenings stay clear and bright.
- **Blending:** each state defines target parameters `(rain, fog, wind, cloud, aurora)`, scaled by a per-slot intensity in 0.75..1.25. Current values relax exponentially toward target with per-parameter time constants (fog is slow, wind is quick). `relax()` composes exactly: `relax(a) then relax(b) == relax(a+b)`, so fast-forward cannot change the outcome.
- **Forecast:** because the chain is pure, `forecast(n)` is exact. The UI deliberately reveals only 1 to 2 slots (barometer needle; a `gale_warning` signal one slot ahead) so the player gets a fair, cozy heads-up.

## 3. Code

### 3.1 `world_math.gd`

```gdscript
class_name WorldMath
extends RefCounted
## Pure helpers: stateless hashing and calendar maths. No engine state, safe headless.

const DAYS_PER_SEASON: int = 28
const DAYS_PER_YEAR: int = 112
const MINUTES_PER_DAY: float = 1440.0

enum Season { THAW, BRIGHT, EMBER, HUSH }

const SEASON_NAMES: PackedStringArray = ["Thaw", "Brightwater", "Emberfall", "Hushwinter"]
const WEEKDAY_NAMES: PackedStringArray = [
	"Moonday", "Tideday", "Windday", "Lampday", "Saltday", "Gullday", "Restday"
]


static func _avalanche(v: int) -> int:
	var x: int = v & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45D9F3B) & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45D9F3B) & 0xFFFFFFFF
	return (x >> 16) ^ x


## 32-bit integer mixer. Stable across engine versions (unlike hash(), whose output is not guaranteed).
static func mix32(a: int, b: int) -> int:
	var lane: int = (b & 0xFFFFFFFF) * 0x632BE5AB
	return _avalanche((_avalanche(a) + lane) & 0xFFFFFFFF)


## Deterministic float in [0, 1) for (stream, index).
static func unit(stream: int, index: int) -> float:
	return float(mix32(stream, index)) / 4294967296.0


static func season_of(day: int) -> Season:
	return floori(posmod(day, DAYS_PER_YEAR) / float(DAYS_PER_SEASON)) as Season


static func hour_of(t_days: float) -> float:
	return fposmod(t_days, 1.0) * 24.0


## Keys: year (1-based), season (Season), day (1-based in season), weekday (0..6), day_of_year (0..111).
static func date_from_days(t_days: float) -> Dictionary:
	var d: int = floori(t_days)
	var doy: int = posmod(d, DAYS_PER_YEAR)
	return {
		"year": floori(d / float(DAYS_PER_YEAR)) + 1,
		"season": season_of(d),
		"day": posmod(doy, DAYS_PER_SEASON) + 1,
		"weekday": posmod(d, 7),
		"day_of_year": doy,
	}


static func clock_string(t_days: float) -> String:
	var minutes: int = floori(fposmod(t_days, 1.0) * MINUTES_PER_DAY)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
```

(`minutes / 60` is integer division; add `@warning_ignore("integer_division")` above `clock_string` if your project promotes that warning to an error.)

### 3.2 `astro.gd`

```gdscript
class_name Astro
extends RefCounted
## Pure sun and moon geometry. All angles in radians. Azimuth is measured from North, clockwise.

enum TimeOfDay { NIGHT, DAWN, DAY, DUSK }

const YEAR_DAYS: float = 112.0
const SYNODIC_DAYS: float = 28.0
const NODE_DAYS: float = 26.0
const OBLIQUITY: float = 0.409093          # 23.44 degrees
const MOON_INCLINATION: float = 0.0897     # 5.14 degrees
const HORIZON_ALT: float = -0.014544       # -0.833 degrees (refraction + solar radius)
const CIVIL_TWILIGHT: float = -0.104720    # -6 degrees
const DAY_ALT: float = 0.104720            # +6 degrees

const PHASE_NAMES: PackedStringArray = [
	"New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
	"Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
]


class BodyState extends RefCounted:
	var azimuth: float = 0.0
	var elevation: float = 0.0
	var declination: float = 0.0
	var right_ascension: float = 0.0
	var hour_angle: float = 0.0
	var elongation: float = 0.0       # moon only: 0 = new, PI = full
	var illumination: float = 0.0     # moon only: 0..1


static func sun_longitude(t_days: float) -> float:
	return fposmod(t_days / YEAR_DAYS, 1.0) * TAU


## Solar hour angle: 0 at local solar noon, negative in the morning.
static func solar_hour_angle(t_days: float) -> float:
	return (fposmod(t_days, 1.0) - 0.5) * TAU


## Returns Vector2(right_ascension, declination).
static func ecliptic_to_equatorial(lon: float, lat: float) -> Vector2:
	var sin_dec: float = sin(lat) * cos(OBLIQUITY) + cos(lat) * sin(OBLIQUITY) * sin(lon)
	var y: float = sin(lon) * cos(lat) * cos(OBLIQUITY) - sin(lat) * sin(OBLIQUITY)
	var x: float = cos(lon) * cos(lat)
	return Vector2(atan2(y, x), asin(clampf(sin_dec, -1.0, 1.0)))


## Returns Vector2(azimuth from North clockwise in [0, TAU), elevation).
static func horizontal(latitude: float, dec: float, hour_angle: float) -> Vector2:
	var sin_el: float = sin(latitude) * sin(dec) + cos(latitude) * cos(dec) * cos(hour_angle)
	var az: float = atan2(
		-cos(dec) * sin(hour_angle),
		sin(dec) * cos(latitude) - cos(dec) * cos(hour_angle) * sin(latitude)
	)
	return Vector2(fposmod(az, TAU), asin(clampf(sin_el, -1.0, 1.0)))


static func sun_state(latitude: float, t_days: float) -> BodyState:
	var s: BodyState = BodyState.new()
	var eq: Vector2 = ecliptic_to_equatorial(sun_longitude(t_days), 0.0)
	s.right_ascension = eq.x
	s.declination = eq.y
	s.hour_angle = solar_hour_angle(t_days)
	var hz: Vector2 = horizontal(latitude, s.declination, s.hour_angle)
	s.azimuth = hz.x
	s.elevation = hz.y
	return s


static func moon_elongation(t_days: float, phase_offset: float) -> float:
	return fposmod(t_days / SYNODIC_DAYS + phase_offset, 1.0) * TAU


## Latitude-independent moon equatorial data. Returns Vector3(ra, dec, hour_angle in [-PI, PI]).
static func moon_equatorial(t_days: float, phase_offset: float) -> Vector3:
	var lon_s: float = sun_longitude(t_days)
	var lon_m: float = lon_s + moon_elongation(t_days, phase_offset)
	var beta: float = MOON_INCLINATION * sin(TAU * t_days / NODE_DAYS)
	var eq_m: Vector2 = ecliptic_to_equatorial(lon_m, beta)
	var eq_s: Vector2 = ecliptic_to_equatorial(lon_s, 0.0)
	var ha: float = solar_hour_angle(t_days) + eq_s.x - eq_m.x
	return Vector3(eq_m.x, eq_m.y, wrapf(ha, -PI, PI))


static func moon_state(latitude: float, t_days: float, phase_offset: float) -> BodyState:
	var m: BodyState = BodyState.new()
	var eq: Vector3 = moon_equatorial(t_days, phase_offset)
	m.right_ascension = eq.x
	m.declination = eq.y
	m.hour_angle = eq.z
	m.elongation = moon_elongation(t_days, phase_offset)
	m.illumination = (1.0 - cos(m.elongation)) * 0.5
	var hz: Vector2 = horizontal(latitude, m.declination, m.hour_angle)
	m.azimuth = hz.x
	m.elevation = hz.y
	return m


static func moon_phase_index(elongation: float) -> int:
	return mini(floori(fposmod(elongation / TAU + 0.0625, 1.0) * 8.0), 7)


static func moon_age_days(elongation: float) -> float:
	return elongation / TAU * SYNODIC_DAYS


## Returns Vector2(sunrise_hour, sunset_hour). Midnight sun: (0, 24). Polar night: (12, 12).
static func sunrise_sunset(latitude: float, dec: float) -> Vector2:
	var c: float = (sin(HORIZON_ALT) - sin(latitude) * sin(dec)) / (cos(latitude) * cos(dec))
	if c <= -1.0:
		return Vector2(0.0, 24.0)
	if c >= 1.0:
		return Vector2(12.0, 12.0)
	var half_day_hours: float = acos(c) / TAU * 24.0
	return Vector2(12.0 - half_day_hours, 12.0 + half_day_hours)


static func phase_of(elevation: float, hour_angle: float) -> TimeOfDay:
	if elevation >= DAY_ALT:
		return TimeOfDay.DAY
	if elevation <= CIVIL_TWILIGHT:
		return TimeOfDay.NIGHT
	return TimeOfDay.DAWN if hour_angle < 0.0 else TimeOfDay.DUSK


## 0 at deep twilight, 1 in full day. Smooth, for colour ramps and CanvasModulate.
static func daylight(elevation: float) -> float:
	return smoothstep(CIVIL_TWILIGHT, 0.2, elevation)


## Unit vector toward the sun in Godot 3D space (+X east, +Y up, -Z north).
static func direction_vector(azimuth: float, elevation: float) -> Vector3:
	return Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))


## Top-down/3-4 view shadow direction on screen (+X east, +Y south), unit length.
static func shadow_direction_2d(azimuth: float) -> Vector2:
	return Vector2(-sin(azimuth), cos(azimuth))


## Shadow length in units of object height. Clamped so dawn shadows do not span the island.
static func shadow_length_ratio(elevation: float) -> float:
	return clampf(1.0 / tan(maxf(elevation, 0.05)), 0.0, 6.0)
```

### 3.3 `tide_model.gd`

```gdscript
class_name TideModel
extends RefCounted
## Pure tide model derived from the lunar and solar hour angles. Heights in metres.

const M2_AMP: float = 1.00
const S2_AMP: float = 0.46
const K1_AMP: float = 0.25
const MAX_HEIGHT: float = 1.71
const SURGE_PER_GALE: float = 0.35
const TREND_EPS: float = 1e-9


static func height_from_angles(moon_ha: float, sun_ha: float, moon_dec: float, port_lag: float) -> float:
	var k1_scale: float = clampf(absf(sin(moon_dec)) / 0.4, 0.0, 1.0)
	return (
		M2_AMP * cos(2.0 * (moon_ha - port_lag))
		+ S2_AMP * cos(2.0 * (sun_ha - port_lag))
		+ K1_AMP * k1_scale * cos(moon_ha - port_lag)
	)


static func height_at(t_days: float, moon_offset: float, port_lag: float) -> float:
	var m: Vector3 = Astro.moon_equatorial(t_days, moon_offset)
	return height_from_angles(m.z, Astro.solar_hour_angle(t_days), m.y, port_lag)


static func level01(height: float) -> float:
	return clampf((height + MAX_HEIGHT) / (2.0 * MAX_HEIGHT), 0.0, 1.0)


## Central difference over +/- 1 game minute. Positive means rising.
static func trend(t_days: float, moon_offset: float, port_lag: float) -> float:
	var dt: float = 1.0 / WorldMath.MINUTES_PER_DAY
	return height_at(t_days + dt, moon_offset, port_lag) - height_at(t_days - dt, moon_offset, port_lag)


## 1 at new/full moon (spring tides), 0 at the quarters (neap).
static func spring_factor(elongation: float) -> float:
	return absf(cos(elongation))


## Next turning point within 14 hours. Returns Vector2(time_days, height); (-1, 0) if none found.
static func next_extreme(t_days: float, moon_offset: float, port_lag: float) -> Vector2:
	var step: float = 6.0 / WorldMath.MINUTES_PER_DAY
	var prev: float = trend(t_days, moon_offset, port_lag)
	for i: int in range(1, 141):
		var ti: float = t_days + step * float(i)
		var cur: float = trend(ti, moon_offset, port_lag)
		if prev * cur < 0.0:
			var lo: float = ti - step
			var hi: float = ti
			for _k: int in 12:   # bisection on the sign change
				var mid: float = (lo + hi) * 0.5
				if trend(mid, moon_offset, port_lag) * prev > 0.0:
					lo = mid
				else:
					hi = mid
			return Vector2(hi, height_at(hi, moon_offset, port_lag))
		prev = cur
	return Vector2(-1.0, 0.0)
```

### 3.4 `weather_model.gd`

```gdscript
class_name WeatherModel
extends RefCounted
## Pure weather maths: transition tables, deterministic picks, parameter relaxation.

enum State { FAIR, SEA_FOG, GENTLE_RAIN, HEAVY_GALE, AURORA }

const STATE_COUNT: int = 5
const SLOTS_PER_DAY: int = 12                     # one decision per 2 game hours
const P_RAIN: int = 0
const P_FOG: int = 1
const P_WIND: int = 2
const P_CLOUD: int = 3
const P_AURORA: int = 4
const PARAM_COUNT: int = 5

const STREAM_STATE: int = 0x57A7E
const STREAM_INTENSITY: int = 0x1A7E
const STREAM_WIND: int = 0x71D0

const STATE_NAMES: PackedStringArray = ["Fair", "Sea Fog", "Gentle Rain", "Heavy Gale", "Aurora"]

## Per-state targets, row = State, columns = rain, fog, wind, cloud, aurora.
const TARGETS: PackedFloat32Array = [
	0.00, 0.00, 0.18, 0.15, 0.00,   # FAIR
	0.00, 0.85, 0.06, 0.55, 0.00,   # SEA_FOG
	0.45, 0.20, 0.30, 0.80, 0.00,   # GENTLE_RAIN
	0.80, 0.05, 0.95, 0.95, 0.00,   # HEAVY_GALE
	0.00, 0.00, 0.08, 0.05, 1.00,   # AURORA
]

## Relaxation time constants in game minutes: rain, fog, wind, cloud, aurora.
const TAU_MINUTES: PackedFloat32Array = [40.0, 90.0, 30.0, 60.0, 45.0]

## Row = from, column = to (FAIR, FOG, RAIN, GALE, AURORA). Rows are renormalised in code.
const M_THAW: PackedFloat32Array = [
	0.56, 0.16, 0.20, 0.04, 0.04,
	0.30, 0.50, 0.16, 0.03, 0.01,
	0.26, 0.14, 0.46, 0.12, 0.02,
	0.18, 0.04, 0.38, 0.40, 0.00,
	0.50, 0.06, 0.06, 0.00, 0.38,
]
const M_BRIGHT: PackedFloat32Array = [
	0.72, 0.14, 0.11, 0.03, 0.00,
	0.42, 0.44, 0.12, 0.02, 0.00,
	0.34, 0.12, 0.44, 0.10, 0.00,
	0.26, 0.02, 0.42, 0.30, 0.00,
	0.90, 0.05, 0.05, 0.00, 0.00,
]
const M_EMBER: PackedFloat32Array = [
	0.46, 0.14, 0.22, 0.10, 0.08,
	0.26, 0.42, 0.20, 0.08, 0.04,
	0.20, 0.10, 0.46, 0.20, 0.04,
	0.12, 0.03, 0.35, 0.50, 0.00,
	0.45, 0.05, 0.08, 0.02, 0.40,
]
const M_HUSH: PackedFloat32Array = [
	0.50, 0.10, 0.12, 0.12, 0.16,
	0.32, 0.40, 0.14, 0.10, 0.04,
	0.22, 0.06, 0.44, 0.22, 0.06,
	0.16, 0.02, 0.30, 0.52, 0.00,
	0.40, 0.03, 0.05, 0.02, 0.50,
]
const MATRICES: Array = [M_THAW, M_BRIGHT, M_EMBER, M_HUSH]   # index = WorldMath.Season

## Time-of-day column multipliers (index = Astro.TimeOfDay): FAIR, FOG, RAIN, GALE, AURORA.
const MOD_NIGHT: PackedFloat32Array = [1.00, 0.90, 1.00, 1.00, 1.00]
const MOD_DAWN: PackedFloat32Array = [1.00, 1.80, 0.90, 0.80, 0.00]
const MOD_DAY: PackedFloat32Array = [1.10, 0.50, 1.00, 1.00, 0.00]
const MOD_DUSK: PackedFloat32Array = [1.00, 1.20, 1.00, 1.10, 0.30]
const TIME_MODS: Array = [MOD_NIGHT, MOD_DAWN, MOD_DAY, MOD_DUSK]


static func slot_of(t_days: float) -> int:
	return floori(t_days * float(SLOTS_PER_DAY))


static func season_for_slot(slot: int) -> int:
	return WorldMath.season_of(floori(float(slot) / float(SLOTS_PER_DAY)))


## Sun-driven time-of-day bucket sampled at the slot midpoint.
static func bucket_for_slot(slot: int, latitude_rad: float) -> int:
	var t: float = (float(slot) + 0.5) / float(SLOTS_PER_DAY)
	var sun: Astro.BodyState = Astro.sun_state(latitude_rad, t)
	return Astro.phase_of(sun.elevation, sun.hour_angle)


## Normalised outgoing probabilities from `prev` for the given season and bucket.
static func transition_weights(prev: State, season: int, bucket: int) -> PackedFloat32Array:
	var m: PackedFloat32Array = MATRICES[season]
	var mod: PackedFloat32Array = TIME_MODS[bucket]
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(STATE_COUNT)
	var total: float = 0.0
	for j: int in STATE_COUNT:
		var w: float = m[int(prev) * STATE_COUNT + j] * mod[j]
		out[j] = w
		total += w
	if total <= 0.0:
		out.fill(0.0)
		out[int(prev)] = 1.0
		return out
	for j: int in STATE_COUNT:
		out[j] /= total
	return out


static func pick(weights: PackedFloat32Array, u: float) -> State:
	var acc: float = 0.0
	for j: int in STATE_COUNT:
		acc += weights[j]
		if u < acc:
			return j as State
	return (STATE_COUNT - 1) as State


## One Markov step for a given random draw (pure, table driven; handy for stationary-distribution tests).
static func step(prev: State, season: int, bucket: int, u: float) -> State:
	return pick(transition_weights(prev, season, bucket), u)


## State entered at `slot` (the transition draw is keyed by the slot index, nothing else).
static func next_state(world_seed: int, slot: int, prev: State, latitude_rad: float) -> State:
	var u: float = WorldMath.unit(WorldMath.mix32(world_seed, STREAM_STATE), slot)
	return step(prev, season_for_slot(slot), bucket_for_slot(slot, latitude_rad), u)


## Replays the chain from slot 0 (always FAIR). O(slot); a decade is about 13k trivial steps.
static func state_at_slot(world_seed: int, slot: int, latitude_rad: float) -> State:
	var s: State = State.FAIR
	for i: int in range(1, slot + 1):
		s = next_state(world_seed, i, s, latitude_rad)
	return s


static func intensity(world_seed: int, slot: int) -> float:
	return 0.75 + 0.5 * WorldMath.unit(WorldMath.mix32(world_seed, STREAM_INTENSITY), slot)


## Direction the wind blows FROM (radians, compass). Prevailing westerly with seeded drift.
static func wind_from(world_seed: int, slot: int, state: State) -> float:
	var u: float = WorldMath.unit(WorldMath.mix32(world_seed, STREAM_WIND), slot)
	var spread: float = 0.5 if state == State.HEAVY_GALE else 1.2
	return wrapf(1.5 * PI + (u - 0.5) * 2.0 * spread, 0.0, TAU)


static func target_params(state: State, intensity_scale: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(PARAM_COUNT)
	for p: int in PARAM_COUNT:
		var v: float = TARGETS[int(state) * PARAM_COUNT + p]
		if p != P_AURORA and p != P_CLOUD:
			v *= intensity_scale
		out[p] = clampf(v, 0.0, 1.0)
	return out


## Exponential approach. Composable: relax(dt1) then relax(dt2) equals relax(dt1 + dt2).
static func relax(current: PackedFloat32Array, target: PackedFloat32Array, dt_minutes: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(PARAM_COUNT)
	for i: int in PARAM_COUNT:
		var a: float = 1.0 - exp(-dt_minutes / TAU_MINUTES[i])
		out[i] = current[i] + (target[i] - current[i]) * a
	return out
```

### 3.5 `weather_system.gd`

```gdscript
class_name WeatherSystem
extends Node
## Stateful wrapper around WeatherModel. Child of TimeManager; ticked by it in game time only.

signal state_changed(old_state: WeatherModel.State, new_state: WeatherModel.State)
signal gale_warning()    ## the NEXT slot is a Heavy Gale and this one is not

const WIND_DIR_TAU_MINUTES: float = 45.0
const SAVE_VERSION: int = 1

var world_seed: int = 0
var slot: int = 0
var state: WeatherModel.State = WeatherModel.State.FAIR

var rain_intensity: float:
	get: return _params[WeatherModel.P_RAIN]
var fog_density: float:
	get: return _params[WeatherModel.P_FOG]
var wind: float:
	get: return _params[WeatherModel.P_WIND]
var cloud_cover: float:
	get: return _params[WeatherModel.P_CLOUD]
var aurora_strength: float:
	get: return _params[WeatherModel.P_AURORA]
var wind_from: float:
	get: return _wind_from

var _lat_rad: float = 1.012291
var _params: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _target: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _wind_from: float = 4.712389
var _wind_from_target: float = 4.712389


## Replays the seeded chain to `t_days` and snaps parameters (new game / debug time jump).
func setup(seed_value: int, latitude_rad: float, t_days: float) -> void:
	world_seed = seed_value
	_lat_rad = latitude_rad
	slot = WeatherModel.slot_of(t_days)
	state = WeatherModel.state_at_slot(world_seed, slot, _lat_rad)
	_refresh_targets()
	_params = _target.duplicate()
	_wind_from = _wind_from_target


## Called by TimeManager every simulation tick (<= 5 game minutes). Never called with real delta.
func advance(dt_minutes: float, t_days: float) -> void:
	var target_slot: int = WeatherModel.slot_of(t_days)
	while slot < target_slot:
		_enter_slot(slot + 1)
	_params = WeatherModel.relax(_params, _target, dt_minutes)
	_wind_from = lerp_angle(_wind_from, _wind_from_target, 1.0 - exp(-dt_minutes / WIND_DIR_TAU_MINUTES))


## Exact future states (the chain is pure). UI should only reveal the first 1 or 2.
func forecast(slots_ahead: int) -> Array[WeatherModel.State]:
	var out: Array[WeatherModel.State] = []
	var s: WeatherModel.State = state
	for i: int in range(1, slots_ahead + 1):
		s = WeatherModel.next_state(world_seed, slot + i, s, _lat_rad)
		out.append(s)
	return out


func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": world_seed,
		"slot": slot,
		"state": int(state),
		"params": Array(_params),
		"wind_from": _wind_from,
	}


func deserialize(d: Dictionary, latitude_rad: float) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false
	_lat_rad = latitude_rad
	world_seed = int(d.get("seed", 0))
	slot = int(d.get("slot", 0))
	state = int(d.get("state", 0)) as WeatherModel.State
	_refresh_targets()
	var saved: Array = d.get("params", [])
	if saved.size() == WeatherModel.PARAM_COUNT:
		for i: int in WeatherModel.PARAM_COUNT:
			_params[i] = float(saved[i])
	else:
		_params = _target.duplicate()
	_wind_from = float(d.get("wind_from", _wind_from_target))
	return true


func _enter_slot(new_slot: int) -> void:
	var old: WeatherModel.State = state
	slot = new_slot
	state = WeatherModel.next_state(world_seed, slot, old, _lat_rad)
	_refresh_targets()
	if state != old:
		state_changed.emit(old, state)
	var upcoming: WeatherModel.State = WeatherModel.next_state(world_seed, slot + 1, state, _lat_rad)
	if upcoming == WeatherModel.State.HEAVY_GALE and state != WeatherModel.State.HEAVY_GALE:
		gale_warning.emit()


func _refresh_targets() -> void:
	_target = WeatherModel.target_params(state, WeatherModel.intensity(world_seed, slot))
	_wind_from_target = WeatherModel.wind_from(world_seed, slot, state)
```

### 3.6 `world_snapshot.gd`

```gdscript
class_name WorldSnapshot
extends RefCounted
## One reused, read-only-by-convention view of the world. Listeners MUST copy values they keep.

var t_days: float = 0.0
var hour: float = 0.0
var date: Dictionary = {}
var phase: Astro.TimeOfDay = Astro.TimeOfDay.DAY

var sun_azimuth: float = 0.0
var sun_elevation: float = 0.0
var sun_dir: Vector3 = Vector3.UP
var sun_shadow_dir: Vector2 = Vector2.DOWN
var sun_shadow_len: float = 1.0
var daylight: float = 1.0

var moon_azimuth: float = 0.0
var moon_elevation: float = 0.0
var moon_illumination: float = 0.0
var moon_age_days: float = 0.0
var moon_phase_index: int = 0
var spring_factor: float = 0.0

var tide_height: float = 0.0       # metres, includes storm surge
var tide_level01: float = 0.5
var tide_rising: bool = true

var weather_state: WeatherModel.State = WeatherModel.State.FAIR
var rain_intensity: float = 0.0
var fog_density: float = 0.0
var wind: float = 0.0
var wind_from: float = 0.0
var cloud_cover: float = 0.0
var aurora: float = 0.0

var ambient_light: float = 1.0     # 0..1 combined sun + moon + aurora, weather attenuated
```

### 3.7 `time_manager.gd` (autoload `TimeManager`)

```gdscript
extends Node
## Autoload "TimeManager": the island's world clock. Renders nothing, owns no UI.
## Owns t_days, derives sun/moon/tide, ticks the child WeatherSystem, and broadcasts.

# ---- Continuous (throttled to AMBIENT_HZ, only while time runs) ----
signal ambient_updated(snapshot: WorldSnapshot)

# ---- Discrete events (emitted exactly once per occurrence, in game-time order) ----
signal hour_changed(hour: int)
signal day_started(date: Dictionary)
signal season_changed(season: WorldMath.Season)
signal time_of_day_changed(phase: Astro.TimeOfDay)
signal sunrise()
signal sunset()
signal moon_phase_changed(phase_index: int, phase_name: String)
signal tide_turned(is_high: bool, height: float)
signal low_tide_window_changed(is_open: bool)
signal weather_changed(old_state: WeatherModel.State, new_state: WeatherModel.State)
signal gale_warning()

# ---- Control ----
signal speed_changed(speed: Speed, scale: float)
signal paused_changed(is_paused: bool)

enum Speed { PAUSED, SLOW, NORMAL, FAST }

const SPEED_SCALES: PackedFloat32Array = [0.0, 0.35, 1.0, 3.0]
const DAY_REAL_SECONDS: float = 1200.0      # one game day = 20 real minutes at NORMAL
const TICK_MINUTES: float = 5.0             # simulation granularity
const TICK_DAYS: float = TICK_MINUTES / 1440.0
const AMBIENT_HZ: float = 15.0
const MAX_FRAME_DELTA: float = 0.25         # alt-tab stalls must not skip half a day
const START_HOUR: float = 6.5
const LOW_TIDE_OPEN: float = 0.22
const LOW_TIDE_CLOSE: float = 0.30
const SAVE_VERSION: int = 1

@export var latitude_deg: float = 58.0

var world_seed: int = 0
var t_days: float = 0.0
var speed: Speed = Speed.NORMAL
var weather: WeatherSystem
var snapshot: WorldSnapshot = WorldSnapshot.new()

var _lat_rad: float = 0.0
var _moon_offset: float = 0.0
var _port_lag: float = 0.5
var _pause_reasons: Dictionary = {}          # StringName -> true
var _ambient_accum: float = 0.0
var _was_paused: bool = false

var _p_day: int = 0
var _p_hour: int = 0
var _p_season: int = 0
var _p_phase: int = 0
var _p_sun_up: bool = false
var _p_moon: int = 0
var _p_trend: int = 0
var _p_low_open: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # a paused SceneTree also stops the clock
	weather = WeatherSystem.new()
	weather.name = "Weather"
	add_child(weather)
	weather.state_changed.connect(_on_weather_state_changed)
	weather.gale_warning.connect(_on_weather_gale_warning)
	new_game(1)


func _process(delta: float) -> void:
	var paused: bool = is_paused()
	if paused != _was_paused:
		_was_paused = paused
		paused_changed.emit(paused)
	if paused:
		return
	var d: float = minf(delta, MAX_FRAME_DELTA)
	_advance_days(d * SPEED_SCALES[speed] / DAY_REAL_SECONDS)
	_ambient_accum += d
	if _ambient_accum >= 1.0 / AMBIENT_HZ:
		_ambient_accum = 0.0
		_publish_ambient()


# ---------------------------------------------------------------- public API

func new_game(seed_value: int) -> void:
	world_seed = seed_value
	_lat_rad = deg_to_rad(latitude_deg)
	_derive_constants()
	var start_day: int = 2 + floori(WorldMath.unit(world_seed, 101) * 12.0)
	t_days = float(start_day) + START_HOUR / 24.0
	weather.setup(world_seed, _lat_rad, t_days)
	_prime_events()
	_publish_ambient()


func is_paused() -> bool:
	return speed == Speed.PAUSED or not _pause_reasons.is_empty()


## Re-entrant pause for dialogs, journal, photo mode. Each reason pops independently.
func push_pause(reason: StringName) -> void:
	_pause_reasons[reason] = true


func pop_pause(reason: StringName) -> void:
	_pause_reasons.erase(reason)


func set_speed(new_speed: Speed) -> void:
	if new_speed == speed:
		return
	speed = new_speed
	speed_changed.emit(speed, SPEED_SCALES[speed])


## Sleeping or "wait until": jumps to the next occurrence of `hour`, firing every event on the way.
func skip_to_hour(hour: float) -> void:
	var delta_days: float = fposmod(hour / 24.0 - fposmod(t_days, 1.0), 1.0)
	if delta_days < 0.01:
		delta_days += 1.0
	_advance_days(delta_days)
	_publish_ambient()


func skip_hours(hours: float) -> void:
	_advance_days(hours / 24.0)
	_publish_ambient()


## Debug / tests / cutscenes: absolute jump without firing events.
func set_time(day: int, hour: float) -> void:
	t_days = float(day) + hour / 24.0
	weather.setup(world_seed, _lat_rad, t_days)
	_prime_events()
	_publish_ambient()


func hour_of_day() -> float:
	return WorldMath.hour_of(t_days)


func clock_string() -> String:
	return WorldMath.clock_string(t_days)


func next_tide_extreme() -> Vector2:
	return TideModel.next_extreme(t_days, _moon_offset, _port_lag)


# ---------------------------------------------------------------- save / load

func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"seed": world_seed,
		"t_days": t_days,
		"speed": int(speed),
		"latitude_deg": latitude_deg,
		"weather": weather.serialize(),
	}


func deserialize(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false
	world_seed = int(d.get("seed", 1))
	latitude_deg = float(d.get("latitude_deg", 58.0))
	_lat_rad = deg_to_rad(latitude_deg)
	_derive_constants()
	t_days = float(d.get("t_days", 2.27))
	speed = int(d.get("speed", Speed.NORMAL)) as Speed
	var wd: Variant = d.get("weather")
	if wd is Dictionary and weather.deserialize(wd as Dictionary, _lat_rad):
		pass
	else:
		weather.setup(world_seed, _lat_rad, t_days)   # fall back to the seeded replay
	_prime_events()
	_publish_ambient()
	return true


# ---------------------------------------------------------------- simulation

func _derive_constants() -> void:
	_moon_offset = WorldMath.unit(world_seed, 102)
	_port_lag = 0.3 + WorldMath.unit(world_seed, 103) * 0.9


func _advance_days(days: float) -> void:
	var remaining: float = days
	while remaining > 0.0:
		var step: float = minf(remaining, TICK_DAYS)
		t_days += step
		weather.advance(step * WorldMath.MINUTES_PER_DAY, t_days)
		remaining -= step
		_detect_events()


func _prime_events() -> void:
	_p_day = floori(t_days)
	_p_hour = floori(WorldMath.hour_of(t_days))
	_p_season = int(WorldMath.season_of(_p_day))
	var sun: Astro.BodyState = Astro.sun_state(_lat_rad, t_days)
	_p_sun_up = sun.elevation > Astro.HORIZON_ALT
	_p_phase = int(Astro.phase_of(sun.elevation, sun.hour_angle))
	_p_moon = Astro.moon_phase_index(Astro.moon_elongation(t_days, _moon_offset))
	var tr: float = TideModel.trend(t_days, _moon_offset, _port_lag)
	_p_trend = 0 if absf(tr) < TideModel.TREND_EPS else (1 if tr > 0.0 else -1)
	var level: float = TideModel.level01(TideModel.height_at(t_days, _moon_offset, _port_lag))
	_p_low_open = level < LOW_TIDE_OPEN


func _detect_events() -> void:
	var day: int = floori(t_days)
	if day != _p_day:
		_p_day = day
		var date: Dictionary = WorldMath.date_from_days(t_days)
		var season: int = int(date["season"])
		if season != _p_season:
			_p_season = season
			season_changed.emit(season as WorldMath.Season)
		day_started.emit(date)
	var hour: int = floori(WorldMath.hour_of(t_days))
	if hour != _p_hour:
		_p_hour = hour
		hour_changed.emit(hour)

	var sun: Astro.BodyState = Astro.sun_state(_lat_rad, t_days)
	var up: bool = sun.elevation > Astro.HORIZON_ALT
	if up != _p_sun_up:
		_p_sun_up = up
		if up:
			sunrise.emit()
		else:
			sunset.emit()
	var phase: int = int(Astro.phase_of(sun.elevation, sun.hour_angle))
	if phase != _p_phase:
		_p_phase = phase
		time_of_day_changed.emit(phase as Astro.TimeOfDay)

	var moon_idx: int = Astro.moon_phase_index(Astro.moon_elongation(t_days, _moon_offset))
	if moon_idx != _p_moon:
		_p_moon = moon_idx
		moon_phase_changed.emit(moon_idx, Astro.PHASE_NAMES[moon_idx])

	var tr: float = TideModel.trend(t_days, _moon_offset, _port_lag)
	if absf(tr) >= TideModel.TREND_EPS:
		var sgn: int = 1 if tr > 0.0 else -1
		if _p_trend != 0 and sgn != _p_trend:
			tide_turned.emit(_p_trend > 0, TideModel.height_at(t_days, _moon_offset, _port_lag))
		_p_trend = sgn
	var level: float = TideModel.level01(TideModel.height_at(t_days, _moon_offset, _port_lag))
	if not _p_low_open and level < LOW_TIDE_OPEN:
		_p_low_open = true
		low_tide_window_changed.emit(true)
	elif _p_low_open and level > LOW_TIDE_CLOSE:
		_p_low_open = false
		low_tide_window_changed.emit(false)


func _publish_ambient() -> void:
	refresh_snapshot()
	ambient_updated.emit(snapshot)


## Rebuilds the shared snapshot in place (no allocation of the snapshot itself).
func refresh_snapshot() -> void:
	var s: WorldSnapshot = snapshot
	var sun: Astro.BodyState = Astro.sun_state(_lat_rad, t_days)
	var moon: Astro.BodyState = Astro.moon_state(_lat_rad, t_days, _moon_offset)
	s.t_days = t_days
	s.hour = WorldMath.hour_of(t_days)
	s.date = WorldMath.date_from_days(t_days)
	s.phase = Astro.phase_of(sun.elevation, sun.hour_angle)
	s.sun_azimuth = sun.azimuth
	s.sun_elevation = sun.elevation
	s.sun_dir = Astro.direction_vector(sun.azimuth, sun.elevation)
	s.sun_shadow_dir = Astro.shadow_direction_2d(sun.azimuth)
	s.sun_shadow_len = Astro.shadow_length_ratio(sun.elevation)
	s.daylight = Astro.daylight(sun.elevation)
	s.moon_azimuth = moon.azimuth
	s.moon_elevation = moon.elevation
	s.moon_illumination = moon.illumination
	s.moon_age_days = Astro.moon_age_days(moon.elongation)
	s.moon_phase_index = Astro.moon_phase_index(moon.elongation)
	s.spring_factor = TideModel.spring_factor(moon.elongation)

	var gale_fraction: float = clampf(weather.wind, 0.0, 1.0)
	gale_fraction = smoothstep(0.6, 1.0, gale_fraction)
	var h: float = TideModel.height_at(t_days, _moon_offset, _port_lag)
	h += TideModel.SURGE_PER_GALE * gale_fraction
	s.tide_height = h
	s.tide_level01 = TideModel.level01(h)
	s.tide_rising = TideModel.trend(t_days, _moon_offset, _port_lag) > 0.0

	s.weather_state = weather.state
	s.rain_intensity = weather.rain_intensity
	s.fog_density = weather.fog_density
	s.wind = weather.wind
	s.wind_from = weather.wind_from
	s.cloud_cover = weather.cloud_cover
	s.aurora = weather.aurora_strength

	var sun_light: float = s.daylight * (1.0 - 0.55 * s.cloud_cover - 0.15 * s.fog_density)
	var moon_up: float = smoothstep(-0.05, 0.2, moon.elevation)
	var moon_light: float = s.moon_illumination * moon_up * 0.18 * (1.0 - 0.6 * s.cloud_cover)
	s.ambient_light = clampf(sun_light + moon_light + s.aurora * 0.05 + 0.04, 0.0, 1.0)


func _on_weather_state_changed(old_state: WeatherModel.State, new_state: WeatherModel.State) -> void:
	weather_changed.emit(old_state, new_state)


func _on_weather_gale_warning() -> void:
	gale_warning.emit()
```

## 4. Signal architecture

### 4.1 Two channels

| Channel | Signals | Rate | Purpose |
|---|---|---|---|
| **Continuous** | `ambient_updated(snapshot)` | 15 Hz while time runs; once on any jump, load, new game | Colour grading, light angle, shadows, water level, particle intensity, ambient mix. |
| **Discrete** | `hour_changed`, `day_started`, `season_changed`, `time_of_day_changed`, `sunrise`, `sunset`, `moon_phase_changed`, `tide_turned`, `low_tide_window_changed`, `weather_changed`, `gale_warning` | Exactly once per occurrence | Gameplay and one-shot presentation: lamp prompts, NPC schedules, tidepool tiles, bell chimes, journal entries. |
| Control | `speed_changed`, `paused_changed` | On change | HUD clock icon, muffling audio when paused. |

Rule of thumb: *visuals follow the continuous value; gameplay follows the event.* Do not derive a gameplay trigger by thresholding `ambient_updated` (the 15 Hz throttle makes that jittery and it will double-fire on load).

Events fire inside the simulation tick, so during `skip_to_hour()` (sleep) a night's `sunset`, `tide_turned` and `weather_changed` all fire in order, synchronously, before the function returns. Listeners must tolerate a burst.

### 4.2 Who listens

| Listener | Signals | Does |
|---|---|---|
| `LightingRig` (CanvasModulate + DirectionalLight2D, one per play scene) | `ambient_updated` | Samples a `Gradient` by `daylight` and `phase`; rotates light by `sun_shadow_dir`; stretches shadows by `sun_shadow_len`; adds cool moon tint; pushes shader globals. |
| `SkyLayer` (stars, sun, moon sprites, aurora shader) | `ambient_updated` | Places sun and moon by azimuth/elevation; moon sprite frame from `moon_phase_index`; aurora alpha from `aurora`; clouds from `cloud_cover`. |
| `SeaLayer` / shoreline tiles | `ambient_updated`, `low_tide_window_changed` | Water mask height from `tide_level01`; reveal tidepool interactables when the window opens. |
| `WeatherFX` (rain particles, fog sprite, wind sway shader) | `ambient_updated` | `GPUParticles2D.amount_ratio = rain_intensity`; fog alpha; `wind` and `wind_from` drive foliage and flag shaders. |
| `LighthouseLamp` | `sunset`, `sunrise`, `time_of_day_changed` | Shows "light the lamp" prompt on `sunset`; extinguish nudge on `sunrise`. The lamp stays valid at any time; nothing fails if you are late. |
| `AudioDirector` | `ambient_updated`, `weather_changed`, `time_of_day_changed`, `paused_changed` | Crossfades wave, wind, rain beds; owl and crickets at night; low-pass when paused. |
| `NPCScheduler` | `hour_changed`, `day_started`, `weather_changed` | Visitors, the supply boat, who sits by the stove in a storm. |
| `Journal / Logbook UI` | `day_started`, `moon_phase_changed`, `tide_turned`, `weather_changed` | Auto-writes entries; shows tide table via `TimeManager.next_tide_extreme()`; barometer via `weather.forecast(1)`. |
| `Barometer prop` | `gale_warning` | Needle drops one slot early; diegetic warning. |
| `SaveService` (whatever persists game state) | none (calls `serialize()` / `deserialize()`) | Pulls state at save time; no signals needed. |
| `Hud clock` | `speed_changed`, `paused_changed`, `hour_changed` | Icons and `clock_string()` once per game hour, or `ambient_updated` for the minute hand. |

### 4.3 Connection conventions

1. **Connect in `_ready()`, directly to the autoload.** `TimeManager.sunset.connect(_on_sunset)`. No intermediary bus. Godot disconnects automatically when the listener is freed.
2. **Handler name is `_on_<signal>`** when the autoload is the only source in that script (`_on_ambient_updated`, `_on_sunset`), otherwise `_on_time_manager_<signal>`.
3. **Prime on entry.** A scene that loads mid-game (the cellar, after climbing down) calls its handler once manually: `_on_ambient_updated(TimeManager.snapshot)`. Discrete state is read from the snapshot (`snapshot.phase`, `snapshot.weather_state`) rather than waiting for the next event.
4. **The snapshot is shared and mutated.** Never store the object; copy the floats you need. Never write to it.
5. **Listeners never emit back into the clock** and never call `set_speed()` from a handler without a deferred call (`set_speed.call_deferred(...)`), to avoid re-entrancy inside the tick loop.
6. **Typed payloads only.** Enum payloads (`Astro.TimeOfDay`, `WeatherModel.State`) keep `match` statements exhaustive and warn on refactors.
7. **One-shot prompts** use `CONNECT_ONE_SHOT` (e.g. a tutorial "wait for sunset").
8. **Pausing:** UI that wants the world to hold still calls `TimeManager.push_pause(&"journal")` on open and `pop_pause(&"journal")` on close. Never toggles `speed`. A `get_tree().paused` pause also halts the clock automatically (`PROCESS_MODE_PAUSABLE`). Weather particles can use `PROCESS_MODE_ALWAYS` if you want rain to keep falling visually on the pause screen.
9. **Shader globals** are written by `LightingRig`, not by the clock (the clock stays free of rendering). Suggested names: `global uniform vec3 sun_dir`, `float daylight`, `float wind`, `float rain`, `float fog`.

### 4.4 Example listener

```gdscript
class_name LightingRig
extends Node2D
## One per play scene. Colours the world from the clock; never drives the clock.

@export var day_ramp: Gradient            ## x: 0 = deep night, 1 = full day
@export var storm_tint: Color = Color(0.62, 0.68, 0.78)
@export var modulate_node: CanvasModulate
@export var sun_light: DirectionalLight2D

func _ready() -> void:
	TimeManager.ambient_updated.connect(_on_ambient_updated)
	TimeManager.time_of_day_changed.connect(_on_time_of_day_changed)
	_on_ambient_updated(TimeManager.snapshot)       # prime (convention 3)


func _on_ambient_updated(s: WorldSnapshot) -> void:
	var base: Color = day_ramp.sample(s.daylight)
	var gloom: float = clampf(s.cloud_cover * 0.5 + s.rain_intensity * 0.3, 0.0, 0.8)
	modulate_node.color = base.lerp(storm_tint * base, gloom)
	sun_light.rotation = s.sun_shadow_dir.angle()
	sun_light.energy = s.daylight * (1.0 - s.cloud_cover * 0.6)
	RenderingServer.global_shader_parameter_set(&"sun_dir", s.sun_dir)
	RenderingServer.global_shader_parameter_set(&"wind", s.wind)


func _on_time_of_day_changed(phase: Astro.TimeOfDay) -> void:
	match phase:
		Astro.TimeOfDay.DAWN, Astro.TimeOfDay.DUSK:
			pass   # e.g. trigger a one-shot window-glow tween
		Astro.TimeOfDay.DAY, Astro.TimeOfDay.NIGHT:
			pass
```

## 5. Save and load

- `TimeManager.serialize()` returns a plain `Dictionary` of primitives: `version`, `seed`, `t_days`, `speed`, `latitude_deg`, and the nested `weather` block (`slot`, `state`, `params[5]`, `wind_from`). About 15 numbers.
- Moon offset, port lag, and the start date are **derived from the seed**, never saved, so a balance change to their derivation is a visible version bump rather than silent drift.
- Weather **history** is not saved; it is a function of `(seed, slot)`. Only the live blend (`params`) is saved so rain mid-fade resumes exactly. If the weather block is missing or the version mismatches, `deserialize` falls back to `weather.setup()` and replays the chain, giving the correct state with parameters snapped.
- JSON stringifies ints as floats; every read goes through `int()` / `float()`, and the seed must stay below 2^53.
- `deserialize` primes event baselines (`_prime_events`) so loading never fires a flood of `sunset`/`hour_changed`, then emits a single `ambient_updated`.
- Migration: bump `SAVE_VERSION`; add a `match` in `deserialize` that upgrades older dictionaries before use.
- Float determinism: the chain uses only integer hashing and table lookups; the astro functions use `sin/cos/atan2/asin` on doubles. Event timing could in theory differ by an epsilon across CPUs, but the *weather states* (the saved gameplay-relevant part) depend only on integer slots and a bucket classification, which cannot flip except at an exact elevation threshold at an exact slot midpoint (±0 ulp). Acceptable for a single-player game.

## 6. Headless tests

Run:

```
godot --headless --path . -s res://tests/world_tests.gd
```

Exit code is 0 on success, 1 on any failure. Only pure classes plus a bare `WeatherSystem` node are used (no autoload, no scene), so it also drops into CI or GUT unchanged (wrap each `_test_*` as a `test_*` method).

```gdscript
extends SceneTree

const LAT: float = 1.012291    # 58 degrees north
var _fail: int = 0
var _count: int = 0


func _init() -> void:
	_test_hash()
	_test_calendar()
	_test_sun()
	_test_moon_and_tide()
	_test_weather_tables()
	_test_weather_determinism()
	_test_relax_composes()
	_test_weather_save_roundtrip()
	print("world tests: %d checks, %d failed" % [_count, _fail])
	quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	_count += 1
	if not cond:
		_fail += 1
		printerr("FAIL: " + msg)


func _near(a: float, b: float, eps: float, msg: String) -> void:
	_ok(absf(a - b) <= eps, "%s (got %f, want %f +/- %f)" % [msg, a, b, eps])


func _test_hash() -> void:
	_ok(WorldMath.mix32(7, 9) == WorldMath.mix32(7, 9), "mix32 is deterministic")
	_ok(WorldMath.mix32(7, 9) != WorldMath.mix32(9, 7), "mix32 is not symmetric")
	var lo: float = 1.0
	var hi: float = 0.0
	for i: int in 2000:
		var u: float = WorldMath.unit(42, i)
		lo = minf(lo, u)
		hi = maxf(hi, u)
	_ok(lo >= 0.0 and hi < 1.0 and lo < 0.02 and hi > 0.98, "unit() covers [0,1)")


func _test_calendar() -> void:
	var d0: Dictionary = WorldMath.date_from_days(0.0)
	_ok(d0["season"] == WorldMath.Season.THAW and d0["day"] == 1 and d0["year"] == 1, "day 0 is Thaw 1, year 1")
	var d1: Dictionary = WorldMath.date_from_days(28.5)
	_ok(d1["season"] == WorldMath.Season.BRIGHT and d1["day"] == 1, "day 28 opens Brightwater")
	_ok(WorldMath.date_from_days(112.0)["year"] == 2, "day 112 starts year 2")
	_ok(WorldMath.clock_string(0.5) == "12:00", "clock string")


func _test_sun() -> void:
	_near(Astro.sun_state(LAT, 0.0).declination, 0.0, 1e-6, "equinox declination")
	_near(rad_to_deg(Astro.sun_state(LAT, 28.5).elevation), 55.44, 0.4, "summer noon elevation")
	_near(rad_to_deg(Astro.sun_state(LAT, 84.5).elevation), 8.56, 0.4, "winter noon elevation")
	_near(rad_to_deg(Astro.sun_state(LAT, 28.5).azimuth), 180.0, 0.5, "noon sun is due south")
	var summer: Vector2 = Astro.sunrise_sunset(LAT, Astro.OBLIQUITY)
	_ok(summer.y - summer.x > 18.0 and summer.y - summer.x < 18.4, "summer day length is about 18.2 h")
	var eq: Vector2 = Astro.sunrise_sunset(LAT, 0.0)
	_ok(eq.x > 5.7 and eq.x < 6.1, "equinox sunrise near 06:00")
	var morning: Astro.BodyState = Astro.sun_state(LAT, 28.0 + 8.0 / 24.0)
	_ok(morning.azimuth < PI, "morning sun is in the east")


func _test_moon_and_tide() -> void:
	# phase_offset 0.5 puts a full moon at t = 84.0 (winter solstice, solar midnight)
	var full: Astro.BodyState = Astro.moon_state(LAT, 84.0, 0.5)
	_near(full.illumination, 1.0, 1e-6, "full moon fully lit")
	var el: float = rad_to_deg(full.elevation)
	_ok(el > 57.0 and el < 64.0, "winter full moon rides high at midnight (got %f)" % el)
	_near(absf(full.hour_angle), 0.0, 0.02, "full moon transits at solar midnight")
	_ok(Astro.moon_phase_index(PI) == 4, "phase index 4 is Full Moon")
	_ok(Astro.moon_phase_index(0.0) == 0, "phase index 0 is New Moon")

	var spring_max: float = 0.0
	var neap_max: float = 0.0
	for i: int in 144:   # every 10 minutes
		var dt: float = float(i) / 144.0
		spring_max = maxf(spring_max, absf(TideModel.height_at(0.0 + dt, 0.0, 0.6)))
		neap_max = maxf(neap_max, absf(TideModel.height_at(7.0 + dt, 0.0, 0.6)))
	_ok(spring_max - neap_max > 0.4, "spring range exceeds neap (%f vs %f)" % [spring_max, neap_max])

	var ext: Vector2 = TideModel.next_extreme(0.3, 0.0, 0.6)
	_ok(ext.x > 0.3 and ext.x < 0.3 + 14.0 / 24.0, "next tide extreme within 14 h")
	_near(TideModel.trend(ext.x, 0.0, 0.6), 0.0, 2e-3, "trend is flat at an extreme")
	_ok(TideModel.level01(TideModel.MAX_HEIGHT) == 1.0 and TideModel.level01(-TideModel.MAX_HEIGHT) == 0.0, "level01 spans 0..1")


func _test_weather_tables() -> void:
	for season: int in 4:
		for bucket: int in 4:
			for s: int in WeatherModel.STATE_COUNT:
				var w: PackedFloat32Array = WeatherModel.transition_weights(s as WeatherModel.State, season, bucket)
				var sum: float = 0.0
				for x: float in w:
					sum += x
				_near(sum, 1.0, 1e-4, "row sums to 1")
	var day_w: PackedFloat32Array = WeatherModel.transition_weights(
			WeatherModel.State.FAIR, WorldMath.Season.HUSH, Astro.TimeOfDay.DAY)
	_ok(day_w[WeatherModel.State.AURORA] == 0.0, "no aurora in daylight")
	# long-run frequencies with a fixed season/bucket
	var counts: Array[int] = [0, 0, 0, 0, 0]
	var s2: WeatherModel.State = WeatherModel.State.FAIR
	for i: int in 20000:
		s2 = WeatherModel.step(s2, WorldMath.Season.BRIGHT, Astro.TimeOfDay.NIGHT, WorldMath.unit(99, i))
		counts[s2] += 1
	_ok(counts[WeatherModel.State.AURORA] == 0, "no aurora in Brightwater")
	_ok(counts[WeatherModel.State.FAIR] > 8000, "Brightwater is mostly fair")
	var gales_hush: int = 0
	var s3: WeatherModel.State = WeatherModel.State.FAIR
	for i: int in 20000:
		s3 = WeatherModel.step(s3, WorldMath.Season.HUSH, Astro.TimeOfDay.NIGHT, WorldMath.unit(99, i))
		if s3 == WeatherModel.State.HEAVY_GALE:
			gales_hush += 1
	_ok(gales_hush > counts[WeatherModel.State.HEAVY_GALE] * 2, "winter gales outnumber summer gales")


func _test_weather_determinism() -> void:
	var a: WeatherModel.State = WeatherModel.state_at_slot(1234, 800, LAT)
	var b: WeatherModel.State = WeatherModel.state_at_slot(1234, 800, LAT)
	_ok(a == b, "same seed and slot give same state")
	var differs: bool = false
	for slot: int in range(10, 200):
		if WeatherModel.state_at_slot(1, slot, LAT) != WeatherModel.state_at_slot(2, slot, LAT):
			differs = true
			break
	_ok(differs, "different seeds diverge")
	# stepping in different tick sizes must land on the same state and parameters
	var w1: WeatherSystem = WeatherSystem.new()
	var w2: WeatherSystem = WeatherSystem.new()
	w1.setup(77, LAT, 3.0)
	w2.setup(77, LAT, 3.0)
	var t1: float = 3.0
	var t2: float = 3.0
	for i: int in 288:   # one day in 5-minute ticks
		t1 += 5.0 / 1440.0
		w1.advance(5.0, t1)
	for i: int in 24:    # one day in 1-hour ticks
		t2 += 1.0 / 24.0
		w2.advance(60.0, t2)
	_ok(w1.slot == w2.slot and w1.state == w2.state, "tick size does not change the chain")
	_near(w1.fog_density, w2.fog_density, 0.01, "tick size does not change blended fog (within float error)")
	w1.free()
	w2.free()


func _test_relax_composes() -> void:
	var cur: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var tgt: PackedFloat32Array = WeatherModel.target_params(WeatherModel.State.HEAVY_GALE, 1.0)
	var two: PackedFloat32Array = WeatherModel.relax(WeatherModel.relax(cur, tgt, 10.0), tgt, 10.0)
	var one: PackedFloat32Array = WeatherModel.relax(cur, tgt, 20.0)
	for i: int in WeatherModel.PARAM_COUNT:
		_near(two[i], one[i], 1e-4, "relax composes (param %d)" % i)


func _test_weather_save_roundtrip() -> void:
	var w: WeatherSystem = WeatherSystem.new()
	w.setup(555, LAT, 40.0)
	var t: float = 40.0
	for i: int in 100:
		t += 5.0 / 1440.0
		w.advance(5.0, t)
	var d: Dictionary = JSON.parse_string(JSON.stringify(w.serialize())) as Dictionary
	var r: WeatherSystem = WeatherSystem.new()
	_ok(r.deserialize(d, LAT), "deserialize accepts current version")
	_ok(r.slot == w.slot and r.state == w.state, "roundtrip keeps slot and state")
	_near(r.rain_intensity, w.rain_intensity, 1e-4, "roundtrip keeps rain")
	_ok(r.forecast(6) == w.forecast(6), "forecast identical after load")
	_ok(not r.deserialize({"version": 99}, LAT), "unknown version rejected")
	w.free()
	r.free()
```

## 7. Tuning and extension notes

| Knob | Where | Effect |
|---|---|---|
| `DAY_REAL_SECONDS` | `TimeManager` | 1200 means a 20-minute day. Raise for a slower, more meditative pace. |
| `SPEED_SCALES` | `TimeManager` | SLOW 0.35 is for "watching the light"; FAST 3.0 for waiting out a gale. |
| `latitude_deg` | `TimeManager` export | 58 gives 18 h summer days. 50 is gentler; above 66.5 gives midnight sun (`sunrise_sunset` already handles it). |
| `M_*` matrices | `WeatherModel` | Rows need not sum to 1. Self-weight sets mean dwell: a 0.5 self-weight is about 4 game hours. |
| `TAU_MINUTES` | `WeatherModel` | Fog 90 min makes banks roll in visibly; lower for snappier weather. |
| `TIME_MODS` | `WeatherModel` | Dawn fog 1.8 gives the classic morning haze, then it burns off by day. |
| `TICK_MINUTES` | `TimeManager` | Do not exceed 60. A tick must never span more than one weather slot (120 min) or relaxation would be skipped. |

Performance: one frame at NORMAL runs one `weather.advance`, two `sun_state` calls and six tide evaluations (two moon equatorials each) at most; far below 0.05 ms. Sleep of 12 h is 144 ticks, a fraction of a millisecond. `refresh_snapshot` allocates two small `BodyState` objects and one `Dictionary` per 15 Hz publish; if profiling ever shows it, cache `date` per day and pool the states.

Natural extensions that need no architectural change: lightning during gale (derive from `rain_intensity > 0.6` with `unit(seed, floor(t*1440))`); eclipses (when `elongation` is near 0 or PI and `beta_m` is near 0, which is already in the formulas); wave height from `wind` and `tide_level01`; fishing bites keyed to `tide_turned`; festival days from `WorldMath.date_from_days()`.

Known simplifications (deliberate for readability and cozy tone): no equation of time or atmospheric refraction beyond the -0.833 degree convention; the moon's orbit is circular with a stylised nodal wobble; the tide ignores perigee (N2); latitude is global, not per-scene (the sea cave and the lighthouse share the sky).

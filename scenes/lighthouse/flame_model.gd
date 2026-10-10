class_name FlameModel
extends RefCounted
## Oil and wick wear. The flame state is a pure function of both.

enum FlameState { OUT, EMBER, STEADY, BRIGHT }

const OUT_BELOW: float = 0.01
const EMBER_BELOW: float = 0.25
const STEADY_BELOW: float = 0.9

var tuning: LanternTuning = LanternTuning.new()
## 0.0..1.0
var oil: float = 1.0
## 0.0..1.0
var wick_wear: float = 0.0


func brightness() -> float:
	var over: float = clampf(
		(wick_wear - tuning.wick_wear_threshold) / (1.0 - tuning.wick_wear_threshold), 0.0, 1.0)
	return oil * (1.0 - tuning.wick_dim_amount * over)


func get_state() -> FlameState:
	var b: float = brightness()
	if b < OUT_BELOW:
		return FlameState.OUT
	if b < EMBER_BELOW:
		return FlameState.EMBER
	if b < STEADY_BELOW:
		return FlameState.STEADY
	return FlameState.BRIGHT


func add_oil(amount: float) -> void:
	oil = clampf(oil + amount, 0.0, 1.0)


## Burn for real seconds. Wears the wick too.
func burn(seconds: float, deep_night: bool = false) -> void:
	var factor: float = tuning.deep_night_drain_factor if deep_night else 1.0
	oil = clampf(oil - tuning.oil_drain_per_second * factor * seconds, 0.0, 1.0)
	if oil > 0.0:
		wick_wear = clampf(wick_wear + seconds / tuning.wick_wear_seconds, 0.0, 1.0)


func trim_wick() -> void:
	wick_wear = 0.0

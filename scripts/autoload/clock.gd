extends Node
## Night clock: dusk (18:00) to dawn (06:00), 1 game minute = 1 real second by default.
## Time is in minutes since midnight of the evening the night starts (1080..1800).

enum Phase { DUSK, NIGHT, PRE_DAWN, SUNRISE }

## Emitted once per whole game minute change.
signal time_changed(minutes: int)
## Emitted when the phase changes.
signal phase_changed(phase: Phase)
## Emitted exactly once, at 06:00.
signal night_ended

const NIGHT_START: float = 1080.0
const NIGHT_END: float = 1800.0
const DUSK_END: float = 1200.0
const NIGHT_PHASE_END: float = 1680.0
const PRE_DAWN_END: float = 1770.0

## Game minutes per real second.
var minutes_per_second: float = 1.0
var minutes: float = NIGHT_START
var phase: Phase = Phase.DUSK
var running: bool = false

var _ended: bool = false
var _last_whole_minute: int = int(NIGHT_START)


func _process(delta: float) -> void:
	if running:
		advance(delta)


func start_night() -> void:
	minutes = NIGHT_START
	phase = Phase.DUSK
	_ended = false
	_last_whole_minute = int(NIGHT_START)
	running = true


## Advance the clock by real seconds. Pure logic, called by _process and by tests.
func advance(seconds: float) -> void:
	if _ended:
		return
	minutes = minf(minutes + seconds * minutes_per_second, NIGHT_END)
	var whole: int = int(minutes)
	if whole != _last_whole_minute:
		_last_whole_minute = whole
		time_changed.emit(whole)
	var new_phase: Phase = phase_for(minutes)
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)
	if minutes >= NIGHT_END:
		_ended = true
		running = false
		night_ended.emit()


static func phase_for(at_minutes: float) -> Phase:
	if at_minutes < DUSK_END:
		return Phase.DUSK
	if at_minutes < NIGHT_PHASE_END:
		return Phase.NIGHT
	if at_minutes < PRE_DAWN_END:
		return Phase.PRE_DAWN
	return Phase.SUNRISE


## "HH:MM" for display and logs.
func clock_text() -> String:
	var wrapped: int = int(minutes) % 1440
	return "%02d:%02d" % [wrapped / 60, wrapped % 60]

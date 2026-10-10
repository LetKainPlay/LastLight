extends SceneTree
## Headless test for Clock. Run: godot --headless --path . --script res://tests/test_clock.gd

const ClockScript: GDScript = preload("res://scripts/autoload/clock.gd")

var _failed: bool = false
var _ended_count: int = 0


func _init() -> void:
	var clock: Node = ClockScript.new()
	clock.night_ended.connect(_on_clock_night_ended)
	clock.start_night()
	for i: int in 800:
		clock.advance(1.0)
	_expect(_ended_count == 1, "night_ended emitted exactly once, got %d" % _ended_count)
	_expect(clock.clock_text() == "06:00", "ends at 06:00, got %s" % clock.clock_text())
	_expect(ClockScript.phase_for(1080.0) == ClockScript.Phase.DUSK, "18:00 is dusk")
	_expect(ClockScript.phase_for(1500.0) == ClockScript.Phase.NIGHT, "01:00 is night")
	_expect(ClockScript.phase_for(1700.0) == ClockScript.Phase.PRE_DAWN, "04:40 is pre-dawn")
	_expect(ClockScript.phase_for(1790.0) == ClockScript.Phase.SUNRISE, "05:50 is sunrise")
	clock.free()
	quit(1 if _failed else 0)


func _on_clock_night_ended() -> void:
	_ended_count += 1


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("PASS %s" % message)
	else:
		_failed = true
		printerr("FAIL %s" % message)

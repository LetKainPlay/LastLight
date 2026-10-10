extends SceneTree
## Headless test for FlameModel. Run: godot --headless --path . --script res://tests/test_flame_model.gd

var _failed: bool = false


func _init() -> void:
	_check_state(0.0, 0.0, FlameModel.FlameState.OUT)
	_check_state(0.05, 0.0, FlameModel.FlameState.EMBER)
	_check_state(0.5, 0.0, FlameModel.FlameState.STEADY)
	_check_state(1.0, 0.0, FlameModel.FlameState.BRIGHT)
	_check_state(1.0, 1.0, FlameModel.FlameState.STEADY)
	_check_clamped()
	quit(1 if _failed else 0)


func _check_state(oil: float, wear: float, expected: FlameModel.FlameState) -> void:
	var model: FlameModel = FlameModel.new()
	model.oil = oil
	model.wick_wear = wear
	var actual: FlameModel.FlameState = model.get_state()
	if actual != expected:
		_failed = true
		printerr("FAIL oil=%s wear=%s expected %s got %s" % [oil, wear, expected, actual])
	else:
		print("PASS oil=%s wear=%s" % [oil, wear])


func _check_clamped() -> void:
	var model: FlameModel = FlameModel.new()
	model.add_oil(5.0)
	if model.oil > 1.0:
		_failed = true
		printerr("FAIL oil exceeded capacity: %s" % model.oil)
	model.burn(9999.0)
	if model.oil < 0.0:
		_failed = true
		printerr("FAIL oil went negative: %s" % model.oil)
	model.trim_wick()
	if model.wick_wear != 0.0:
		_failed = true
		printerr("FAIL trim did not reset wear")

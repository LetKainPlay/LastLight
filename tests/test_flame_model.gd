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
	_check_relight()
	_check_reset()
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


func _check_relight() -> void:
	var model: FlameModel = FlameModel.new()
	model.burn(9999.0)
	if model.get_state() != FlameModel.FlameState.OUT:
		_failed = true
		printerr("FAIL burnt-out flame is not OUT")
	model.add_oil(1.0)
	if model.get_state() != FlameModel.FlameState.OUT:
		_failed = true
		printerr("FAIL adding oil relit the flame")
	model.relight()
	if model.get_state() != FlameModel.FlameState.BRIGHT:
		_failed = true
		printerr("FAIL match did not relight")


func _check_reset() -> void:
	var model: FlameModel = FlameModel.new()
	model.burn(9999.0)
	model.reset()
	if model.get_state() != FlameModel.FlameState.BRIGHT:
		_failed = true
		printerr("FAIL reset did not restore a bright flame")

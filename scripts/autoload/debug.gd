extends Node
## Debug overlay (F1) and time controls. Does nothing in release builds.
## Launch with `-- --night-speed=10` to compress the night.

const SPEED_FLAG: String = "--night-speed="

var _label: Label = null


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		set_process_unhandled_input(false)
		return
	_apply_speed_flag()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	_label = Label.new()
	_label.visible = false
	layer.add_child(_label)
	add_child(layer)


func _process(_delta: float) -> void:
	if _label.visible:
		_label.text = "%d fps  %s  x%.1f" % [
			Engine.get_frames_per_second(), Clock.clock_text(), Clock.minutes_per_second]


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_label.visible = not _label.visible
		KEY_BRACKETLEFT:
			Clock.minutes_per_second = maxf(Clock.minutes_per_second * 0.5, 0.25)
		KEY_BRACKETRIGHT:
			Clock.minutes_per_second = minf(Clock.minutes_per_second * 2.0, 64.0)


func _apply_speed_flag() -> void:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with(SPEED_FLAG):
			Clock.minutes_per_second = clampf(float(arg.trim_prefix(SPEED_FLAG)), 0.25, 64.0)

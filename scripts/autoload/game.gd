extends Node
## Save/load: only the night-completed flag and volume. Local JSON.

const DEFAULT_SAVE_PATH: String = "user://save.json"
const OIL_CANS_PER_NIGHT: int = 4
const DEEP_NIGHT_START: float = 1440.0
const DEEP_NIGHT_END: float = 1680.0

var night_completed: bool = false
## Master volume, 0.0..1.0.
var volume: float = 0.8
var save_path: String = DEFAULT_SAVE_PATH

## The one flame of the night. Rooms only display it.
var flame: FlameModel = FlameModel.new()
## Game minutes the flame has been lit tonight.
var lit_minutes: float = 0.0
var oil_cans_left: int = OIL_CANS_PER_NIGHT

var _clock: Node = null


func _ready() -> void:
	load_save()


func _process(delta: float) -> void:
	if _clock == null:
		_clock = get_node_or_null("/root/Clock")
		return
	if not _clock.running:
		return
	var minutes: float = _clock.minutes
	flame.burn(delta, minutes >= DEEP_NIGHT_START and minutes < DEEP_NIGHT_END)
	if flame.lit:
		lit_minutes += delta * _clock.minutes_per_second


func reset_night() -> void:
	flame.reset()
	lit_minutes = 0.0
	oil_cans_left = OIL_CANS_PER_NIGHT


func save() -> void:
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write save file: %s" % save_path)
		return
	file.store_string(JSON.stringify({"night_completed": night_completed, "volume": volume}))


func load_save() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	night_completed = bool(data.get("night_completed", false))
	volume = clampf(float(data.get("volume", 0.8)), 0.0, 1.0)

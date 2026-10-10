extends Node
## Save/load: only the night-completed flag and volume. Local JSON.

const DEFAULT_SAVE_PATH: String = "user://save.json"

var night_completed: bool = false
## Master volume, 0.0..1.0.
var volume: float = 0.8
var save_path: String = DEFAULT_SAVE_PATH


func _ready() -> void:
	load_save()


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

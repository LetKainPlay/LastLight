extends Node2D
## Thin bootstrap: loads the active room and fades between rooms.

const ROOMS: Dictionary[StringName, PackedScene] = {
	&"keepers_quarters": preload("res://scenes/rooms/keepers_quarters.tscn"),
	&"lantern_room": preload("res://scenes/rooms/lantern_room.tscn"),
}
const FADE_SECONDS: float = 0.2

var _room: Room = null
var _changing: bool = false

@onready var _rooms_root: Node2D = $Rooms
@onready var _player: Player = $Player
@onready var _fade: ColorRect = $FadeLayer/Fade


func _ready() -> void:
	_enter_room(&"keepers_quarters", &"Start")
	_fade_to(0.0)


func _enter_room(room_name: StringName, spawn_name: StringName) -> void:
	if _room != null:
		_room.queue_free()
	_room = ROOMS[room_name].instantiate() as Room
	_rooms_root.add_child(_room)
	for room_exit: RoomExit in _room.get_exits():
		room_exit.exit_requested.connect(_on_room_exit_exit_requested)
	_player.position = _room.spawn_point(spawn_name)
	_player.velocity = Vector2.ZERO


func _fade_to(alpha: float) -> Tween:
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_SECONDS)
	return tween


func _on_room_exit_exit_requested(room_name: StringName, spawn_name: StringName) -> void:
	if _changing:
		return
	_changing = true
	_player.set_physics_process(false)
	await _fade_to(1.0).finished
	_enter_room(room_name, spawn_name)
	await _fade_to(0.0).finished
	_player.set_physics_process(true)
	_changing = false

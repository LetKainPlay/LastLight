extends Node2D
## Thin bootstrap: loads the active room, fades between rooms, runs title -> night -> sunrise.

enum Stage { TITLE, NIGHT, SUNRISE }

const ROOMS: Dictionary[StringName, PackedScene] = {
	&"keepers_quarters": preload("res://scenes/rooms/keepers_quarters.tscn"),
	&"lantern_room": preload("res://scenes/rooms/lantern_room.tscn"),
}
const FADE_SECONDS: float = 0.2
const TINT_SECONDS: float = 3.0
## Indexed by Clock.Phase: dusk, night, pre-dawn, sunrise.
const PHASE_TINTS: Array[Color] = [
	Color(1.0, 0.82, 0.7),
	Color(0.45, 0.5, 0.8),
	Color(0.6, 0.6, 0.85),
	Color(1.0, 0.86, 0.75),
]

var _stage: Stage = Stage.TITLE
var _room: Room = null
var _changing: bool = false

@onready var _clock: Node = get_node("/root/Clock")
@onready var _game: Node = get_node("/root/Game")
@onready var _rooms_root: Node2D = $Rooms
@onready var _player: Player = $Player
@onready var _tint: CanvasModulate = $Tint
@onready var _fade: ColorRect = $FadeLayer/Fade
@onready var _card: Control = $CardLayer/Card
@onready var _card_title: Label = $CardLayer/Card/Title
@onready var _card_line: Label = $CardLayer/Card/Line


func _ready() -> void:
	_clock.phase_changed.connect(_on_clock_phase_changed)
	_clock.night_ended.connect(_on_clock_night_ended)
	_show_title()
	_fade_to(0.0)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _stage == Stage.TITLE or _stage == Stage.SUNRISE:
		_start_night()


func _show_title() -> void:
	_stage = Stage.TITLE
	_player.set_physics_process(false)
	_card_title.text = "Het Laatste Licht"
	_card_line.text = "Druk op een toets"
	_card.visible = true
	_set_tint(PHASE_TINTS[0], 0.0)


func _start_night() -> void:
	_stage = Stage.NIGHT
	_card.visible = false
	_game.reset_night()
	_player.has_oil_can = false
	_enter_room(&"keepers_quarters", &"Start")
	_player.set_physics_process(true)
	_clock.start_night()
	_set_tint(PHASE_TINTS[0], 0.0)


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


func _set_tint(color: Color, seconds: float) -> void:
	if seconds <= 0.0:
		_tint.color = color
		return
	create_tween().tween_property(_tint, "color", color, seconds)


func _on_room_exit_exit_requested(room_name: StringName, spawn_name: StringName) -> void:
	if _changing:
		return
	_changing = true
	_player.set_physics_process(false)
	await _fade_to(1.0).finished
	_enter_room(room_name, spawn_name)
	await _fade_to(0.0).finished
	_player.set_physics_process(_stage == Stage.NIGHT)
	_changing = false


func _on_clock_phase_changed(phase: int) -> void:
	_set_tint(PHASE_TINTS[phase], TINT_SECONDS)


func _on_clock_night_ended() -> void:
	_stage = Stage.SUNRISE
	_player.set_physics_process(false)
	var total: int = int(_game.lit_minutes)
	_card_title.text = "De zon komt op"
	_card_line.text = "Het licht brandde %d uur en %d minuten." % [total / 60, total % 60]
	_card.visible = true
	_game.night_completed = true
	_game.save()

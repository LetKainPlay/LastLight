class_name RoomExit
extends Area2D
## Stairs or door. Asks for a room change when the player walks in.

## Emitted once when the player enters.
signal exit_requested(room: StringName, spawn: StringName)

@export var target_room: StringName = &""
@export var target_spawn: StringName = &""


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		exit_requested.emit(target_room, target_spawn)

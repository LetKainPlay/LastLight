class_name Interactable
extends Area2D
## Something the player can use. Tap (hold_time 0) or hold to complete.

## Emitted when the interaction completes.
signal interacted(who: Node2D)
## Emitted while holding, 0.0..1.0.
signal hold_progressed(fraction: float)

@export_range(0.0, 5.0) var hold_time: float = 0.0

var _held: float = 0.0
var _done: bool = false

@onready var _prompt: Sprite2D = $Prompt


func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	_prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func press(who: Node2D) -> void:
	if hold_time <= 0.0:
		interacted.emit(who)


func hold(delta: float, who: Node2D) -> void:
	if hold_time <= 0.0 or _done:
		return
	_held += delta
	hold_progressed.emit(clampf(_held / hold_time, 0.0, 1.0))
	if _held >= hold_time:
		_done = true
		interacted.emit(who)


func release() -> void:
	_held = 0.0
	_done = false
	hold_progressed.emit(0.0)


func _on_body_entered(body: Node2D) -> void:
	var player: Player = body as Player
	if player != null:
		player.set_nearby(self)
		_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	var player: Player = body as Player
	if player != null:
		player.clear_nearby(self)
		_prompt.visible = false

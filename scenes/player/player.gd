class_name Player
extends CharacterBody2D
## Walks the rooms. Position stays a float; only the visual is snapped to the pixel grid.

## Emitted every FOOTSTEP_DISTANCE pixels walked.
signal footstep

enum Facing { DOWN, UP, LEFT, RIGHT }

const SPEED: float = 60.0
const FOOTSTEP_DISTANCE: float = 14.0

var facing: Facing = Facing.DOWN

var _walked: float = 0.0
var _nearby: Interactable = null

@onready var _visual: Node2D = $Visual


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = direction * SPEED
	move_and_slide()
	if direction != Vector2.ZERO:
		_update_facing(direction)
		_walked += get_real_velocity().length() * delta
		if _walked >= FOOTSTEP_DISTANCE:
			_walked = 0.0
			footstep.emit()
	_visual.position = Vector2(Pixel.snap(position)) - position
	_handle_interaction(delta)


func set_nearby(interactable: Interactable) -> void:
	_nearby = interactable


func clear_nearby(interactable: Interactable) -> void:
	if _nearby == interactable:
		_nearby.release()
		_nearby = null


func _update_facing(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		facing = Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	else:
		facing = Facing.DOWN if direction.y > 0.0 else Facing.UP


func _handle_interaction(delta: float) -> void:
	if _nearby == null:
		return
	if Input.is_action_just_pressed(&"interact"):
		_nearby.press(self)
	elif Input.is_action_pressed(&"interact"):
		_nearby.hold(delta, self)
	elif Input.is_action_just_released(&"interact"):
		_nearby.release()

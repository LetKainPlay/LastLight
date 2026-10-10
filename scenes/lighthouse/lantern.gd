class_name Lantern
extends Node2D
## The lamp. Owns the FlameModel, burns oil while the night runs, and shows the flame.

## Emitted when the flame changes state.
signal flame_state_changed(state: FlameModel.FlameState)

const DEEP_NIGHT_START: float = 1440.0
const DEEP_NIGHT_END: float = 1680.0
const FLAME_COLORS: Dictionary[FlameModel.FlameState, Color] = {
	FlameModel.FlameState.OUT: Color(0.172549, 0.207843, 0.329412, 1),
	FlameModel.FlameState.EMBER: Color(0.784314, 0.501961, 0.172549, 1),
	FlameModel.FlameState.STEADY: Color(0.94902, 0.705882, 0.254902, 1),
	FlameModel.FlameState.BRIGHT: Color(1, 0.901961, 0.603922, 1),
}

var model: FlameModel = FlameModel.new()

var _state: FlameModel.FlameState = FlameModel.FlameState.BRIGHT

@onready var _clock: Node = get_node("/root/Clock")
@onready var _flame: Polygon2D = $Flame
@onready var _reservoir: Interactable = $Reservoir
@onready var _wick: Interactable = $Wick
@onready var _match: Interactable = $Match


func _ready() -> void:
	_reservoir.interacted.connect(_on_reservoir_interacted)
	_wick.interacted.connect(_on_wick_interacted)
	_match.interacted.connect(_on_match_interacted)
	_show_flame()


func _process(delta: float) -> void:
	if _clock.running:
		var minutes: float = _clock.minutes
		model.burn(delta, minutes >= DEEP_NIGHT_START and minutes < DEEP_NIGHT_END)
	_show_flame()


func _show_flame() -> void:
	var state: FlameModel.FlameState = model.get_state()
	_flame.visible = state != FlameModel.FlameState.OUT
	_flame.color = FLAME_COLORS[state]
	_flame.scale = Vector2.ONE * (0.4 + 0.6 * model.brightness())
	if state != _state:
		_state = state
		flame_state_changed.emit(state)


func _on_reservoir_interacted(who: Node2D) -> void:
	var player: Player = who as Player
	if player != null and player.has_oil_can:
		player.has_oil_can = false
		model.add_oil(1.0)


func _on_wick_interacted(_who: Node2D) -> void:
	model.trim_wick()


func _on_match_interacted(_who: Node2D) -> void:
	model.relight()

class_name Lantern
extends Node2D
## The lamp. Shows and tends the night's flame (kept on Game, so it survives leaving the room).

## Emitted when the flame changes state.
signal flame_state_changed(state: FlameModel.FlameState)

const FLAME_TEXTURES: Dictionary[FlameModel.FlameState, Texture2D] = {
	FlameModel.FlameState.EMBER: preload("res://art/sprites/fx_flame_ember.png"),
	FlameModel.FlameState.STEADY: preload("res://art/sprites/fx_flame_steady.png"),
	FlameModel.FlameState.BRIGHT: preload("res://art/sprites/fx_flame_bright.png"),
}

var model: FlameModel = null

var _state: FlameModel.FlameState = FlameModel.FlameState.BRIGHT

@onready var _flame: Sprite2D = $Flame
@onready var _reservoir: Interactable = $Reservoir
@onready var _wick: Interactable = $Wick
@onready var _match: Interactable = $Match


func _ready() -> void:
	model = get_node("/root/Game").flame
	_reservoir.interacted.connect(_on_reservoir_interacted)
	_wick.interacted.connect(_on_wick_interacted)
	_match.interacted.connect(_on_match_interacted)
	_show_flame()


func _process(_delta: float) -> void:
	_show_flame()


func _show_flame() -> void:
	var state: FlameModel.FlameState = model.get_state()
	_flame.visible = state != FlameModel.FlameState.OUT
	if state != FlameModel.FlameState.OUT:
		_flame.texture = FLAME_TEXTURES[state]
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

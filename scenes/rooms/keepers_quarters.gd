extends Room
## Keeper's quarters: the oil barrel hands out cans, four over the night.

@onready var _game: Node = get_node("/root/Game")
@onready var _barrel: Interactable = $OilBarrel


func _ready() -> void:
	_barrel.interacted.connect(_on_oil_barrel_interacted)


func _on_oil_barrel_interacted(who: Node2D) -> void:
	var player: Player = who as Player
	if player != null and not player.has_oil_can and _game.oil_cans_left > 0:
		_game.oil_cans_left -= 1
		player.has_oil_can = true

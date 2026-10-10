extends Room
## Keeper's quarters: the oil barrel hands out cans, four over the night.

const STARTING_STOCK: int = 4

var _stock: int = STARTING_STOCK

@onready var _barrel: Interactable = $OilBarrel


func _ready() -> void:
	_barrel.interacted.connect(_on_oil_barrel_interacted)


func _on_oil_barrel_interacted(who: Node2D) -> void:
	var player: Player = who as Player
	if player != null and not player.has_oil_can and _stock > 0:
		_stock -= 1
		player.has_oil_can = true

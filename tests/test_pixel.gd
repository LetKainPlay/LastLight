extends SceneTree
## Headless test for Pixel. Run: godot --headless --path . --script res://tests/test_pixel.gd


func _init() -> void:
	var ok: bool = Pixel.snap(Vector2(1.4, -2.6)) == Vector2i(1, -3)
	print("PASS pixel snap" if ok else "FAIL pixel snap")
	quit(0 if ok else 1)

class_name Pixel
extends RefCounted
## Pixel-grid helpers.


## Round a world position to the pixel grid. Render with this, keep the float elsewhere.
static func snap(position: Vector2) -> Vector2i:
	return Vector2i(roundi(position.x), roundi(position.y))

class_name Room
extends Node2D
## A room: floor, walls, spawn markers under `Spawns`, and RoomExit triggers.


func spawn_point(spawn_name: StringName) -> Vector2:
	var marker: Marker2D = get_node_or_null("Spawns/%s" % spawn_name) as Marker2D
	if marker == null:
		push_warning("%s has no spawn '%s'" % [name, spawn_name])
		return Vector2.ZERO
	return marker.position


func get_exits() -> Array[RoomExit]:
	var exits: Array[RoomExit] = []
	for node: Node in find_children("*", "RoomExit", true, false):
		exits.append(node as RoomExit)
	return exits

class_name LevelBuilder
extends RefCounted

const SOLID_RECT_SCENE := preload(
	"res://scenes/level_solid_rect.tscn"
)
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_ENEMY_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)


static func build_into(arena: Node, data: Dictionary) -> Dictionary:
	var geometry_parent := arena.get_node_or_null("Geometry/LevelObjects")
	var actors_parent := arena.get_node_or_null("Actors")
	var errors: Array[String] = []

	if not is_instance_valid(geometry_parent):
		errors.append(
			"Runtime arena is missing Geometry/LevelObjects."
		)
	if not is_instance_valid(actors_parent):
		errors.append("Runtime arena is missing Actors.")
	if not errors.is_empty():
		return _failure(errors)

	if (
		geometry_parent.get_child_count() > 0
		or actors_parent.get_child_count() > 0
	):
		return _failure(
			["Runtime arena already contains generated level objects."]
		)

	var placements: Array[Dictionary] = []
	var objects_by_id: Dictionary = {}

	for definition: Dictionary in data["objects"]:
		var build_result := _create_object(definition)
		if not bool(build_result["ok"]):
			errors.append_array(build_result["errors"])
			_discard_placements(placements)
			return _failure(errors)

		var node := build_result["node"] as Node
		var object_id: String = definition["id"]
		var parent := (
			geometry_parent
			if build_result["parent"] == "geometry"
			else actors_parent
		)
		node.name = StringName(object_id)
		node.set_meta("level_object_id", object_id)
		placements.append({"parent": parent, "node": node})
		objects_by_id[object_id] = node

	for placement: Dictionary in placements:
		var parent := placement["parent"] as Node
		var node := placement["node"] as Node
		parent.add_child(node)

	return {
		"ok": true,
		"errors": [] as Array[String],
		"objects": objects_by_id,
	}


static func _create_object(definition: Dictionary) -> Dictionary:
	var object_type: String = definition["type"]

	match object_type:
		"solid_rect":
			var solid := SOLID_RECT_SCENE.instantiate()
			if not is_instance_valid(solid):
				return _object_failure(
					"Could not instantiate solid_rect."
				)

			var values: Array = definition["rect"]
			solid.call(
				"configure",
				Rect2(
					float(values[0]),
					float(values[1]),
					float(values[2]),
					float(values[3])
				)
			)
			return _object_success(solid, "geometry")

		"player_spawn":
			var player := PLAYER_SCENE.instantiate() as Player
			if not is_instance_valid(player):
				return _object_failure(
					"Could not instantiate player_spawn."
				)

			player.position = _vector_from(definition["position"])
			return _object_success(player, "actors")

		"patrol_enemy":
			var enemy := (
				PATROL_ENEMY_SCENE.instantiate() as PatrolEnemy
			)
			if not is_instance_valid(enemy):
				return _object_failure(
					"Could not instantiate patrol_enemy."
				)

			enemy.position = _vector_from(definition["position"])
			enemy.patrol_speed = float(definition["speed"])
			enemy.patrol_direction = float(definition["direction"])
			return _object_success(enemy, "actors")

	return _object_failure(
		"Builder does not support object type '%s'." % object_type
	)


static func _vector_from(values: Array) -> Vector2:
	return Vector2(float(values[0]), float(values[1]))


static func _object_success(node: Node, parent: String) -> Dictionary:
	return {
		"ok": true,
		"errors": [] as Array[String],
		"node": node,
		"parent": parent,
	}


static func _object_failure(message: String) -> Dictionary:
	var errors: Array[String] = [message]
	return {
		"ok": false,
		"errors": errors,
		"node": null,
		"parent": "",
	}


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"errors": errors,
		"objects": {},
	}


static func _discard_placements(
	placements: Array[Dictionary]
) -> void:
	for placement: Dictionary in placements:
		var node := placement["node"] as Node
		if is_instance_valid(node):
			node.free()

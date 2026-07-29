class_name LevelBuilder
extends RefCounted

const SOLID_RECT_SCENE := preload(
	"res://scenes/level_solid_rect.tscn"
)
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_ENEMY_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)
const SHOVE_ENEMY_SCENE := preload(
	"res://scenes/shove_enemy.tscn"
)
const SHOOTER_ENEMY_SCENE := preload(
	"res://scenes/shooter_enemy.tscn"
)
const CATAPULT_PLATFORM_SCENE := preload(
	"res://scenes/rotating_platform.tscn"
)
const VERTICAL_PLATFORM_SCENE := preload(
	"res://scenes/vertical_platform.tscn"
)
const TOGGLE_PLATFORM_SCENE := preload(
	"res://scenes/toggle_platform.tscn"
)
const HINGE_SCENE := preload("res://scenes/hinge.tscn")

const LINK_COLOR := Color(0.439, 0.827, 0.816, 0.48)
const LINK_WIDTH := 3.0


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
		if objects_by_id.has(object_id):
			errors.append(
				"Builder received duplicate object ID '%s'." % object_id
			)
			node.free()
			_discard_placements(placements)
			return _failure(errors)
		var parent := (
			geometry_parent
			if build_result["parent"] == "geometry"
			else actors_parent
		)
		node.name = StringName(object_id)
		node.set_meta("level_object_id", object_id)
		placements.append({"parent": parent, "node": node})
		objects_by_id[object_id] = node

	var link_result := _resolve_links(
		data["objects"],
		objects_by_id,
		placements,
		geometry_parent
	)
	if not bool(link_result["ok"]):
		_discard_placements(placements)
		return _failure(link_result["errors"])

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
				),
				bool(definition.get("one_way", false))
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

		"shove_enemy":
			var enemy := (
				SHOVE_ENEMY_SCENE.instantiate() as ShoveEnemy
			)
			if not is_instance_valid(enemy):
				return _object_failure(
					"Could not instantiate shove_enemy."
				)

			enemy.position = _vector_from(definition["position"])
			enemy.patrol_direction = float(definition["direction"])
			return _object_success(enemy, "actors")

		"shooter_enemy":
			var enemy := (
				SHOOTER_ENEMY_SCENE.instantiate() as ShooterEnemy
			)
			if not is_instance_valid(enemy):
				return _object_failure(
					"Could not instantiate shooter_enemy."
				)

			enemy.position = _vector_from(definition["position"])
			return _object_success(enemy, "actors")

		"catapult_platform":
			var platform := (
				CATAPULT_PLATFORM_SCENE.instantiate()
				as RotatingPlatform
			)
			if not is_instance_valid(platform):
				return _object_failure(
					"Could not instantiate catapult_platform."
				)

			platform.position = _vector_from(definition["position"])
			return _object_success(platform, "geometry")

		"vertical_platform":
			var platform := (
				VERTICAL_PLATFORM_SCENE.instantiate()
				as VerticalPlatform
			)
			if not is_instance_valid(platform):
				return _object_failure(
					"Could not instantiate vertical_platform."
				)

			platform.position = _vector_from(definition["position"])
			return _object_success(platform, "geometry")

		"toggle_platform":
			var platform := (
				TOGGLE_PLATFORM_SCENE.instantiate()
				as TogglePlatform
			)
			if not is_instance_valid(platform):
				return _object_failure(
					"Could not instantiate toggle_platform."
				)

			var values: Array = definition["rect"]
			platform.configure(
				Rect2(
					float(values[0]),
					float(values[1]),
					float(values[2]),
					float(values[3])
				),
				bool(definition["starts_active"])
			)
			return _object_success(platform, "geometry")

		"hinge":
			var hinge := HINGE_SCENE.instantiate() as Hinge
			if not is_instance_valid(hinge):
				return _object_failure(
					"Could not instantiate hinge."
				)

			hinge.position = _vector_from(definition["position"])
			return _object_success(hinge, "geometry")

	return _object_failure(
		"Builder does not support object type '%s'." % object_type
	)


static func _resolve_links(
	definitions: Array,
	objects_by_id: Dictionary,
	placements: Array[Dictionary],
	geometry_parent: Node
) -> Dictionary:
	var errors: Array[String] = []
	for definition: Dictionary in definitions:
		if definition["type"] != "hinge":
			continue

		var source_id: String = definition["id"]
		var target_id: String = definition["target_id"]
		var source := objects_by_id.get(source_id) as Node
		var target := objects_by_id.get(target_id) as Node
		if not source is Hinge:
			errors.append(
				"Object '%s' is not a hinge during link resolution."
				% source_id
			)
			continue
		if (
			not target is TogglePlatform
			and not target is RotatingPlatform
			and not target is VerticalPlatform
		):
			errors.append(
				(
					"Hinge '%s' target '%s' is missing or is not "
					+ "a supported mechanism."
				)
				% [source_id, target_id]
			)
			continue

		(source as Hinge).configure_target(target)
		var cable := _create_link_line(
			source as Node2D,
			target as Node2D,
			source_id
		)
		placements.append(
			{"parent": geometry_parent, "node": cable}
		)

	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "errors": [] as Array[String]}


static func _create_link_line(
	source: Node2D,
	target: Node2D,
	source_id: String
) -> Line2D:
	var cable := Line2D.new()
	cable.name = StringName("Link_%s" % source_id)
	cable.z_index = -2
	cable.width = LINK_WIDTH
	cable.default_color = LINK_COLOR
	cable.points = PackedVector2Array(
		[source.position, target.position]
	)
	cable.set_meta("level_link_source_id", source_id)
	return cable


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

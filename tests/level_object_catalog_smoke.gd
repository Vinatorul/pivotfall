extends SceneTree

const CATALOG := preload("res://scripts/levels/level_object_catalog.gd")
const VALIDATOR := preload("res://scripts/levels/level_data_validator.gd")
const BUILDER := preload("res://scripts/levels/level_builder.gd")
const EDITOR_CANVAS := preload("res://scripts/editor/level_editor_canvas.gd")
const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")

const CATEGORIES: Array[LevelObjectCatalog.Category] = [
	CATALOG.Category.RECT,
	CATALOG.Category.POINT,
	CATALOG.Category.ACTOR,
	CATALOG.Category.ENEMY,
	CATALOG.Category.SUPPORT,
	CATALOG.Category.HINGE_TARGET,
	CATALOG.Category.PROJECTILE_BLOCKER,
]
const EXPECTED_ACTOR_EXTENTS := {
	CATALOG.TYPE_PLAYER_SPAWN: Vector2i(14, 20),
	CATALOG.TYPE_PATROL_ENEMY: Vector2i(15, 18),
	CATALOG.TYPE_SHOVE_ENEMY: Vector2i(16, 19),
	CATALOG.TYPE_SHOOTER_ENEMY: Vector2i(17, 19),
}

var failures: Array[String] = []


class BuilderArena:
	extends Node2D

	func resolve_lethal_hazard(
		_body: Node2D,
		_cause: int,
		_direction: Vector2
	) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_contract()
	var fixture := _fixture()
	_test_fixture_contract(fixture)
	var validation: Dictionary = VALIDATOR.validate_and_normalize(fixture)
	_expect(
		bool(validation.get("ok", false)),
		"Validator rejected the all-types fixture: %s"
		% [validation.get("errors", [])]
	)
	if bool(validation.get("ok", false)):
		_test_builder(validation["data"])
		await _test_editor_and_canvas(validation["data"])
	_test_validation_messages(fixture)
	_finish()


func _test_catalog_contract() -> void:
	var supported: Array[String] = CATALOG.supported_types()
	_expect(_string_set(supported).size() == supported.size(), "Supported type IDs are not unique.")
	for type_id: String in supported:
		_expect(CATALOG.is_supported_type(type_id), "Catalog rejected its own type '%s'." % type_id)
	_test_category_entries(supported)
	_test_shape_partition(supported)
	_test_actor_contract(supported)
	_test_copy_contract()
	_test_canvas_order(EDITOR_CANVAS.DRAW_ORDER, "draw")
	_test_canvas_order(EDITOR_CANVAS.HIT_ORDER, "hit")


func _test_category_entries(supported: Array[String]) -> void:
	for category: LevelObjectCatalog.Category in CATEGORIES:
		var entries: Array[String] = CATALOG.category_types(category)
		_expect(
			_string_set(entries).size() == entries.size(),
			"Catalog category %s contains duplicate IDs." % category
		)
		for type_id: String in entries:
			_expect(
				supported.has(type_id),
				"Catalog category %s contains unsupported type '%s'."
				% [category, type_id]
			)


func _test_shape_partition(supported: Array[String]) -> void:
	var rects: Array[String] = CATALOG.category_types(CATALOG.Category.RECT)
	var points: Array[String] = CATALOG.category_types(CATALOG.Category.POINT)
	for type_id: String in supported:
		var memberships := int(rects.has(type_id)) + int(points.has(type_id))
		_expect(memberships == 1, "Type '%s' must belong to exactly one shape category." % type_id)


func _test_actor_contract(supported: Array[String]) -> void:
	var actors: Array[String] = CATALOG.category_types(CATALOG.Category.ACTOR)
	var enemies: Array[String] = CATALOG.category_types(CATALOG.Category.ENEMY)
	_expect(
		_same_string_set(actors, EXPECTED_ACTOR_EXTENTS.keys()),
		"Actor types drifted from the extents contract."
	)
	for type_id: String in supported:
		var is_actor := actors.has(type_id)
		_expect(
			CATALOG.has_actor_half_extents(type_id) == is_actor,
			"Actor extent presence drifted for '%s'." % type_id
		)
		_expect(
			(CATALOG.actor_half_extents(type_id) != Vector2i.ZERO) == is_actor,
			"Actor extent value drifted for '%s'." % type_id
		)
	for type_id: String in actors:
		_expect(
			CATALOG.actor_half_extents(type_id) == EXPECTED_ACTOR_EXTENTS[type_id],
			"Actor extents changed for '%s'." % type_id
		)
	for type_id: String in enemies:
		_expect(actors.has(type_id), "Enemy '%s' is not classified as an actor." % type_id)


func _test_copy_contract() -> void:
	var supported: Array[String] = CATALOG.supported_types()
	var expected_supported := supported.duplicate()
	supported.clear()
	_expect(
		CATALOG.supported_types() == expected_supported,
		"supported_types() exposed mutable catalog state."
	)
	for category: LevelObjectCatalog.Category in CATEGORIES:
		var entries: Array[String] = CATALOG.category_types(category)
		var expected_entries := entries.duplicate()
		entries.clear()
		_expect(
			CATALOG.category_types(category) == expected_entries,
			"category_types(%s) exposed mutable catalog state." % category
		)


func _test_fixture_contract(fixture: Dictionary) -> void:
	var fixture_types: Array[String] = []
	for object: Dictionary in fixture["objects"]:
		fixture_types.append(str(object["type"]))
	var supported: Array[String] = CATALOG.supported_types()
	_expect(fixture_types.size() == supported.size(), "All-types fixture has the wrong object count.")
	_expect(
		_string_set(fixture_types).size() == fixture_types.size(),
		"All-types fixture repeats a type."
	)
	_expect(
		_same_string_set(fixture_types, supported),
		"All-types fixture does not match the catalog."
	)


func _test_builder(data: Dictionary) -> void:
	var arena := _builder_arena()
	var result: Dictionary = BUILDER.build_into(arena, data)
	_expect(
		bool(result.get("ok", false)),
		"Builder rejected the all-types fixture: %s"
		% [result.get("errors", [])]
	)
	var objects: Dictionary = result.get("objects", {})
	_expect(
		objects.size() == CATALOG.supported_types().size(),
		"Builder did not create one object per catalog type."
	)
	for definition: Dictionary in data["objects"]:
		_expect(objects.has(definition["id"]), "Builder omitted '%s'." % definition["id"])
	arena.free()


func _builder_arena() -> BuilderArena:
	var arena := BuilderArena.new()
	var geometry := Node2D.new()
	geometry.name = "Geometry"
	arena.add_child(geometry)
	var level_objects := Node2D.new()
	level_objects.name = "LevelObjects"
	geometry.add_child(level_objects)
	var actors := Node2D.new()
	actors.name = "Actors"
	arena.add_child(actors)
	return arena


func _test_editor_and_canvas(data: Dictionary) -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	await process_frame
	for object: Dictionary in data["objects"]:
		_test_editor_type(editor, object, data)
	editor.queue_free()
	await editor.tree_exited


func _test_editor_type(editor: LevelEditor, object: Dictionary, data: Dictionary) -> void:
	editor.draft.replace(data, true)
	var type_id := str(object["type"])
	editor.call("_set_tool", type_id)
	var button := editor.call("_palette_button_for_tool", type_id) as Button
	_expect(is_instance_valid(button), "Editor palette omitted '%s'." % type_id)
	_expect(
		editor.active_tool == type_id
		and str(editor.canvas.get("_tool")) == type_id,
		"Editor or canvas rejected tool '%s'." % type_id
	)
	var payload: Variant = editor.canvas.call("_payload_for_object", object)
	_expect(payload != null, "Canvas cannot move '%s'." % type_id)
	var bounds: Rect2 = editor.canvas.call("_bounds_for_object", object)
	_expect(bounds.size != Vector2.ZERO, "Canvas has no bounds for '%s'." % type_id)
	_test_hinge_classification(editor, type_id)
	editor.call("_place_object", type_id, payload)
	var placed := editor.draft.find_object(editor.selected_id)
	_expect(placed.get("type", "") == type_id, "Editor has no placement handler for '%s'." % type_id)


func _test_hinge_classification(editor: LevelEditor, type_id: String) -> void:
	var expected := CATALOG.is_in_category(type_id, CATALOG.Category.HINGE_TARGET)
	var editor_result := bool(editor.call("_is_hinge_target_type", type_id))
	var canvas_result := bool(editor.canvas.call("_is_hinge_target_type", type_id))
	_expect(
		editor_result == expected and canvas_result == expected,
		"Hinge-target classification drifted for '%s'." % type_id
	)


func _test_canvas_order(order: Array, label: String) -> void:
	var supported: Array[String] = CATALOG.supported_types()
	_expect(order.size() == supported.size(), "Canvas %s order has the wrong size." % label)
	_expect(_string_set(order).size() == order.size(), "Canvas %s order repeats a type." % label)
	_expect(_same_string_set(order, supported), "Canvas %s order does not cover the catalog." % label)


func _test_validation_messages(fixture: Dictionary) -> void:
	var unknown := fixture.duplicate(true)
	unknown["objects"][0]["type"] = "unknown_object"
	var unknown_result: Dictionary = VALIDATOR.validate_and_normalize(unknown)
	var expected_unknown := [
		"root.objects[0].type 'unknown_object' is not supported.",
	]
	_expect(
		unknown_result.get("errors", []) == expected_unknown,
		"Unknown-type validation message drifted: %s"
		% [unknown_result.get("errors", [])]
	)
	var wrong_target := fixture.duplicate(true)
	_object_by_id(wrong_target, "hinge")["target_id"] = "player_start"
	var target_result: Dictionary = VALIDATOR.validate_and_normalize(wrong_target)
	var expected_target := [
		(
			"Hinge 'hinge' target 'player_start' must be a supported "
			+ "mechanism; got 'player_spawn'."
		),
	]
	_expect(
		target_result.get("errors", []) == expected_target,
		"Hinge-target validation message drifted: %s"
		% [target_result.get("errors", [])]
	)


func _fixture() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "level_object_catalog_smoke",
		"title": "LEVEL OBJECT CATALOG SMOKE",
		"objective": "VERIFY THE CATALOG",
		"clear_message": "CLEAR",
		"canvas": {"width": 960, "height": 540, "grid_size": 20},
		"objects": _fixture_objects(),
	}


func _fixture_objects() -> Array[Dictionary]:
	var objects: Array[Dictionary] = [
		{"id": "floor", "type": CATALOG.TYPE_SOLID_RECT, "rect": [32, 496, 896, 44]},
		{"id": "spikes", "type": CATALOG.TYPE_SPIKE_TRAP, "rect": [400, 476, 80, 20]},
		{"id": "player_start", "type": CATALOG.TYPE_PLAYER_SPAWN, "position": [100, 450]},
		{"id": "patrol", "type": CATALOG.TYPE_PATROL_ENEMY, "position": [220, 450]},
		{"id": "shove", "type": CATALOG.TYPE_SHOVE_ENEMY, "position": [300, 450]},
		{"id": "shooter", "type": CATALOG.TYPE_SHOOTER_ENEMY, "position": [780, 450]},
		{"id": "catapult", "type": CATALOG.TYPE_CATAPULT_PLATFORM, "position": [40, 300]},
		{"id": "lift", "type": CATALOG.TYPE_VERTICAL_PLATFORM, "position": [860, 100]},
		{"id": "double_jump", "type": CATALOG.TYPE_DOUBLE_JUMP_PICKUP, "position": [360, 200]},
		{"id": "bridge", "type": CATALOG.TYPE_TOGGLE_PLATFORM, "rect": [520, 400, 120, 20]},
		{"id": "gate", "type": CATALOG.TYPE_TOGGLE_WALL, "rect": [700, 300, 20, 140]},
		{"id": "hinge", "type": CATALOG.TYPE_HINGE, "position": [480, 300], "target_id": "bridge"},
	]
	return objects


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _string_set(values: Array) -> Dictionary:
	var result := {}
	for value: Variant in values:
		result[str(value)] = true
	return result


func _same_string_set(first: Array, second: Array) -> bool:
	var first_set := _string_set(first)
	var second_set := _string_set(second)
	if first_set.size() != second_set.size():
		return false
	for value: Variant in first_set:
		if not second_set.has(value):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("LEVEL_OBJECT_CATALOG_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

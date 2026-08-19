extends SceneTree

const VALIDATOR := preload("res://scripts/levels/level_data_validator.gd")
const CODEC := preload("res://scripts/levels/level_data_codec.gd")
const CATALOG := preload("res://scripts/levels/level_object_catalog.gd")
const BUILDER := preload("res://scripts/levels/level_builder.gd")
const RUNTIME_SCENE := preload("res://scenes/level_runtime_arena.tscn")
const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const PLATE_SCENE := preload("res://scenes/pressure_plate.tscn")
const TOGGLE_SCENE := preload("res://scenes/toggle_platform.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_contract()
	_test_schema_and_round_trip()
	_test_schema_geometry()
	_test_schema_links()
	_test_schema_placements()
	_test_builder_link()
	await _test_editor_embedded_playtest()
	await _test_single_occupants()
	await _test_mixed_occupancy_and_free()
	await _test_rapid_coalescing()
	await _test_blocked_wall_edge()
	_finish()


func _test_catalog_contract() -> void:
	_expect(
		CATALOG.is_supported_type(CATALOG.TYPE_PRESSURE_PLATE)
		and CATALOG.is_in_category(
			CATALOG.TYPE_PRESSURE_PLATE, CATALOG.Category.RECT
		),
		"Catalog did not classify pressure_plate as a supported rect."
	)
	var targets: Array[String] = CATALOG.category_types(
		CATALOG.Category.PRESSURE_TARGET
	)
	_expect(
		targets.has(CATALOG.TYPE_TOGGLE_PLATFORM)
		and targets.has(CATALOG.TYPE_TOGGLE_WALL)
		and targets.size() == 2,
		"Pressure-target category drifted: %s" % [targets]
	)
	for category: LevelObjectCatalog.Category in [
		CATALOG.Category.SUPPORT,
		CATALOG.Category.HINGE_TARGET,
		CATALOG.Category.PROJECTILE_BLOCKER,
	]:
		_expect(
			not CATALOG.is_in_category(CATALOG.TYPE_PRESSURE_PLATE, category),
			"pressure_plate leaked into catalog category %s." % category
		)


func _test_schema_and_round_trip() -> void:
	var validation: Dictionary = VALIDATOR.validate_and_normalize(_fixture())
	_expect(bool(validation.get("ok", false)), "Valid pressure_plate was rejected: %s" % [validation.get("errors", [])])
	if not bool(validation.get("ok", false)):
		return
	var plate := _object_by_id(validation["data"], "plate")
	var keys: Array = plate.keys()
	keys.sort()
	_expect(
		keys == ["active_while_pressed", "id", "rect", "target_id", "type"],
		"Canonical pressure_plate keys drifted: %s" % [keys]
	)
	var first: Dictionary = CODEC.encode(validation["data"])
	var decoded: Dictionary = CODEC.decode_text(str(first.get("text", "")))
	var second: Dictionary = CODEC.encode(decoded.get("data", {}))
	_expect(
		bool(first.get("ok", false)) and bool(decoded.get("ok", false))
		and first.get("text") == second.get("text"),
		"pressure_plate did not survive deterministic JSON round-trip."
	)


func _test_schema_geometry() -> void:
	var narrow := _fixture()
	_object_by_id(narrow, "plate")["rect"] = [340, 476, 39, 20]
	_expect_invalid(narrow, "width must be at least 40", "narrow plate")
	var tall := _fixture()
	_object_by_id(tall, "plate")["rect"] = [340, 476, 100, 21]
	_expect_invalid(tall, "height must be exactly 20", "tall plate")
	var outside := _fixture()
	_object_by_id(outside, "plate")["rect"] = [20, 476, 100, 20]
	_expect_invalid(outside, "runtime playfield", "out-of-playfield plate")
	var unknown := _fixture()
	_object_by_id(unknown, "plate")["pressed"] = false
	_expect_invalid(unknown, "unknown key 'pressed'", "open-ended plate")
	var missing_state := _fixture()
	_object_by_id(missing_state, "plate").erase("active_while_pressed")
	_expect_invalid(missing_state, "missing required key 'active_while_pressed'", "missing held state")


func _test_schema_links() -> void:
	var missing := _fixture()
	_object_by_id(missing, "plate")["target_id"] = "missing"
	_expect_invalid(missing, "targets missing object 'missing'", "missing target")
	var self_target := _fixture()
	_object_by_id(self_target, "plate")["target_id"] = "plate"
	_expect_invalid(self_target, "must not target itself", "self target")
	var incompatible := _fixture()
	_object_by_id(incompatible, "plate")["target_id"] = "floor"
	_expect_invalid(incompatible, "must be a toggle platform or wall", "solid target")
	var wrong_initial := _fixture()
	_object_by_id(wrong_initial, "bridge")["starts_active"] = true
	_expect_invalid(wrong_initial, "unpressed state", "wrong target initial state")
	_test_controller_conflicts()


func _test_controller_conflicts() -> void:
	var duplicate := _fixture()
	duplicate["objects"].append(_plate("plate_2", [440, 476, 80, 20]))
	_expect_invalid(duplicate, "both target 'bridge'", "duplicate pressure target")
	var mixed := _fixture()
	mixed["objects"].append(
		{"id": "hinge", "type": "hinge", "position": [300, 300], "target_id": "bridge"}
	)
	_expect_invalid(mixed, "mixed hinge", "mixed hinge and pressure control")


func _test_schema_placements() -> void:
	var on_plate := _fixture()
	_object_by_id(on_plate, "player")["position"] = [370, 456]
	_object_by_id(on_plate, "patrol")["position"] = [410, 458]
	var validation: Dictionary = VALIDATOR.validate_and_normalize(on_plate)
	_expect(
		bool(validation.get("ok", false)),
		"Player/enemy start on pressure_plate was rejected: %s" % [validation.get("errors", [])]
	)
	var spikes := _fixture()
	spikes["objects"].append(
		{"id": "spikes", "type": "spike_trap", "rect": [340, 476, 100, 20]}
	)
	_expect_invalid(spikes, "overlaps pressure_plate 'plate'", "spike overlap")


func _test_builder_link() -> void:
	var validation: Dictionary = VALIDATOR.validate_and_normalize(_fixture())
	if not bool(validation.get("ok", false)):
		_expect(false, "Builder fixture validation failed: %s" % [validation.get("errors", [])])
		return
	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	var result: Dictionary = BUILDER.build_into(
		arena, validation.get("data", {})
	)
	var objects: Dictionary = result.get("objects", {})
	var plate := objects.get("plate") as PressurePlate
	var target := objects.get("bridge") as TogglePlatform
	var cable := arena.get_node_or_null(
		"Geometry/LevelObjects/PressureLink_plate"
	) as Line2D
	_expect(
		bool(result.get("ok", false))
		and is_instance_valid(plate)
		and plate.target == target
		and is_instance_valid(cable)
		and cable.points.size() == 2
		and cable.default_color.a > 0.0,
		"Builder did not resolve pressure_plate target and visible cable."
	)
	arena.free()


func _test_editor_embedded_playtest() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame
	editor.draft.replace(_fixture(), true)
	await process_frame
	_expect(
		bool(editor.validation_result.get("ok", false)),
		"Editor rejected the pressure_plate fixture."
	)
	editor.call("_start_playtest")
	await process_frame
	await physics_frame
	var runtime := editor.playtest_runtime as LevelRuntimeArena
	await _verify_editor_runtime(runtime)
	if is_instance_valid(runtime):
		editor.call("_stop_playtest")
		await process_frame
	current_scene = null
	editor.queue_free()
	await editor.tree_exited


func _verify_editor_runtime(runtime: LevelRuntimeArena) -> void:
	var plate := runtime.get_level_object("plate") as PressurePlate if is_instance_valid(runtime) else null
	var target := runtime.get_level_object("bridge") as TogglePlatform if is_instance_valid(runtime) else null
	var player := runtime.get_level_object("player") as Player if is_instance_valid(runtime) else null
	var cable := runtime.get_node_or_null(
		"Geometry/LevelObjects/PressureLink_plate"
	) as Line2D if is_instance_valid(runtime) else null
	_expect(
		is_instance_valid(runtime) and runtime.level_loaded
		and is_instance_valid(plate) and plate.target == target
		and is_instance_valid(player) and is_instance_valid(cable),
		"Editor embedded playtest lost pressure_plate, target, or cable."
	)
	if not is_instance_valid(plate) or not is_instance_valid(target):
		return
	target.transition_time = 0.01
	plate.body_entered.emit(player)
	await _wait_for_toggle(target)
	_expect(plate.is_pressed and target.is_active, "Embedded playtest press did not activate target.")
	plate.body_exited.emit(player)
	await _wait_for_toggle(target)
	_expect(not plate.is_pressed and not target.is_active, "Embedded playtest release did not restore target.")


func _test_single_occupants() -> void:
	await _test_single_occupant("player", "Player")
	await _test_single_occupant("enemies", "Enemy")


func _test_single_occupant(group_name: String, label: String) -> void:
	var pair := _runtime_pair(false)
	var plate: PressurePlate = pair["plate"]
	var target: TogglePlatform = pair["target"]
	var actor := _actor(group_name)
	root.add_child(actor)
	await process_frame
	plate.body_entered.emit(actor)
	await _wait_for_toggle(target)
	_expect(
		plate.is_pressed and plate.occupant_count() == 1 and target.is_active,
		"%s alone did not press and hold the plate." % label
	)
	plate.body_exited.emit(actor)
	await _wait_for_toggle(target)
	_expect(
		not plate.is_pressed and plate.occupant_count() == 0 and not target.is_active,
		"%s exit did not release the plate." % label
	)
	await _free_nodes([actor, plate, target])


func _test_mixed_occupancy_and_free() -> void:
	var pair := _runtime_pair(false)
	var plate: PressurePlate = pair["plate"]
	var target: TogglePlatform = pair["target"]
	await process_frame
	var player := _actor("player")
	var enemy := _actor("enemies")
	var projectile := _actor("")
	for body: CharacterBody2D in [player, enemy, projectile]:
		root.add_child(body)
	plate.body_entered.emit(projectile)
	plate.body_entered.emit(player)
	plate.body_entered.emit(player)
	plate.body_entered.emit(enemy)
	await _wait_for_toggle(target)
	_expect(plate.is_pressed and plate.occupant_count() == 2 and target.is_active, "Mixed occupancy did not hold the target active.")
	plate.body_exited.emit(player)
	_expect(plate.is_pressed and plate.occupant_count() == 1, "First exit released a multiply occupied plate.")
	enemy.queue_free()
	await enemy.tree_exited
	await _wait_for_toggle(target)
	_expect(not plate.is_pressed and plate.occupant_count() == 0 and not target.is_active, "Freed last enemy did not release the plate.")
	await _free_nodes([player, projectile, plate, target])


func _test_rapid_coalescing() -> void:
	var pair := _runtime_pair(false)
	var plate: PressurePlate = pair["plate"]
	var target: TogglePlatform = pair["target"]
	var actor := _actor("player")
	root.add_child(actor)
	await process_frame
	plate.body_entered.emit(actor)
	plate.body_exited.emit(actor)
	await _wait_for_toggle(target)
	_expect(not plate.is_pressed and not target.is_active, "Enter/exit did not coalesce to released state.")
	plate.body_entered.emit(actor)
	plate.body_exited.emit(actor)
	plate.body_entered.emit(actor)
	await _wait_for_toggle(target)
	_expect(plate.is_pressed and target.is_active, "Latest rapid occupancy state did not win.")
	await _free_nodes([actor, plate, target])


func _test_blocked_wall_edge() -> void:
	var pair := _runtime_pair(true)
	var plate: PressurePlate = pair["plate"]
	var wall: TogglePlatform = pair["target"]
	var actor := _wall_probe()
	var left := _blocker(Vector2(449, 340))
	var right := _blocker(Vector2(491, 340))
	for node: Node in [actor, left, right]:
		root.add_child(node)
	await physics_frame
	var blocked := {"count": 0}
	wall.toggle_blocked.connect(func() -> void: blocked["count"] += 1)
	plate.body_entered.emit(actor)
	await _wait_for_toggle(wall)
	_expect(not wall.is_active and blocked["count"] == 1, "Blocked pressure close did not cancel atomically.")
	for _frame in 10:
		await process_frame
	_expect(blocked["count"] == 1 and not wall.is_transitioning, "Blocked close retried without an occupancy edge.")
	plate.body_exited.emit(actor)
	left.queue_free()
	right.queue_free()
	await process_frame
	await physics_frame
	plate.body_entered.emit(actor)
	await _wait_for_toggle(wall)
	_expect_wall_retry(wall, actor, blocked)
	await _free_nodes([actor, plate, wall])


func _expect_wall_retry(
	wall: TogglePlatform,
	actor: CharacterBody2D,
	blocked: Dictionary
) -> void:
	_expect(
		wall.is_active and blocked["count"] == 1
		and absf(actor.position.x - 470.0) > 15.0,
		"New edge did not retry wall close with ejection: active=%s x=%s blocked=%s."
		% [wall.is_active, actor.position.x, blocked["count"]]
	)


func _runtime_pair(vertical_wall: bool) -> Dictionary:
	var target := TOGGLE_SCENE.instantiate() as TogglePlatform
	target.transition_time = 0.01
	target.blocked_feedback_time = 0.01
	var rect := Rect2(460, 300, 20, 160) if vertical_wall else Rect2(520, 416, 160, 20)
	target.configure(rect, false, vertical_wall)
	var plate := PLATE_SCENE.instantiate() as PressurePlate
	plate.configure(Rect2(340, 476, 100, 20), true)
	plate.configure_target(target)
	root.add_child(plate)
	root.add_child(target)
	return {"plate": plate, "target": target}


func _actor(group_name: String) -> CharacterBody2D:
	var actor := CharacterBody2D.new()
	if not group_name.is_empty():
		actor.add_to_group(group_name)
	return actor


func _wall_probe() -> CharacterBody2D:
	var probe := _actor("player")
	probe.position = Vector2(466, 340)
	probe.collision_layer = 2
	probe.collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 8)
	collision.shape = shape
	probe.add_child(collision)
	return probe


func _blocker(position: Vector2) -> StaticBody2D:
	var blocker := StaticBody2D.new()
	blocker.position = position
	blocker.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 40)
	collision.shape = shape
	blocker.add_child(collision)
	return blocker


func _wait_for_toggle(toggle: TogglePlatform) -> void:
	for _frame in 60:
		await process_frame
		await physics_frame
		if not toggle.is_transitioning:
			return
	_expect(false, "Toggle transition did not finish.")


func _free_nodes(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _expect_invalid(data: Dictionary, needle: String, label: String) -> void:
	var result: Dictionary = VALIDATOR.validate_and_normalize(data)
	var joined := "\n".join(result.get("errors", []))
	_expect(
		not bool(result.get("ok", false)) and joined.contains(needle),
		"Validator accepted %s or missed '%s': %s" % [label, needle, joined]
	)


func _fixture() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "pressure_plate_smoke",
		"title": "PRESSURE PLATE SMOKE",
		"canvas": {"width": 960, "height": 540, "grid_size": 20},
		"objects": [
			{"id": "floor", "type": "solid_rect", "rect": [32, 496, 896, 44]},
			{"id": "player", "type": "player_spawn", "position": [100, 450]},
			{"id": "patrol", "type": "patrol_enemy", "position": [220, 450], "speed": 20},
			{"id": "bridge", "type": "toggle_platform", "rect": [520, 416, 160, 20], "starts_active": false},
			_plate("plate", [340, 476, 100, 20]),
		],
	}


func _plate(object_id: String, rect: Array) -> Dictionary:
	return {
		"id": object_id,
		"type": "pressure_plate",
		"rect": rect,
		"target_id": "bridge",
		"active_while_pressed": true,
	}


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PRESSURE_PLATE_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

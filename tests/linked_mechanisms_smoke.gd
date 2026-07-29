extends SceneTree

const RUNTIME_SCENE := preload(
	"res://scenes/data_arena_01.tscn"
)
const LEGACY_ARENA_02_SCENE := preload(
	"res://scenes/arena_02.tscn"
)
const TOGGLE_PLATFORM_SCENE := preload(
	"res://scenes/toggle_platform.tscn"
)
const HINGE_SCENE := preload("res://scenes/hinge.tscn")
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const LEVEL_BUILDER := preload(
	"res://scripts/levels/level_builder.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_canonical_validation()
	_test_invalid_links()
	_test_link_warnings_and_fan_in()
	_test_builder_rolls_back_invalid_links()
	await _test_toggle_lifecycle()
	await _test_legacy_target_path()
	await _test_builder_and_real_attack()

	if failures.is_empty():
		print("LINKED_MECHANISMS_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_canonical_validation() -> void:
	var forward_reference := _make_linked_level()
	var bridge := _object_by_id(forward_reference, "center_bridge")
	bridge.erase("starts_active")

	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			forward_reference
		)
	)
	_expect(
		bool(result["ok"]),
		(
			"Validator rejected a forward hinge reference or the "
			+ "starts_active default: %s"
		)
		% str(result["errors"])
	)
	if not bool(result["ok"]):
		return

	var normalized: Dictionary = result["data"]
	var normalized_hinge := _object_by_id(normalized, "bridge_hinge")
	var normalized_bridge := _object_by_id(normalized, "center_bridge")
	_expect(
		normalized_hinge.get("target_id", "") == "center_bridge",
		"Canonical data changed the hinge target ID."
	)
	_expect(
		normalized_bridge.get("starts_active") == true,
		"An omitted starts_active value did not default to true."
	)
	_expect(
		_object_index(normalized, "bridge_hinge")
		< _object_index(normalized, "center_bridge"),
		"Normalization reordered the forward hinge reference."
	)

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(normalized)
	_expect(
		bool(encoded["ok"]),
		"Canonical linked-mechanism data could not be encoded."
	)
	if not bool(encoded["ok"]):
		return

	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		encoded["text"]
	)
	var reencoded: Dictionary = (
		LEVEL_DATA_CODEC.encode(decoded.get("data", {}))
	)
	_expect(
		bool(decoded["ok"])
		and bool(reencoded["ok"])
		and reencoded["text"] == encoded["text"]
		and _object_by_id(
			decoded["data"],
			"bridge_hinge"
		).get("target_id", "") == "center_bridge"
		and _object_by_id(
			decoded["data"],
			"center_bridge"
		).get("starts_active") == true,
		"Codec round-trip changed the canonical mechanism link."
	)


func _test_invalid_links() -> void:
	var missing_target := _make_linked_level()
	_object_by_id(missing_target, "bridge_hinge").erase("target_id")
	_expect_invalid(missing_target, "hinge without target_id")

	var unknown_target := _make_linked_level()
	_object_by_id(
		unknown_target,
		"bridge_hinge"
	)["target_id"] = "missing_bridge"
	_expect_invalid(unknown_target, "hinge with unknown target_id")

	var wrong_target_type := _make_linked_level()
	_object_by_id(
		wrong_target_type,
		"bridge_hinge"
	)["target_id"] = "left_floor"
	_expect_invalid(
		wrong_target_type,
		"hinge targeting a non-toggle object"
	)

	var self_target := _make_linked_level()
	_object_by_id(
		self_target,
		"bridge_hinge"
	)["target_id"] = "bridge_hinge"
	_expect_invalid(self_target, "self-targeting hinge")

	var wrong_active_type := _make_linked_level()
	_object_by_id(
		wrong_active_type,
		"center_bridge"
	)["starts_active"] = "yes"
	_expect_invalid(
		wrong_active_type,
		"toggle platform with non-boolean starts_active"
	)

	var wrong_height := _make_linked_level()
	_object_by_id(
		wrong_height,
		"center_bridge"
	)["rect"] = [400, 496, 160, 40]
	_expect_invalid(wrong_height, "toggle platform with non-fixed height")
	var wrong_height_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(wrong_height)
	)
	_expect(
		not _contains_text(
			wrong_height_result["errors"],
			"targets missing object"
		),
		"An invalid declared target was misleadingly reported as absent."
	)

	var too_narrow := _make_linked_level()
	_object_by_id(
		too_narrow,
		"center_bridge"
	)["rect"] = [400, 496, 10, 20]
	_expect_invalid(too_narrow, "toggle platform narrower than 20px")

	var clipped_hinge := _make_linked_level()
	_object_by_id(
		clipped_hinge,
		"bridge_hinge"
	)["position"] = [40, 100]
	_expect_invalid(
		clipped_hinge,
		"hinge collider clipping the immutable wall"
	)

	var clipped_platform := _make_linked_level()
	_object_by_id(
		clipped_platform,
		"center_bridge"
	)["rect"] = [20, 496, 180, 20]
	_expect_invalid(
		clipped_platform,
		"toggle platform collider clipping the immutable wall"
	)

	var injected_node_path := _make_linked_level()
	_object_by_id(
		injected_node_path,
		"bridge_hinge"
	)["target_path"] = "../CenterBridge"
	_expect_invalid(
		injected_node_path,
		"hinge with injected target_path"
	)

	var spawn_inside_active_toggle := _make_linked_level()
	_object_by_id(
		spawn_inside_active_toggle,
		"player_start"
	)["position"] = [480, 477]
	_expect_invalid(
		spawn_inside_active_toggle,
		"player collider overlapping an active toggle platform"
	)
	_object_by_id(
		spawn_inside_active_toggle,
		"center_bridge"
	)["starts_active"] = false
	var inactive_overlap_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			spawn_inside_active_toggle
		)
	)
	_expect(
		bool(inactive_overlap_result["ok"]),
		"An inactive toggle platform blocked an actor spawn."
	)


func _test_link_warnings_and_fan_in() -> void:
	var unlinked_platform := _make_linked_level()
	var objects: Array = unlinked_platform["objects"]
	objects.remove_at(_object_index(unlinked_platform, "bridge_hinge"))
	var unlinked_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			unlinked_platform
		)
	)
	_expect(
		bool(unlinked_result["ok"])
		and _contains_text(
			unlinked_result["warnings"],
			"no controlling hinge"
		),
		"An unlinked toggle platform did not produce a warning."
	)

	var inactive_support := _make_linked_level()
	_object_by_id(
		inactive_support,
		"center_bridge"
	)["starts_active"] = false
	var inactive_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			inactive_support
		)
	)
	_expect(
		bool(inactive_result["ok"])
		and _contains_text(
			inactive_result["warnings"],
			"patrol_1"
		)
		and _contains_text(
			inactive_result["warnings"],
			"no solid support"
		),
		"An inactive toggle platform was incorrectly counted as support."
	)

	var fan_in := _make_linked_level()
	fan_in["objects"].append(
		{
			"id": "bridge_hinge_2",
			"type": "hinge",
			"position": [610, 420],
			"target_id": "center_bridge",
		}
	)
	var fan_in_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(fan_in)
	)
	_expect(
		bool(fan_in_result["ok"]),
		"Validator rejected two hinges controlling one platform."
	)


func _test_builder_rolls_back_invalid_links() -> void:
	var invalid_build := _make_linked_level()
	invalid_build["objects"].append(
		{
			"id": "broken_hinge",
			"type": "hinge",
			"position": [610, 420],
			"target_id": "missing_bridge",
		}
	)

	var arena := Node2D.new()
	var geometry := Node2D.new()
	geometry.name = "Geometry"
	arena.add_child(geometry)
	var level_objects := Node2D.new()
	level_objects.name = "LevelObjects"
	geometry.add_child(level_objects)
	var actors := Node2D.new()
	actors.name = "Actors"
	arena.add_child(actors)

	var result: Dictionary = LEVEL_BUILDER.build_into(
		arena,
		invalid_build
	)
	_expect(
		not bool(result["ok"])
		and level_objects.get_child_count() == 0
		and actors.get_child_count() == 0,
		"Builder left a partially assembled arena after a bad link."
	)
	arena.free()


func _test_toggle_lifecycle() -> void:
	var bridge := (
		TOGGLE_PLATFORM_SCENE.instantiate() as TogglePlatform
	)
	var hinge := HINGE_SCENE.instantiate() as Hinge
	bridge.configure(Rect2(300, 300, 220, 20), false)
	hinge.position = Vector2(250, 310)
	hinge.configure_target(bridge)
	root.add_child(bridge)
	root.add_child(hinge)
	await process_frame
	await physics_frame

	_expect(
		not bridge.is_active
		and bridge.collision_shape.disabled
		and bridge.body_visual.color
		== TogglePlatform.INACTIVE_BODY_COLOR,
		"Runtime did not apply an inactive platform's initial state."
	)

	hinge.receive_impulse(Vector2.ZERO)
	for _frame in 60:
		await process_frame
		await physics_frame
		if bridge.is_active and hinge.is_ready:
			break
	_expect(
		bridge.is_active
		and not bridge.collision_shape.disabled
		and hinge.is_ready,
		"First hinge activation did not enable and unlock the platform."
	)

	hinge.receive_impulse(Vector2.ZERO)
	for _frame in 60:
		await process_frame
		await physics_frame
		if not bridge.is_active and hinge.is_ready:
			break
	_expect(
		not bridge.is_active
		and bridge.collision_shape.disabled
		and hinge.is_ready,
		"Second hinge activation did not disable and unlock the platform."
	)

	hinge.queue_free()
	bridge.queue_free()
	await process_frame


func _test_legacy_target_path() -> void:
	var arena := LEGACY_ARENA_02_SCENE.instantiate()
	root.add_child(arena)
	await process_frame
	var hinge := arena.get_node("Hinge") as Hinge
	var bridge := arena.get_node("TogglePlatform") as TogglePlatform
	_expect(
		hinge.target == bridge,
		"Legacy Arena 02 target_path no longer resolves its platform."
	)
	arena.queue_free()
	await process_frame


func _test_builder_and_real_attack() -> void:
	var normalized_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			_make_linked_level()
		)
	)
	_expect(
		bool(normalized_result["ok"]),
		"Could not prepare the runtime mechanism fixture."
	)
	if not bool(normalized_result["ok"]):
		return

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(
		normalized_result["data"]
	)
	_expect(
		bool(encoded["ok"]),
		"Could not encode the runtime mechanism fixture."
	)
	if not bool(encoded["ok"]):
		return

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(encoded["text"])
	arena.clear_restart_delay = 10.0
	root.add_child(arena)
	current_scene = arena
	await process_frame

	_expect(arena.level_loaded, "Runtime did not build the linked level.")
	if not arena.level_loaded:
		await _cleanup_current_scene()
		return

	var hinge := (
		arena.get_level_object("bridge_hinge") as Hinge
	)
	var bridge := (
		arena.get_level_object("center_bridge") as TogglePlatform
	)
	var player := (
		arena.get_level_object("player_start") as Player
	)
	var enemy := (
		arena.get_level_object("patrol_1") as PatrolEnemy
	)
	var cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_bridge_hinge"
	) as Line2D

	_expect(
		is_instance_valid(hinge)
		and is_instance_valid(bridge)
		and is_instance_valid(player)
		and is_instance_valid(enemy)
		and is_instance_valid(cable),
		"Builder did not create every linked-level object."
	)
	if (
		not is_instance_valid(hinge)
		or not is_instance_valid(bridge)
		or not is_instance_valid(player)
		or not is_instance_valid(enemy)
		or not is_instance_valid(cable)
	):
		await _cleanup_current_scene()
		return

	_expect(
		hinge.target == bridge,
		"Builder did not resolve the forward hinge target."
	)
	_expect(
		hinge.get_parent() == arena.get_node("Geometry/LevelObjects")
		and bridge.get_parent()
		== arena.get_node("Geometry/LevelObjects"),
		"Builder placed a mechanism outside generated geometry."
	)
	_expect(
		is_instance_valid(cable)
		and cable.points.size() == 2
		and cable.points[0].is_equal_approx(hinge.position)
		and cable.points[1].is_equal_approx(bridge.position),
		"Builder did not draw the resolved runtime link."
	)
	_expect(
		bridge.position.is_equal_approx(Vector2(480, 506)),
		"Builder did not place the toggle platform at its rect center."
	)
	var bridge_shape := (
		bridge.get_node("CollisionShape2D") as CollisionShape2D
	).shape as RectangleShape2D
	var hinge_shape := (
		hinge.get_node("CollisionShape2D") as CollisionShape2D
	).shape as CircleShape2D
	_expect(
		is_instance_valid(bridge_shape)
		and bridge_shape.size.is_equal_approx(Vector2(180, 20)),
		"Builder did not apply the toggle platform rect size."
	)
	_expect(
		is_instance_valid(hinge_shape)
		and is_equal_approx(
			hinge_shape.radius,
			float(LEVEL_DATA_VALIDATOR.HINGE_RADIUS)
		),
		"Validator hinge bounds drifted from the runtime collider."
	)
	_expect(
		bridge.starts_active
		and bridge.is_active
		and not bridge.collision_shape.disabled,
		"An active toggle platform was built without collision."
	)

	for _frame in range(45):
		await physics_frame

	_expect(
		player.is_on_floor()
		and absf(player.global_position.y - 476.0) <= 1.0,
		"Player did not settle beside the hinge."
	)
	_expect(
		enemy.is_on_floor()
		and absf(enemy.global_position.y - 478.0) <= 1.0,
		"Patrol did not settle on the generated toggle platform."
	)

	await _press_physical_key(KEY_X)
	for _frame in range(90):
		await physics_frame
		if not bridge.is_active and not bridge.is_transitioning:
			break

	_expect(
		not bridge.is_active
		and bridge.collision_shape.disabled,
		"A physical player attack did not switch the linked bridge off."
	)

	for _frame in range(240):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame

	_expect(
		arena.enemies_remaining == 0,
		"The patrol did not fall after its linked bridge switched off."
	)
	_expect(
		arena.pending_outcome == Arena.Outcome.CLEAR,
		"The mechanism-driven enemy fall did not produce CLEAR."
	)
	await _cleanup_current_scene()


func _make_linked_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "linked_mechanisms_smoke",
		"title": "LINKED MECHANISMS SMOKE",
		"objective": "SWITCH THE BRIDGE OFF",
		"clear_message": "LINKED LEVEL CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "bridge_hinge",
				"type": "hinge",
				"position": [350, 476],
				"target_id": "center_bridge",
			},
			{
				"id": "left_floor",
				"type": "solid_rect",
				"rect": [32, 496, 340, 44],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [300, 450],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [480, 450],
				"speed": 0,
				"direction": 1,
			},
			{
				"id": "center_bridge",
				"type": "toggle_platform",
				"rect": [390, 496, 180, 20],
				"starts_active": true,
			},
		],
	}


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _object_index(data: Dictionary, object_id: String) -> int:
	var objects: Array = data.get("objects", [])
	for index in objects.size():
		var object: Dictionary = objects[index]
		if object.get("id", "") == object_id:
			return index
	return -1


func _press_physical_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	await physics_frame

	var release := InputEventKey.new()
	release.physical_keycode = key
	release.keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _cleanup_current_scene() -> void:
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	Input.action_release("ui_accept")
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame


func _expect_invalid(data: Dictionary, label: String) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(not bool(result["ok"]), "Validator accepted %s." % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _contains_text(values: Array, fragment: String) -> bool:
	for value: Variant in values:
		if fragment in str(value):
			return true
	return false

extends SceneTree

const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)
const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
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
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_builtin_arena_02_fixture()
	_test_canonical_validation()
	_test_invalid_links()
	_test_link_warnings_and_fan_in()
	_test_builder_rolls_back_invalid_links()
	await _test_toggle_lifecycle()
	await _test_arena_02_builder_and_real_clear()
	await _test_arena_02_editor_lifecycle()

	if failures.is_empty():
		print("LINKED_MECHANISMS_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_builtin_arena_02_fixture() -> void:
	var builtins := LEVEL_STORAGE.list_builtin_levels()
	var builtin_ids: Array[String] = []
	var unique_builtin_ids := {}
	var arena_02_entry := {}
	for builtin: Dictionary in builtins:
		var builtin_id := str(builtin.get("id", ""))
		builtin_ids.append(builtin_id)
		unique_builtin_ids[builtin_id] = true
		if builtin_id == "arena_02_data":
			arena_02_entry = builtin
	var arena_01_index := builtin_ids.find("arena_01_data")
	var arena_02_index := builtin_ids.find("arena_02_data")
	var arena_03_index := builtin_ids.find("arena_03_data")
	_expect(
		unique_builtin_ids.size() == builtin_ids.size()
		and arena_01_index >= 0
		and arena_01_index < arena_02_index
		and arena_02_index < arena_03_index
		and arena_02_entry == {
			"id": "arena_02_data",
			"path": "res://levels/arena_02.json",
			"title": "Arena 02 / Опора",
		},
		"Built-in catalog IDs are duplicated or Arena 02 is out of order."
	)

	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_02_data")
	)
	_expect(
		bool(loaded.get("ok", false))
		and loaded.get("path", "") == "res://levels/arena_02.json"
		and (loaded.get("warnings", []) as Array).is_empty(),
		"Arena 02 built-in JSON did not load from its registered path."
	)
	if not bool(loaded.get("ok", false)):
		return

	var arena_02: Dictionary = loaded["data"]
	var fixture_ids: Array[String] = []
	for object: Dictionary in arena_02.get("objects", []):
		fixture_ids.append(str(object.get("id", "")))
	_expect(
		arena_02.keys().size() == 7
		and arena_02.get("schema_version", 0) == 1
		and arena_02.get("level_id", "") == "arena_02_data"
		and arena_02.get("title", "")
		== "GRAYBOX  /  DATA ARENA 02"
		and arena_02.get("objective", "")
		== "УДАРЬ ШАРНИР, УБЕРИ МОСТ"
		and arena_02.get("clear_message", "")
		== "DATA ARENA 02 ПРОЙДЕНА  /  ПЕРЕЗАПУСК..."
		and arena_02.get("canvas", {}) == {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		}
		and fixture_ids == [
			"left_floor",
			"right_floor",
			"player_start",
			"patrol_1",
			"center_bridge",
			"bridge_hinge",
		],
		"Arena 02 root metadata or stable object order drifted."
	)
	_expect(
		_object_by_id(
			arena_02,
			"left_floor"
		).get("rect", []) == [32, 496, 368, 44]
		and _object_by_id(
			arena_02,
			"right_floor"
		).get("rect", []) == [560, 496, 368, 44]
		and _object_by_id(
			arena_02,
			"player_start"
		).get("position", []) == [150, 450]
		and _object_by_id(
			arena_02,
			"patrol_1"
		).get("position", []) == [480, 450]
		and is_equal_approx(
			float(
				_object_by_id(
					arena_02,
					"patrol_1"
				).get("speed", -1.0)
			),
			65.0
		)
		and _object_by_id(
			arena_02,
			"patrol_1"
		).get("direction", 0) == 1
		and _object_by_id(
			arena_02,
			"center_bridge"
		).get("rect", []) == [400, 496, 160, 20]
		and bool(
			_object_by_id(
				arena_02,
				"center_bridge"
			).get("starts_active", false)
		)
		and _object_by_id(
			arena_02,
			"bridge_hinge"
		).get("position", []) == [300, 468]
		and _object_by_id(
			arena_02,
			"bridge_hinge"
		).get("target_id", "") == "center_bridge",
		"Arena 02 geometry, actors, or mechanism fixture drifted."
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(arena_02)
	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		encoded_once.get("text", "")
	)
	var encoded_twice: Dictionary = LEVEL_DATA_CODEC.encode(
		decoded.get("data", {})
	)
	_expect(
		bool(encoded_once.get("ok", false))
		and bool(decoded.get("ok", false))
		and bool(encoded_twice.get("ok", false))
		and encoded_once.get("text", "")
		== encoded_twice.get("text", ""),
		"Arena 02 JSON is not deterministic across a round trip."
	)

	var reserved_id: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("arena_02_data")
	)
	_expect(
		bool(reserved_id.get("ok", false))
		and reserved_id.get("data", "") != "arena_02_data",
		"Generated user ID collided with the Arena 02 built-in."
	)


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


func _test_arena_02_builder_and_real_clear() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_02_data")
	)
	_expect(
		bool(loaded.get("ok", false)),
		"Could not prepare the Arena 02 runtime fixture."
	)
	if not bool(loaded.get("ok", false)):
		return

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(
		loaded["data"]
	)
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode the Arena 02 runtime fixture."
	)
	if not bool(encoded.get("ok", false)):
		return

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(encoded["text"])
	var default_clear_restart_delay := arena.clear_restart_delay
	arena.clear_restart_delay = 10.0
	root.add_child(arena)
	current_scene = arena
	await process_frame

	_expect(arena.level_loaded, "Runtime did not build Arena 02.")
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
		"Builder did not create every Arena 02 object."
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
		"Builder did not resolve the Arena 02 hinge target."
	)
	_expect(
		hinge.get_parent() == arena.get_node("Geometry/LevelObjects")
		and bridge.get_parent()
		== arena.get_node("Geometry/LevelObjects"),
		"Builder placed a mechanism outside generated geometry."
	)
	_expect(
		is_instance_valid(cable)
		and cable.points == PackedVector2Array(
			[Vector2(300, 468), Vector2(480, 506)]
		),
		"Builder did not draw the exact Arena 02 runtime link."
	)
	_expect(
		hinge.position.is_equal_approx(Vector2(300, 468))
		and bridge.position.is_equal_approx(Vector2(480, 506))
		and is_equal_approx(enemy.patrol_speed, 65.0)
		and is_equal_approx(enemy.patrol_direction, 1.0)
		and arena.enemies_remaining == 1,
		"Builder did not preserve the Arena 02 placements or patrol preset."
	)
	var bridge_shape := (
		bridge.get_node("CollisionShape2D") as CollisionShape2D
	).shape as RectangleShape2D
	var hinge_shape := (
		hinge.get_node("CollisionShape2D") as CollisionShape2D
	).shape as CircleShape2D
	_expect(
		is_instance_valid(bridge_shape)
		and bridge_shape.size.is_equal_approx(Vector2(160, 20)),
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
		and not bridge.collision_shape.disabled
		and is_equal_approx(bridge.transition_time, 0.18)
		and is_equal_approx(hinge.cooldown, 0.35)
		and is_equal_approx(arena.fall_restart_delay, 0.45)
		and is_equal_approx(default_clear_restart_delay, 1.25),
		"An Arena 02 gameplay preset or active collision drifted."
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

	enemy.patrol_speed = 0.0
	enemy.velocity = Vector2.ZERO
	player.global_position = Vector2(250, 476)
	player.velocity = Vector2.ZERO
	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	await physics_frame
	var enemy_present_before_attack := (
		arena.enemies_remaining == 1
		and is_instance_valid(enemy)
		and bridge.is_active
	)
	await _press_physical_key(KEY_X)
	for _frame in range(90):
		await physics_frame
		if (
			not bridge.is_active
			and not bridge.is_transitioning
			and bridge.collision_shape.disabled
		):
			break

	_expect(
		enemy_present_before_attack
		and not bridge.is_active
		and bridge.collision_shape.disabled,
		"A physical player attack did not switch the linked bridge off."
	)

	for _frame in range(240):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame

	_expect(
		enemy_present_before_attack
		and arena.enemies_remaining == 0,
		"The patrol did not fall after its linked bridge switched off."
	)
	_expect(
		arena.pending_outcome == Arena.Outcome.CLEAR,
		"The mechanism-driven enemy fall did not produce CLEAR."
	)
	await _cleanup_current_scene()


func _test_arena_02_editor_lifecycle() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	var arena_02_index := _load_entry_index(editor, "arena_02_data")
	_expect(
		arena_02_index >= 0
		and editor.load_entries[arena_02_index].get("kind", "")
		== "builtin",
		"Editor does not list Arena 02 as a built-in example."
	)
	if arena_02_index < 0:
		await _cleanup_current_scene()
		return

	editor.call("_perform_load_selected_level", arena_02_index)
	await process_frame
	editor.call("_select_object", "bridge_hinge")
	await process_frame

	var target_options := (
		_find_property_editor(editor, "TARGET") as OptionButton
	)
	var selected_target := ""
	if (
		is_instance_valid(target_options)
		and target_options.selected >= 0
	):
		selected_target = str(
			target_options.get_item_metadata(target_options.selected)
		)
	var draft_before := editor.draft.to_dictionary()
	_expect(
		editor.source_label == "ПРИМЕР"
		and editor.loaded_user_level_id.is_empty()
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and editor.draft.find_object(
			"bridge_hinge"
		).get("target_id", "") == "center_bridge"
		and selected_target == "center_bridge",
		"Editor did not open Arena 02 as a clean linked built-in."
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var runtime := editor.playtest_runtime as LevelRuntimeArena
	_expect(
		is_instance_valid(runtime) and runtime.level_loaded,
		"Editor did not start the Arena 02 built-in playtest."
	)
	if not is_instance_valid(runtime) or not runtime.level_loaded:
		editor.call("_stop_playtest")
		await _cleanup_current_scene()
		return

	var bridge := (
		runtime.get_level_object("center_bridge") as TogglePlatform
	)
	var hinge := runtime.get_level_object("bridge_hinge") as Hinge
	_expect(
		is_instance_valid(bridge)
		and is_instance_valid(hinge)
		and hinge.target == bridge
		and bridge.is_active
		and runtime.enemies_remaining == 1,
		"Editor playtest did not preserve the Arena 02 link or start state."
	)
	if not is_instance_valid(bridge) or not is_instance_valid(hinge):
		editor.call("_stop_playtest")
		await process_frame
		await _cleanup_current_scene()
		return

	var old_runtime_ref: WeakRef = weakref(runtime)
	var old_bridge_ref: WeakRef = weakref(bridge)
	var transition_started := (
		bridge.request_toggle() and bridge.is_transitioning
	)
	var old_runtime_id := runtime.get_instance_id()
	runtime.call("_reload_scene")
	for _frame in range(30):
		await process_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and editor.playtest_runtime.get_instance_id()
			!= old_runtime_id
		):
			break

	var restarted_runtime := (
		editor.playtest_runtime as LevelRuntimeArena
	)
	var restarted_bridge := (
		restarted_runtime.get_level_object(
			"center_bridge"
		) as TogglePlatform
		if is_instance_valid(restarted_runtime)
		else null
	)
	var restarted_hinge := (
		restarted_runtime.get_level_object(
			"bridge_hinge"
		) as Hinge
		if is_instance_valid(restarted_runtime)
		else null
	)
	_expect(
		transition_started
		and old_runtime_ref.get_ref() == null
		and old_bridge_ref.get_ref() == null
		and is_instance_valid(restarted_runtime)
		and restarted_runtime.level_loaded
		and is_instance_valid(restarted_bridge)
		and restarted_bridge.is_active
		and not restarted_bridge.is_transitioning
		and is_instance_valid(restarted_hinge)
		and restarted_hinge.target == restarted_bridge,
		"Restart did not replace the active Arena 02 playtest cleanly."
	)
	if (
		not is_instance_valid(restarted_runtime)
		or not is_instance_valid(restarted_bridge)
	):
		editor.call("_stop_playtest")
		await process_frame
		await _cleanup_current_scene()
		return

	var stop_runtime_ref: WeakRef = weakref(restarted_runtime)
	var stop_bridge_ref: WeakRef = weakref(restarted_bridge)
	var stop_transition_started := (
		restarted_bridge.request_toggle()
		and restarted_bridge.is_transitioning
	)
	editor.call("_stop_playtest")
	await process_frame
	await process_frame
	_expect(
		stop_transition_started
		and stop_runtime_ref.get_ref() == null
		and stop_bridge_ref.get_ref() == null
		and not is_instance_valid(editor.playtest_runtime)
		and editor.editor_view.visible
		and not editor.playtest_overlay.visible
		and editor.draft.to_dictionary() == draft_before
		and not editor.draft.is_dirty(),
		"Stopping Arena 02 playtest changed the draft or leaked runtime nodes."
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


func _find_property_editor(
	editor: LevelEditor,
	label_text: String
) -> Control:
	for row: Node in editor.properties.get_children():
		if not row is HBoxContainer:
			continue
		var children := row.get_children()
		if (
			children.size() >= 2
			and children[0] is Label
			and (children[0] as Label).text == label_text
			and children[1] is Control
		):
			return children[1] as Control
	return null


func _load_entry_index(editor: LevelEditor, level_id: String) -> int:
	for index in editor.load_entries.size():
		if editor.load_entries[index].get("id", "") == level_id:
			return index
	return -1


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

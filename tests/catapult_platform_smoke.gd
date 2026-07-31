extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const RUNTIME_SCENE := preload("res://scenes/level_runtime_arena.tscn")
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const LEVEL_BEHAVIOR_PRESETS := preload(
	"res://scripts/levels/level_behavior_presets.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_builtin_schema_and_preview()
	await _test_builder_forward_reference()
	await _test_launch_extremes()
	await _test_clearance_fallback()
	await _test_arena_04_real_launch_and_clear()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("CATAPULT_PLATFORM_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_builtin_schema_and_preview() -> void:
	var builtins := LEVEL_STORAGE.list_builtin_levels()
	var builtin_ids: Array[String] = []
	for entry: Dictionary in builtins:
		builtin_ids.append(str(entry.get("id", "")))
	_expect(
		builtin_ids.has("arena_04_data"),
		"Built-in catalog does not expose Arena 04."
	)

	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_04_data")
	)
	_expect(
		bool(loaded["ok"])
		and loaded["data"]["level_id"] == "arena_04_data",
		"Arena 04 data fixture did not load."
	)
	if not bool(loaded["ok"]):
		return

	var arena_04: Dictionary = loaded["data"]
	var fixture_ids: Array[String] = []
	for object: Dictionary in arena_04["objects"]:
		fixture_ids.append(str(object["id"]))
	_expect(
		fixture_ids == [
			"left_floor",
			"right_floor",
			"player_start",
			"patrol_1",
			"catapult_1",
			"catapult_hinge",
		]
		and _object_by_id(
			arena_04,
			"left_floor"
		).get("rect", []) == [32, 496, 328, 44]
		and _object_by_id(
			arena_04,
			"right_floor"
		).get("rect", []) == [600, 496, 328, 44]
		and _object_by_id(
			arena_04,
			"player_start"
		).get("position", []) == [120, 450]
		and _object_by_id(
			arena_04,
			"patrol_1"
		).get("position", []) == [270, 310]
		and _object_by_id(
			arena_04,
			"patrol_1"
		).get("speed", 0) == 45
		and _object_by_id(
			arena_04,
			"patrol_1"
		).get("direction", 0) == 1
		and _object_by_id(
			arena_04,
			"catapult_1"
		).get("type", "") == "catapult_platform"
		and _object_by_id(
			arena_04,
			"catapult_1"
		).get("position", []) == [180, 360]
		and _object_by_id(
			arena_04,
			"catapult_hinge"
		).get("position", []) == [320, 468]
		and _object_by_id(
			arena_04,
			"catapult_hinge"
		).get("target_id", "") == "catapult_1",
		"Arena 04 fixture geometry or stable object order drifted."
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(arena_04)
	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		encoded_once.get("text", "")
	)
	var encoded_twice: Dictionary = LEVEL_DATA_CODEC.encode(
		decoded.get("data", {})
	)
	_expect(
		bool(encoded_once["ok"])
		and bool(decoded["ok"])
		and bool(encoded_twice["ok"])
		and encoded_once["text"] == encoded_twice["text"],
		"Arena 04 JSON is not deterministic across a round trip."
	)

	var reserved_id: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("arena_04_data")
	)
	_expect(
		bool(reserved_id["ok"])
		and reserved_id["data"] != "arena_04_data",
		"Generated user ID collided with the Arena 04 built-in."
	)

	var normalized: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			_make_forward_reference_level()
		)
	)
	var canonical_catapult := _object_by_id(
		normalized.get("data", {}),
		"catapult_1"
	)
	var canonical_keys := canonical_catapult.keys()
	canonical_keys.sort()
	_expect(
		bool(normalized["ok"])
		and canonical_keys == [
			"behavior_preset",
			"id",
			"position",
			"type",
		]
		and canonical_catapult.get(
			"behavior_preset",
			""
		) == "standard",
		(
			"Catapult schema is not the compact position plus canonical "
			+ "standard preset contract."
		)
	)

	for invalid_key: String in [
		"direction",
		"launch_direction",
		"launch_impulse",
		"warning_time",
		"swing_angle_degrees",
		"swing_out_time",
		"return_time",
		"clearance_impulse",
		"clearance_attempts",
		"scene_path",
	]:
		var injected := _make_forward_reference_level()
		_object_by_id(injected, "catapult_1")[invalid_key] = 1
		_expect_invalid(
			injected,
			"catapult with internal '%s' tuning" % invalid_key
		)

	for invalid_preset: Variant in ["unknown", 7]:
		var invalid_behavior := _make_forward_reference_level()
		_object_by_id(
			invalid_behavior,
			"catapult_1"
		)["behavior_preset"] = invalid_preset
		_expect_invalid(
			invalid_behavior,
			"catapult with invalid behavior preset %s"
			% str(invalid_preset)
		)

	for invalid_position: Array in [
		[31, 360],
		[749, 360],
		[180, 93],
		[180, 531],
	]:
		var invalid_bounds := _make_forward_reference_level()
		_object_by_id(
			invalid_bounds,
			"catapult_1"
		)["position"] = invalid_position
		_expect_invalid(
			invalid_bounds,
			"catapult pivot at %s" % str(invalid_position)
		)

	for valid_position: Array in [
		[32, 360],
		[748, 360],
		[180, 94],
		[180, 530],
	]:
		var valid_bounds := _make_forward_reference_level()
		_object_by_id(
			valid_bounds,
			"catapult_1"
		)["position"] = valid_position
		_expect(
			bool(
				LEVEL_DATA_VALIDATOR.validate_and_normalize(
					valid_bounds
				)["ok"]
			),
			"Validator rejected catapult boundary %s."
			% str(valid_position)
		)

	var actor_overlap := _make_forward_reference_level()
	_object_by_id(
		actor_overlap,
		"patrol_1"
	)["position"] = [345, 350]
	_expect_invalid(
		actor_overlap,
		"actor overlapping the catapult rest collision"
	)

	var actor_touching := _make_forward_reference_level()
	_object_by_id(
		actor_touching,
		"patrol_1"
	)["position"] = [345, 332]
	var touching_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(actor_touching)
	)
	_expect(
		bool(touching_result["ok"])
		and not _contains_text(
			touching_result["warnings"],
			"no solid support"
		),
		"Catapult right edge is not treated as exact solid support."
	)

	var wrong_target := _make_forward_reference_level()
	_object_by_id(
		wrong_target,
		"catapult_hinge"
	)["target_id"] = "left_floor"
	_expect_invalid(
		wrong_target,
		"hinge targeting a solid instead of a mechanism"
	)

	var unlinked := _make_forward_reference_level()
	var hinge_index := _object_index(unlinked, "catapult_hinge")
	unlinked["objects"].remove_at(hinge_index)
	var unlinked_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(unlinked)
	)
	_expect(
		bool(unlinked_result["ok"])
		and _contains_text(
			unlinked_result["warnings"],
			"no controlling hinge"
		)
		and not _contains_text(
			unlinked_result["warnings"],
			"no solid support"
		),
		"Catapult support or missing-controller warning is incorrect."
	)

	var pivot := Vector2(180, 360)
	var rest_rect := LevelEditorCanvas.catapult_rest_rect(pivot)
	var launch_rect := (
		LevelEditorCanvas.catapult_launch_area_rect(pivot)
	)
	var swing := LevelEditorCanvas.catapult_swing_polygon(pivot)
	var trajectory := LevelEditorCanvas.catapult_trajectory_points(
		Vector2(270, 332)
	)
	var player_trajectory := (
		LevelEditorCanvas.catapult_trajectory_points(
			Vector2(270, 332),
			LevelEditorCanvas.CATAPULT_PREVIEW_PLAYER_DRAG
		)
	)
	var exam_trajectory := (
		LevelEditorCanvas.catapult_trajectory_points(
			Vector2(270, 332),
			LevelEditorCanvas.CATAPULT_PREVIEW_ENEMY_DRAG,
			"exam"
		)
	)
	var standard_guide := (
		LevelEditorCanvas.catapult_guide_points(pivot)
	)
	var exam_guide := LevelEditorCanvas.catapult_guide_points(
		pivot,
		"exam"
	)
	var exam_arrow := (
		LevelEditorCanvas.catapult_guide_arrow_polygon(exam_guide)
	)
	_expect(
		rest_rect.is_equal_approx(Rect2(180, 350, 180, 20))
		and launch_rect.is_equal_approx(
			Rect2(180, 302, 180, 52)
		)
		and swing.size() == 4
		and swing[0].distance_to(
			pivot
			+ Vector2(0, -10).rotated(
				deg_to_rad(-55)
			)
		) < 0.01
		and trajectory.size() == 13
		and trajectory[0].is_equal_approx(Vector2(270, 332))
		and trajectory[3].distance_to(
			Vector2(301.07475, 320.91875)
		) < 0.01
		and trajectory[6].distance_to(
			Vector2(331.299, 312.875)
		) < 0.01
		and trajectory[12].distance_to(
			Vector2(389.196, 305.9)
		) < 0.01
		and player_trajectory[12].distance_to(
			Vector2(387.576, 305.9)
		) < 0.01
		and exam_trajectory[12].distance_to(
			Vector2(295.596, 341.9)
		) < 0.01
		and standard_guide.size() == 3
		and standard_guide[0].is_equal_approx(Vector2(270, 328))
		and standard_guide[2].distance_to(
			Vector2(389.196, 301.9)
		) < 0.01
		and exam_guide.size() == 3
		and exam_guide[2].distance_to(
			Vector2(295.596, 337.9)
		) < 0.01
		and exam_arrow.size() == 3
		and exam_arrow[0].is_equal_approx(exam_guide[2])
		and LEVEL_BEHAVIOR_PRESETS.catapult_launch_impulse(
			"standard"
		).is_equal_approx(Vector2(700, -280))
		and LEVEL_BEHAVIOR_PRESETS.catapult_launch_impulse(
			"exam"
		).is_equal_approx(Vector2(180, -80))
		and LevelEditorCanvas.clamp_catapult_position(
			Vector2(-100, -100)
		).is_equal_approx(Vector2(32, 94))
		and LevelEditorCanvas.clamp_catapult_position(
			Vector2(900, 900)
		).is_equal_approx(Vector2(748, 530)),
		"Catapult editor geometry or standard/exam trajectory drifted."
	)


func _test_builder_forward_reference() -> void:
	var arena := await _create_embedded_runtime(
		_make_forward_reference_level()
	)
	_expect(
		is_instance_valid(arena) and arena.level_loaded,
		"Forward-reference catapult level did not load."
	)
	if not is_instance_valid(arena) or not arena.level_loaded:
		await _cleanup_current_scene()
		return

	var catapult := (
		arena.get_level_object("catapult_1") as RotatingPlatform
	)
	var hinge := arena.get_level_object("catapult_hinge") as Hinge
	var enemy := arena.get_level_object("patrol_1") as PatrolEnemy
	var player := arena.get_level_object("player_start") as Player
	if (
		not is_instance_valid(catapult)
		or not is_instance_valid(hinge)
		or not is_instance_valid(enemy)
		or not is_instance_valid(player)
	):
		failures.append(
			"Builder did not create the catapult, hinge, and actors."
		)
		await _cleanup_current_scene()
		return

	var rest_shape := (
		catapult.rest_collision.shape as RectangleShape2D
	)
	var launch_shape_node := catapult.get_node(
		"LaunchArea/CollisionShape2D"
	) as CollisionShape2D
	var launch_shape := (
		launch_shape_node.shape as RectangleShape2D
	)
	var cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_catapult_hinge"
	) as Line2D
	_expect(
		is_instance_valid(catapult)
		and is_instance_valid(hinge)
		and is_instance_valid(enemy)
		and catapult.get_parent() == arena.get_node(
			"Geometry/LevelObjects"
		)
		and hinge.target == catapult
		and catapult.position.is_equal_approx(Vector2(180, 360))
		and is_equal_approx(catapult.launch_direction, 1.0)
		and catapult.launch_impulse.is_equal_approx(
			LEVEL_BEHAVIOR_PRESETS.catapult_launch_impulse(
				"standard"
			)
		)
		and is_equal_approx(
			-catapult.swing_angle_degrees,
			LevelEditorCanvas.CATAPULT_SWING_ANGLE_DEGREES
		)
		and is_equal_approx(
			enemy.knockback_drag,
			LevelEditorCanvas.CATAPULT_PREVIEW_ENEMY_DRAG
		)
		and enemy.knockback_lock_time >= (
			LevelEditorCanvas.CATAPULT_PREVIEW_DURATION
		)
		and is_equal_approx(
			enemy.gravity,
			LevelEditorCanvas.CATAPULT_PREVIEW_GRAVITY
		)
		and is_equal_approx(
			player.knockback_drag,
			LevelEditorCanvas.CATAPULT_PREVIEW_PLAYER_DRAG
		)
		and player.knockback_lock_time >= (
			LevelEditorCanvas.CATAPULT_PREVIEW_DURATION
		)
		and is_equal_approx(
			player.gravity,
			LevelEditorCanvas.CATAPULT_PREVIEW_GRAVITY
		)
		and catapult.rest_collision.position.is_equal_approx(
			Vector2(90, 0)
		)
		and rest_shape.size.is_equal_approx(Vector2(180, 20))
		and launch_shape_node.position.is_equal_approx(
			Vector2(90, -32)
		)
		and launch_shape.size.is_equal_approx(Vector2(180, 52))
		and catapult.safe_above.position.is_equal_approx(
			Vector2(90, -42)
		)
		and is_instance_valid(cable)
		and cable.points == PackedVector2Array(
			[Vector2(320, 468), Vector2(180, 360)]
		)
		and arena.enemies_remaining == 1,
		"Builder catapult geometry, preset, link, or parent drifted."
	)
	await _cleanup_current_scene()


func _test_launch_extremes() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_04_data")
	)
	if not bool(loaded["ok"]):
		failures.append(
			"Could not prepare Arena 04 launch-edge fixtures."
		)
		return

	for start_x: float in [195.0, 345.0]:
		var arena := await _create_embedded_runtime(
			loaded["data"]
		)
		if not is_instance_valid(arena) or not arena.level_loaded:
			failures.append(
				"Arena 04 launch-edge fixture did not load."
			)
			await _cleanup_current_scene()
			continue
		arena.clear_restart_delay = 10.0

		var catapult := (
			arena.get_level_object("catapult_1") as RotatingPlatform
		)
		var enemy := (
			arena.get_level_object("patrol_1") as PatrolEnemy
		)
		for _frame in range(30):
			await physics_frame
		enemy.global_position.x = start_x
		enemy.velocity = Vector2.ZERO
		await physics_frame
		catapult.warning_time = 0.0
		var accepted := catapult.request_toggle()

		for _frame in range(240):
			await physics_frame
			if arena.enemies_remaining == 0:
				break
		_expect(
			accepted
			and is_equal_approx(enemy.patrol_speed, 45.0)
			and arena.enemies_remaining == 0
			and arena.pending_outcome == Arena.Outcome.CLEAR,
			"Catapult missed the center pit from patrol x=%d."
			% int(start_x)
		)
		await _cleanup_current_scene()


func _test_clearance_fallback() -> void:
	var arena := await _create_embedded_runtime(
		_make_forward_reference_level()
	)
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Catapult clearance fixture did not load.")
		await _cleanup_current_scene()
		return

	var catapult := (
		arena.get_level_object("catapult_1") as RotatingPlatform
	)
	var player := arena.get_level_object("player_start") as Player
	if not is_instance_valid(catapult) or not is_instance_valid(player):
		failures.append("Catapult clearance actors were not built.")
		await _cleanup_current_scene()
		return

	player.set_physics_process(false)
	player.global_position = (
		catapult.global_position + Vector2(90, -20)
	)
	player.velocity = Vector2.ZERO
	for _frame in range(3):
		await physics_frame
		if player in catapult.launch_area.get_overlapping_bodies():
			break

	catapult.warning_time = 0.0
	catapult.swing_out_time = 0.01
	catapult.swing_hold_time = 0.0
	catapult.return_time = 0.01
	catapult.clearance_time = 0.0
	var launch_counts: Array[int] = []
	catapult.launched.connect(
		func(body_count: int) -> void:
			launch_counts.append(body_count)
	)
	var accepted := catapult.request_toggle()
	for _frame in range(120):
		await physics_frame
		if not catapult.is_transitioning:
			break

	_expect(
		accepted
		and not launch_counts.is_empty()
		and launch_counts[0] >= 1
		and not catapult.is_transitioning
		and not catapult.rest_collision.disabled
		and player.global_position.distance_to(
			catapult.safe_above.global_position
		) < 0.5,
		(
			"Catapult did not move a trapped body to SafeAbove: "
			+ "accepted=%s launches=%s transitioning=%s "
			+ "collision_disabled=%s player=%s safe=%s."
		)
		% [
			accepted,
			str(launch_counts),
			catapult.is_transitioning,
			catapult.rest_collision.disabled,
			player.global_position,
			catapult.safe_above.global_position,
		]
	)
	await _cleanup_current_scene()


func _test_arena_04_real_launch_and_clear() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_04_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 04 fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 04 embedded playtest did not load.")
		await _cleanup_current_scene()
		return
	arena.clear_restart_delay = 10.0

	var catapult := (
		arena.get_level_object("catapult_1") as RotatingPlatform
	)
	var hinge := arena.get_level_object("catapult_hinge") as Hinge
	var enemy := arena.get_level_object("patrol_1") as PatrolEnemy
	var player := arena.get_level_object("player_start") as Player
	var launch_records: Array[Dictionary] = []
	catapult.launched.connect(
		func(body_count: int) -> void:
			launch_records.append(
				{
					"count": body_count,
					"velocity": enemy.velocity,
					"lock": enemy.knockback_time_remaining,
				}
			)
	)

	for _frame in range(30):
		await physics_frame
	enemy.patrol_speed = 0.0
	player.global_position = Vector2(270, 476)
	player.velocity = Vector2.ZERO
	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	await physics_frame
	await _press_physical_key(KEY_X)

	var saw_warning := false
	for _frame in range(60):
		await physics_frame
		saw_warning = (
			saw_warning
			or catapult.is_transitioning
			and not catapult.rest_collision.disabled
		)
		if not launch_records.is_empty():
			break
	await physics_frame
	var saw_disabled_collision := catapult.rest_collision.disabled
	var launch_velocity: Vector2 = (
		launch_records[0].get("velocity", Vector2.ZERO)
		if not launch_records.is_empty()
		else Vector2.ZERO
	)
	_expect(
		saw_warning
		and not hinge.is_ready
		and launch_records.size() == 1
		and int(launch_records[0]["count"]) == 1
		and launch_velocity.is_equal_approx(Vector2(700, -280))
		and float(launch_records[0]["lock"]) > 0.0
		and saw_disabled_collision,
		"Physical hinge hit did not run warning and exact launch preset."
	)

	for _frame in range(240):
		await physics_frame
		if (
			arena.restart_scheduled
			and not catapult.is_transitioning
			and hinge.is_ready
		):
			break
	await process_frame
	_expect(
		arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and not catapult.is_transitioning
		and not catapult.rest_collision.disabled
		and hinge.is_ready,
		"Arena 04 did not clear and restore the catapult after launch."
	)
	await _cleanup_current_scene()


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	var arena_04_index := _load_entry_index(editor, "arena_04_data")
	_expect(
		arena_04_index >= 0,
		"Editor does not list the Arena 04 built-in."
	)
	if arena_04_index < 0:
		await _cleanup_current_scene()
		return
	editor.call("_perform_load_selected_level", arena_04_index)
	await process_frame

	editor.call("_select_object", "catapult_1")
	await process_frame
	var preset_options := (
		_find_property_editor(editor, "PRESET") as OptionButton
	)
	_expect(
		editor.source_label == "ПРИМЕР"
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and is_instance_valid(_find_property_editor(editor, "X"))
		and is_instance_valid(_find_property_editor(editor, "Y"))
		and _selected_option_metadata(preset_options) == "standard"
		and not is_instance_valid(
			_find_property_editor(editor, "DIRECTION")
		)
		and not is_instance_valid(_find_property_editor(editor, "SPEED"))
		and "PRESET STANDARD" in editor.inspector_hint.text
		and "700, -280" in editor.inspector_hint.text,
		"Catapult built-in or compact inspector is incorrect."
	)
	if is_instance_valid(preset_options):
		preset_options.select(1)
		preset_options.item_selected.emit(1)
		await process_frame
		_expect(
			editor.draft.find_object(
				"catapult_1"
			).get("behavior_preset", "") == "exam"
			and "PRESET EXAM" in editor.inspector_hint.text
			and "180, -80" in editor.inspector_hint.text,
			"Catapult PRESET inspector did not apply the exam variant."
		)
		editor.call("_undo")
		await process_frame

	editor.canvas.grab_focus()
	await process_frame
	await _press_physical_key(KEY_8)
	await process_frame
	_expect(
		editor.active_tool == "catapult_platform"
		and editor.catapult_button.button_pressed
		and editor.tool_scroll.get_global_rect().encloses(
			editor.catapult_button.get_global_rect()
		),
		"Physical 8 did not select and reveal the catapult tool."
	)

	editor.canvas.call(
		"_begin_primary_action",
		Vector2(500, 300) * 0.6
	)
	await process_frame
	var placed_id: String = editor.selected_id
	var placed := editor.draft.find_object(placed_id)
	var hit := editor.canvas.call(
		"_hit_test",
		Vector2(590, 300)
	) as Dictionary
	var shooter_blockers := editor.canvas.call(
		"_shooter_blockers"
	) as Array[Dictionary]
	var catapult_blocker := _dictionary_by_id(
		shooter_blockers,
		"catapult_1"
	)
	_expect(
		placed.get("type", "") == "catapult_platform"
		and placed.get("position", []) == [500, 300]
		and placed.get("behavior_preset", "") == "standard"
		and placed.keys().size() == 4
		and hit.get("id", "") == placed_id
		and catapult_blocker.get(
			"rect",
			Rect2()
		).is_equal_approx(Rect2(180, 350, 180, 20)),
		"Catapult placement, far-body hit-test, or schema is incorrect."
	)

	editor.call("_nudge_selected", Vector2i.LEFT, false)
	_expect(
		editor.draft.find_object(placed_id)["position"] == [480, 300],
		"Catapult nudge did not use the editor grid."
	)
	editor.call("_duplicate_selected")
	var duplicate_id: String = editor.selected_id
	var duplicate := editor.draft.find_object(duplicate_id)
	_expect(
		duplicate_id != placed_id
		and duplicate.get("position", []) == [500, 320]
		and duplicate.get("behavior_preset", "") == "standard"
		and duplicate.keys().size() == 4,
		"Catapult duplicate leaked tuning or used the wrong offset."
	)

	editor.call("_select_object", placed_id)
	editor.draft.update_object(placed_id, {"position": [748, 530]})
	editor.call("_nudge_selected", Vector2i.RIGHT, false)
	editor.call("_nudge_selected", Vector2i.DOWN, false)
	editor.call("_duplicate_selected")
	var edge_duplicate_id: String = editor.selected_id
	_expect(
		editor.draft.find_object(placed_id).get(
			"position",
			[]
		) == [748, 530]
		and editor.draft.find_object(edge_duplicate_id).get(
			"position",
			[]
		) == [748, 530],
		"Catapult nudge or duplicate escaped its valid footprint."
	)

	for _attempt in range(10):
		if not editor.draft.is_dirty():
			break
		editor.call("_undo")
	_expect(
		editor.draft.find_object(placed_id).is_empty()
		and editor.draft.find_object(duplicate_id).is_empty()
		and editor.draft.find_object(edge_duplicate_id).is_empty()
		and not editor.draft.is_dirty(),
		"Catapult actions did not undo to the Arena 04 snapshot."
	)

	editor.call("_select_object", "catapult_hinge")
	await process_frame
	var target_options := (
		_find_property_editor(editor, "TARGET") as OptionButton
	)
	var target_selected := (
		str(
			target_options.get_item_metadata(
				target_options.selected
			)
		)
		if is_instance_valid(target_options)
		else ""
	)
	editor.draft.add_object(
		{
			"id": "overlapped_toggle",
			"type": "toggle_platform",
			"rect": [180, 350, 180, 20],
			"starts_active": true,
		}
	)
	editor.call("_begin_linking", "catapult_hinge")
	await process_frame
	var link_hit := editor.canvas.call(
		"_hit_test_hinge_target",
		Vector2(270, 360)
	) as Dictionary
	editor.call(
		"_on_link_target_requested",
		str(link_hit.get("id", ""))
	)
	await process_frame
	editor.call("_undo")
	_expect(
		target_selected == "catapult_1"
		and link_hit.get("id", "") == "catapult_1"
		and editor.draft.find_object(
			"catapult_hinge"
		).get("target_id", "") == "catapult_1"
		and editor.linking_hinge_id.is_empty()
		and not editor.draft.is_dirty(),
		(
			"Hinge dropdown or field-link mode did not accept the "
			+ "catapult: selected=%s hit=%s target=%s linking=%s dirty=%s"
		)
		% [
			target_selected,
			str(link_hit),
			editor.draft.find_object(
				"catapult_hinge"
			).get("target_id", ""),
			editor.linking_hinge_id,
			editor.draft.is_dirty(),
		]
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var runtime := editor.playtest_runtime as LevelRuntimeArena
	var runtime_catapult := (
		runtime.get_level_object(
			"catapult_1"
		) as RotatingPlatform
		if is_instance_valid(runtime)
		else null
	)
	var old_runtime_ref: WeakRef = weakref(runtime)
	var old_catapult_ref: WeakRef = weakref(runtime_catapult)
	if is_instance_valid(runtime_catapult):
		runtime_catapult.warning_time = 0.0
		runtime_catapult.request_toggle()
	var tween_started := await _wait_for_active_tween(
		runtime_catapult
	)
	var launch_started := (
		is_instance_valid(runtime_catapult)
		and runtime_catapult.is_transitioning
	)
	var old_runtime_id: int = runtime.get_instance_id()
	runtime.call("_reload_scene")
	for _frame in range(20):
		await process_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and (
				editor.playtest_runtime.get_instance_id()
				!= old_runtime_id
			)
		):
			break

	var restarted_runtime := (
		editor.playtest_runtime as LevelRuntimeArena
	)
	var restarted_catapult := (
		restarted_runtime.get_level_object(
			"catapult_1"
		) as RotatingPlatform
		if is_instance_valid(restarted_runtime)
		else null
	)
	var restarted_hinge := (
		restarted_runtime.get_level_object(
			"catapult_hinge"
		) as Hinge
		if is_instance_valid(restarted_runtime)
		else null
	)
	_expect(
		launch_started
		and tween_started
		and old_runtime_ref.get_ref() == null
		and old_catapult_ref.get_ref() == null
		and is_instance_valid(restarted_runtime)
		and restarted_runtime.level_loaded
		and is_instance_valid(restarted_catapult)
		and not restarted_catapult.is_transitioning
		and is_instance_valid(restarted_hinge)
		and restarted_hinge.target == restarted_catapult,
		"Restart did not replace an active catapult playtest cleanly."
	)

	var stop_catapult_ref: WeakRef = weakref(restarted_catapult)
	if is_instance_valid(restarted_catapult):
		restarted_catapult.warning_time = 0.0
		restarted_catapult.request_toggle()
	var stop_tween_started := await _wait_for_active_tween(
		restarted_catapult
	)
	editor.call("_stop_playtest")
	await process_frame
	await process_frame
	_expect(
		stop_tween_started
		and stop_catapult_ref.get_ref() == null
		and _count_catapults(editor) == 0,
		"Catapult survived stopping the embedded playtest."
	)
	await _cleanup_current_scene()


func _make_forward_reference_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "catapult_forward_smoke",
		"title": "CATAPULT FORWARD SMOKE",
		"objective": "TEST",
		"clear_message": "CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "catapult_hinge",
				"type": "hinge",
				"position": [320, 468],
				"target_id": "catapult_1",
			},
			{
				"id": "left_floor",
				"type": "solid_rect",
				"rect": [32, 496, 328, 44],
			},
			{
				"id": "right_floor",
				"type": "solid_rect",
				"rect": [600, 496, 328, 44],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [270, 310],
				"speed": 45,
				"direction": 1,
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [120, 450],
			},
			{
				"id": "catapult_1",
				"type": "catapult_platform",
				"position": [180, 360],
			},
		],
	}


func _create_embedded_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded["ok"]),
		"Could not encode embedded catapult fixture: %s"
		% str(encoded["errors"])
	)
	if not bool(encoded["ok"]):
		return null

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(encoded["text"])
	root.add_child(arena)
	current_scene = arena
	await process_frame
	return arena


func _cleanup_current_scene() -> void:
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	Input.action_release("ui_accept")
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame


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


func _selected_option_metadata(options: OptionButton) -> Variant:
	if not is_instance_valid(options) or options.selected < 0:
		return null
	return options.get_item_metadata(options.selected)


func _load_entry_index(editor: LevelEditor, level_id: String) -> int:
	for index in editor.load_entries.size():
		if editor.load_entries[index].get("id", "") == level_id:
			return index
	return -1


func _count_catapults(node: Node) -> int:
	var count := 1 if node is RotatingPlatform else 0
	for child: Node in node.get_children():
		count += _count_catapults(child)
	return count


func _wait_for_active_tween(catapult: RotatingPlatform) -> bool:
	for _frame in range(12):
		if (
			is_instance_valid(catapult)
			and is_instance_valid(catapult.active_tween)
		):
			return true
		await physics_frame
	return false


func _dictionary_by_id(
	entries: Array[Dictionary],
	entry_id: String
) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("id", "") == entry_id:
			return entry
	return {}


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


func _contains_text(messages: Array, fragment: String) -> bool:
	for message: Variant in messages:
		if fragment in str(message):
			return true
	return false


func _expect_invalid(data: Dictionary, label: String) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(not bool(result["ok"]), "Validator accepted %s." % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

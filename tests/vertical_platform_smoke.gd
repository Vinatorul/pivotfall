extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const RUNTIME_SCENE := preload("res://scenes/data_arena_01.tscn")
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_builtin_schema_and_preview()
	_test_corridor_validation()
	await _test_builder_forward_reference()
	await _test_passenger_round_trip()
	await _test_shooter_height_and_goal()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("VERTICAL_PLATFORM_SMOKE_OK")
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
		builtin_ids.has("arena_07_data"),
		"Built-in catalog does not expose Arena 07."
	)

	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_07_data")
	)
	_expect(
		bool(loaded["ok"])
		and loaded["data"]["level_id"] == "arena_07_data",
		"Arena 07 data fixture did not load."
	)
	if not bool(loaded["ok"]):
		return

	var arena_07: Dictionary = loaded["data"]
	var fixture_ids: Array[String] = []
	for object: Dictionary in arena_07["objects"]:
		fixture_ids.append(str(object["id"]))
	_expect(
		fixture_ids == [
			"floor",
			"cover",
			"player_start",
			"shooter_1",
			"lift_1",
			"lift_hinge",
		]
		and _object_by_id(
			arena_07,
			"floor"
		).get("rect", []) == [32, 496, 328, 44]
		and _object_by_id(
			arena_07,
			"cover"
		).get("rect", []) == [324, 430, 36, 66]
		and _object_by_id(
			arena_07,
			"player_start"
		).get("position", []) == [120, 450]
		and _object_by_id(
			arena_07,
			"shooter_1"
		).get("position", []) == [439, 270]
		and _object_by_id(
			arena_07,
			"lift_1"
		).get("position", []) == [460, 330]
		and _object_by_id(
			arena_07,
			"lift_hinge"
		).get("position", []) == [250, 468]
		and _object_by_id(
			arena_07,
			"lift_hinge"
		).get("target_id", "") == "lift_1"
		and arena_07["objective"]
		== "ОПУСТИ СТРЕЛКА → ДОБЕРИСЬ ДО ЛИФТА",
		"Arena 07 fixture geometry, goal, or stable object order drifted."
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(arena_07)
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
		"Arena 07 JSON is not deterministic across a round trip."
	)

	var reserved_id: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("arena_07_data")
	)
	_expect(
		bool(reserved_id["ok"])
		and reserved_id["data"] != "arena_07_data",
		"Generated user ID collided with the Arena 07 built-in."
	)

	var normalized: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			_make_forward_reference_level()
		)
	)
	var canonical_lift := _object_by_id(
		normalized.get("data", {}),
		"lift_1"
	)
	var canonical_keys := canonical_lift.keys()
	canonical_keys.sort()
	_expect(
		bool(normalized["ok"])
		and canonical_keys == ["id", "position", "type"],
		"Lift schema is not the compact id/type/position contract."
	)

	for invalid_key: String in [
		"starts_lowered",
		"travel_offset",
		"travel_distance",
		"direction",
		"warning_time",
		"travel_time",
		"speed",
		"scene_path",
	]:
		var injected := _make_forward_reference_level()
		_object_by_id(injected, "lift_1")[invalid_key] = 1
		_expect_invalid(
			injected,
			"vertical platform with internal '%s' tuning"
			% invalid_key
		)

	for invalid_position: Array in [
		[71, 200],
		[889, 200],
		[460, 81],
		[460, 395],
	]:
		var invalid_bounds := _make_bounds_level(invalid_position)
		_expect_invalid(
			invalid_bounds,
			"vertical platform origin at %s"
			% str(invalid_position)
		)

	for valid_position: Array in [
		[72, 200],
		[888, 200],
		[460, 82],
		[460, 394],
	]:
		var valid_bounds := _make_bounds_level(valid_position)
		_expect(
			bool(
				LEVEL_DATA_VALIDATOR.validate_and_normalize(
					valid_bounds
				)["ok"]
			),
			"Validator rejected lift boundary %s."
			% str(valid_position)
		)

	var unlinked := _make_forward_reference_level()
	unlinked["objects"].remove_at(
		_object_index(unlinked, "lift_hinge")
	)
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
			"shooter_1"
		),
		"Lift support or missing-controller warning is incorrect."
	)

	var position := Vector2(460, 330)
	_expect(
		LevelEditorCanvas.vertical_platform_upper_rect(
			position
		).is_equal_approx(Rect2(420, 320, 80, 20))
		and LevelEditorCanvas.vertical_platform_lower_rect(
			position
		).is_equal_approx(Rect2(420, 456, 80, 20))
		and LevelEditorCanvas.vertical_platform_corridor_rect(
			position
		).is_equal_approx(Rect2(420, 320, 80, 156))
		and LevelEditorCanvas.vertical_platform_passenger_clearance_rect(
			position
		).is_equal_approx(Rect2(420, 280, 80, 196))
		and LevelEditorCanvas.clamp_vertical_platform_position(
			Vector2(-100, -100)
		).is_equal_approx(Vector2(72, 82))
		and LevelEditorCanvas.clamp_vertical_platform_position(
			Vector2(1000, 1000)
		).is_equal_approx(Vector2(888, 394)),
		"Lift editor geometry, travel preset, or clamp drifted."
	)


func _test_corridor_validation() -> void:
	var overhead_overlap := _make_forward_reference_level()
	overhead_overlap["objects"].append(
		{
			"id": "low_ceiling",
			"type": "solid_rect",
			"rect": [480, 270, 20, 20],
		}
	)
	_expect_invalid_with_fragments(
		overhead_overlap,
		"solid clipping only the lift passenger clearance",
		["clearance corridor", "low_ceiling"]
	)

	var upper_edge_touch := _make_forward_reference_level()
	upper_edge_touch["objects"].append(
		{
			"id": "upper_edge",
			"type": "solid_rect",
			"rect": [480, 260, 20, 20],
		}
	)
	_expect_valid(
		upper_edge_touch,
		"solid touching the passenger corridor's upper edge"
	)

	var side_edge_touch := _make_forward_reference_level()
	side_edge_touch["objects"].append(
		{
			"id": "side_edge",
			"type": "solid_rect",
			"rect": [500, 300, 20, 20],
		}
	)
	_expect_valid(
		side_edge_touch,
		"solid touching the passenger corridor's side edge"
	)

	var lower_edge_touch := _make_forward_reference_level()
	lower_edge_touch["objects"].append(
		{
			"id": "lower_edge",
			"type": "solid_rect",
			"rect": [480, 476, 20, 20],
		}
	)
	_expect_valid(
		lower_edge_touch,
		"solid touching the travel corridor's lower edge"
	)

	var lower_edge_overlap := _make_forward_reference_level()
	lower_edge_overlap["objects"].append(
		{
			"id": "lower_overlap",
			"type": "solid_rect",
			"rect": [480, 475, 20, 20],
		}
	)
	_expect_invalid_with_fragments(
		lower_edge_overlap,
		"solid crossing the travel corridor's lower edge",
		["clearance corridor", "lower_overlap"]
	)

	var inactive_toggle_overlap := _make_forward_reference_level()
	inactive_toggle_overlap["objects"].append(
		{
			"id": "future_ceiling",
			"type": "toggle_platform",
			"rect": [480, 270, 20, 20],
			"starts_active": false,
		}
	)
	_expect_invalid_with_fragments(
		inactive_toggle_overlap,
		"inactive toggle clipping the lift passenger clearance",
		["clearance corridor", "future_ceiling"]
	)

	var catapult_overlap := _make_forward_reference_level()
	catapult_overlap["objects"].append(
		{
			"id": "catapult_2",
			"type": "catapult_platform",
			"position": [440, 300],
		}
	)
	_expect_invalid_with_fragments(
		catapult_overlap,
		"catapult rest body clipping the lift passenger clearance",
		["clearance corridor", "catapult_2"]
	)

	var second_lift_overlap := _make_forward_reference_level()
	second_lift_overlap["objects"].append(
		{
			"id": "lift_2",
			"type": "vertical_platform",
			"position": [480, 330],
		}
	)
	_expect_invalid_with_fragments(
		second_lift_overlap,
		"overlapping vertical platform clearance corridors",
		["clearance corridor", "lift_1", "lift_2"]
	)

	var actor_in_future_sweep := _make_forward_reference_level()
	_object_by_id(
		actor_in_future_sweep,
		"player_start"
	)["position"] = [480, 360]
	_expect_invalid_with_fragments(
		actor_in_future_sweep,
		"actor spawned inside the lift's future body sweep",
		["player_start", "lift_1", "future sweep"]
	)

	var actor_touching_sweep_side := _make_forward_reference_level()
	_object_by_id(
		actor_touching_sweep_side,
		"player_start"
	)["position"] = [406, 360]
	_expect_valid(
		actor_touching_sweep_side,
		"actor touching the future sweep's side edge"
	)

	var passenger_on_upper_stop := _make_forward_reference_level()
	_object_by_id(
		passenger_on_upper_stop,
		"player_start"
	)["position"] = [480, 300]
	var passenger_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			passenger_on_upper_stop
		)
	)
	_expect(
		bool(passenger_result["ok"])
		and not _contains_text(
			passenger_result["warnings"],
			"player_start"
		),
		"Actor resting on the upper stop was not accepted as a passenger."
	)

	var passenger_inside_body := _make_forward_reference_level()
	_object_by_id(
		passenger_inside_body,
		"player_start"
	)["position"] = [480, 301]
	_expect_invalid_with_fragments(
		passenger_inside_body,
		"actor overlapping the lift's initial body",
		["player_start", "vertical_platform", "lift_1"]
	)


func _test_builder_forward_reference() -> void:
	var arena := await _create_embedded_runtime(
		_make_forward_reference_level()
	)
	_expect(
		is_instance_valid(arena) and arena.level_loaded,
		"Forward-reference lift level did not load."
	)
	if not is_instance_valid(arena) or not arena.level_loaded:
		await _cleanup_current_scene()
		return

	var lift := arena.get_level_object("lift_1") as VerticalPlatform
	var hinge := arena.get_level_object("lift_hinge") as Hinge
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	if (
		not is_instance_valid(lift)
		or not is_instance_valid(hinge)
		or not is_instance_valid(shooter)
	):
		failures.append(
			"Builder did not create the lift, hinge, and shooter."
		)
		await _cleanup_current_scene()
		return

	var body_shape := (
		lift.platform.get_node(
			"CollisionShape2D"
		) as CollisionShape2D
	).shape as RectangleShape2D
	var cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_lift_hinge"
	) as Line2D
	_expect(
		lift.get_parent() == arena.get_node("Geometry/LevelObjects")
		and lift.position.is_equal_approx(Vector2(460, 330))
		and lift.travel_offset.is_equal_approx(Vector2(0, 136))
		and is_equal_approx(lift.warning_time, 0.25)
		and is_equal_approx(lift.travel_time, 1.0)
		and not lift.starts_lowered
		and not lift.is_lowered
		and not lift.is_transitioning
		and lift.platform.position.is_equal_approx(Vector2.ZERO)
		and body_shape.size.is_equal_approx(Vector2(80, 20))
		and lift.track.points == PackedVector2Array(
			[Vector2.ZERO, Vector2(0, 136)]
		)
		and lift.lower_stop.position.is_equal_approx(Vector2(0, 136))
		and not lift.target_preview.visible
		and hinge.target == lift
		and is_instance_valid(cable)
		and cable.points == PackedVector2Array(
			[Vector2(250, 468), Vector2(460, 330)]
		)
		and arena.enemies_remaining == 1,
		"Builder lift preset, geometry, link, or parent drifted."
	)
	await _cleanup_current_scene()


func _test_passenger_round_trip() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_07_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 07 passenger fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 07 passenger fixture did not load.")
		await _cleanup_current_scene()
		return

	var lift := arena.get_level_object("lift_1") as VerticalPlatform
	var hinge := arena.get_level_object("lift_hinge") as Hinge
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	if (
		not is_instance_valid(lift)
		or not is_instance_valid(hinge)
		or not is_instance_valid(shooter)
		or not is_instance_valid(player)
	):
		failures.append("Arena 07 passenger nodes were not built.")
		await _cleanup_current_scene()
		return

	shooter.line_length = 0.0
	player.global_position = Vector2(480, 280)
	player.velocity = Vector2.ZERO
	shooter.velocity = Vector2.ZERO
	for _frame in range(60):
		await physics_frame

	var upper_platform_position := lift.platform.global_position
	var shooter_upper := shooter.global_position
	var player_upper := player.global_position
	var shooter_relative := shooter_upper - upper_platform_position
	var player_relative := player_upper - upper_platform_position
	_expect(
		shooter.is_on_floor()
		and player.is_on_floor()
		and shooter_relative.distance_to(Vector2(-21, -29)) < 1.0
		and player_relative.distance_to(Vector2(20, -30)) < 1.0,
		"Player or shooter did not settle on the upper lift stop."
	)

	lift.warning_time = 0.0
	lift.travel_time = 0.35
	var toggles: Array[bool] = []
	lift.toggled.connect(
		func(is_lowered: bool) -> void:
			toggles.append(is_lowered)
	)
	hinge.receive_impulse(Vector2.ZERO)
	var duplicate_request_rejected := not lift.request_toggle()
	var lowered := await _wait_for_lift(lift, true)
	for _frame in range(30):
		await physics_frame
		if hinge.is_ready:
			break

	var shooter_lower := shooter.global_position
	var player_lower := player.global_position
	_expect(
		duplicate_request_rejected
		and lowered
		and hinge.is_ready
		and lift.platform.position.is_equal_approx(Vector2(0, 136))
		and shooter_lower.distance_to(
			shooter_upper + Vector2(0, 136)
		) < 1.5
		and player_lower.distance_to(
			player_upper + Vector2(0, 136)
		) < 1.5
		and shooter.is_on_floor()
		and player.is_on_floor(),
		"Lift did not carry both passengers to the lower stop."
	)

	hinge.receive_impulse(Vector2.ZERO)
	var raised := await _wait_for_lift(lift, false)
	for _frame in range(30):
		await physics_frame
		if hinge.is_ready:
			break
	_expect(
		raised
		and hinge.is_ready
		and lift.platform.position.is_equal_approx(Vector2.ZERO)
		and shooter.global_position.distance_to(shooter_upper) < 1.5
		and player.global_position.distance_to(player_upper) < 1.5
		and toggles == [true, false],
		"Lift did not return its passengers and signal both stops."
	)
	await _cleanup_current_scene()


func _test_shooter_height_and_goal() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_07_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 07 height fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 07 height fixture did not load.")
		await _cleanup_current_scene()
		return
	arena.clear_restart_delay = 10.0

	var lift := arena.get_level_object("lift_1") as VerticalPlatform
	var hinge := arena.get_level_object("lift_hinge") as Hinge
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	if (
		not is_instance_valid(lift)
		or not is_instance_valid(hinge)
		or not is_instance_valid(shooter)
		or not is_instance_valid(player)
	):
		failures.append("Arena 07 height nodes were not built.")
		await _cleanup_current_scene()
		return

	shooter.aim_time = 1000.0
	shooter.state_time_remaining = 1000.0
	for _frame in range(60):
		await physics_frame

	shooter.call("_track_player")
	shooter.aim_ray.force_raycast_update()
	var upper_line_is_open := not shooter.aim_ray.is_colliding()
	var shooter_upper_y := shooter.global_position.y

	lift.warning_time = 0.0
	lift.travel_time = 0.35
	hinge.receive_impulse(Vector2.ZERO)
	var lowered := await _wait_for_lift(lift, true)
	for _frame in range(10):
		await physics_frame
	shooter.call("_track_player")
	shooter.aim_ray.force_raycast_update()
	var lower_collider := shooter.aim_ray.get_collider() as Node
	var lower_blocker_id := (
		str(lower_collider.get_meta("level_object_id", ""))
		if is_instance_valid(lower_collider)
		else ""
	)
	_expect(
		upper_line_is_open
		and lowered
		and absf(
			shooter.global_position.y - shooter_upper_y - 136.0
		) < 1.0
		and shooter.aim_ray.is_colliding()
		and lower_blocker_id == "cover",
		"Lift height did not change the shooter line from open to covered."
	)

	var enemy_present_before_attack := (
		arena.enemies_remaining == 1
		and is_instance_valid(shooter)
	)
	player.global_position = Vector2(385, shooter.global_position.y)
	player.velocity = Vector2.ZERO
	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	await physics_frame
	await _press_physical_key(KEY_X)
	var attack_started := player.attack_time_remaining > 0.0
	player.set_physics_process(false)
	player.global_position = Vector2(120, 476)

	for _frame in range(240):
		await physics_frame
		if arena.enemies_remaining == 0:
			break
	_expect(
		enemy_present_before_attack
		and attack_started
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR,
		(
			"A real attack from the lowered lift did not clear Arena 07: "
			+ "enemy_before=%s attack=%s enemies=%d outcome=%d."
		)
		% [
			enemy_present_before_attack,
			attack_started,
			arena.enemies_remaining,
			arena.pending_outcome,
		]
	)
	await _cleanup_current_scene()


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	var arena_07_index := _load_entry_index(editor, "arena_07_data")
	_expect(
		arena_07_index >= 0,
		"Editor does not list the Arena 07 built-in."
	)
	if arena_07_index < 0:
		await _cleanup_current_scene()
		return
	editor.call("_perform_load_selected_level", arena_07_index)
	await process_frame

	editor.call("_select_object", "lift_1")
	await process_frame
	var x_editor := _find_property_editor(editor, "X")
	var y_editor := _find_property_editor(editor, "Y")
	var size_value := _find_property_editor(editor, "SIZE")
	var travel_value := _find_property_editor(editor, "TRAVEL")
	_expect(
		editor.source_label == "ПРИМЕР"
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and x_editor is LineEdit
		and y_editor is LineEdit
		and size_value is Label
		and travel_value is Label
		and not is_instance_valid(
			_find_property_editor(editor, "DIRECTION")
		)
		and not is_instance_valid(
			_find_property_editor(editor, "STARTS LOWERED")
		)
		and "136 PX" in editor.inspector_hint.text,
		"Lift built-in or compact inspector is incorrect."
	)

	var preview_passengers := editor.canvas.call(
		"_vertical_platform_passengers",
		Vector2(460, 330),
		"lift_1"
	) as Array[Dictionary]
	var preview_passenger_ids: Array[String] = []
	for passenger: Dictionary in preview_passengers:
		preview_passenger_ids.append(str(passenger.get("id", "")))
	var preview_shooter := _dictionary_by_id(
		preview_passengers,
		"shooter_1"
	)
	var shooter_destination: Vector2 = editor.canvas.call(
		"_vertical_platform_passenger_destination",
		preview_shooter,
		Vector2(460, 330)
	)
	var destination_blockers := editor.canvas.call(
		"_vertical_platform_destination_blockers",
		Vector2(460, 330),
		"lift_1"
	) as Array[Dictionary]
	var destination_lift_blocker := _dictionary_by_id(
		destination_blockers,
		"lift_1"
	)
	var player_destination: Vector2 = (
		LevelEditorCanvas._resting_actor_position(
			LevelEditorCanvas.TOOL_PLAYER_SPAWN,
			Vector2(120, 450),
			destination_blockers
		)
	)
	var lower_aim := LevelEditorCanvas.shooter_aim_preview(
		shooter_destination,
		player_destination,
		destination_blockers
	)
	_expect(
		preview_passenger_ids == ["shooter_1"]
		and shooter_destination.is_equal_approx(Vector2(439, 437))
		and player_destination.is_equal_approx(Vector2(120, 476))
		and destination_lift_blocker.get(
			"rect",
			Rect2()
		).is_equal_approx(Rect2(420, 456, 80, 20))
		and lower_aim.get("blocker_id", "") == "cover",
		"Lift passenger ghost or lower shooter preview drifted."
	)

	editor.canvas.grab_focus()
	await process_frame
	await _press_physical_key(KEY_9)
	await process_frame
	_expect(
		editor.active_tool == "vertical_platform"
		and editor.lift_button.button_pressed
		and editor.tool_scroll.get_global_rect().encloses(
			editor.lift_button.get_global_rect()
		),
		"Physical 9 did not select and reveal the lift tool."
	)

	editor.canvas.call(
		"_begin_primary_action",
		Vector2(600, 300) * 0.6
	)
	await process_frame
	var placed_id: String = editor.selected_id
	var placed := editor.draft.find_object(placed_id)
	var hit := editor.canvas.call(
		"_hit_test",
		Vector2(600, 400)
	) as Dictionary
	var shooter_blockers := editor.canvas.call(
		"_shooter_blockers"
	) as Array[Dictionary]
	var lift_blocker := _dictionary_by_id(
		shooter_blockers,
		"lift_1"
	)
	_expect(
		placed.get("type", "") == "vertical_platform"
		and placed.get("position", []) == [600, 300]
		and placed.keys().size() == 3
		and hit.get("id", "") == placed_id
		and lift_blocker.get(
			"rect",
			Rect2()
		).is_equal_approx(Rect2(420, 320, 80, 20)),
		"Lift placement, corridor hit-test, or shooter blocker is incorrect."
	)

	editor.call("_nudge_selected", Vector2i.LEFT, false)
	_expect(
		editor.draft.find_object(placed_id)["position"] == [580, 300],
		"Lift nudge did not use the editor grid."
	)
	editor.call("_duplicate_selected")
	var duplicate_id: String = editor.selected_id
	var duplicate := editor.draft.find_object(duplicate_id)
	_expect(
		duplicate_id != placed_id
		and duplicate.get("position", []) == [660, 300]
		and duplicate.keys().size() == 3
		and bool(editor.validation_result.get("ok", false)),
		"Lift duplicate leaked tuning or used the wrong offset."
	)

	editor.call("_select_object", placed_id)
	editor.draft.update_object(placed_id, {"position": [888, 394]})
	editor.call("_nudge_selected", Vector2i.RIGHT, false)
	editor.call("_nudge_selected", Vector2i.DOWN, false)
	editor.call("_duplicate_selected")
	var edge_duplicate_id: String = editor.selected_id
	_expect(
		editor.draft.find_object(placed_id).get(
			"position",
			[]
		) == [888, 394]
		and editor.draft.find_object(edge_duplicate_id).get(
			"position",
			[]
		) == [808, 394]
		and bool(editor.validation_result.get("ok", false)),
		"Lift nudge or duplicate escaped its valid corridor."
	)

	for _attempt in range(12):
		if not editor.draft.is_dirty():
			break
		editor.call("_undo")
	_expect(
		editor.draft.find_object(placed_id).is_empty()
		and editor.draft.find_object(duplicate_id).is_empty()
		and editor.draft.find_object(edge_duplicate_id).is_empty()
		and not editor.draft.is_dirty(),
		"Lift actions did not undo to the Arena 07 snapshot."
	)

	editor.draft.add_object(
		{
			"id": "alternate_toggle",
			"type": "toggle_platform",
			"rect": [600, 496, 100, 20],
			"starts_active": true,
		}
	)
	editor.draft.update_object(
		"lift_hinge",
		{"target_id": "alternate_toggle"}
	)
	editor.call("_select_object", "lift_hinge")
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
	var target_offers_lift := _option_has_metadata(
		target_options,
		"lift_1"
	)
	editor.call("_begin_linking", "lift_hinge")
	await process_frame
	var link_hit := editor.canvas.call(
		"_hit_test_hinge_target",
		Vector2(460, 400)
	) as Dictionary
	editor.call(
		"_on_link_target_requested",
		str(link_hit.get("id", ""))
	)
	await process_frame
	var reassigned_to_lift: bool = (
		editor.draft.find_object(
			"lift_hinge"
		).get("target_id", "") == "lift_1"
		and editor.draft.is_dirty()
	)
	editor.call("_undo")
	var reverted_to_alternate: bool = (
		editor.draft.find_object(
			"lift_hinge"
		).get("target_id", "") == "alternate_toggle"
	)
	editor.call("_undo")
	editor.call("_undo")
	_expect(
		target_selected == "alternate_toggle"
		and target_offers_lift
		and link_hit.get("id", "") == "lift_1"
		and reassigned_to_lift
		and reverted_to_alternate
		and editor.draft.find_object(
			"lift_hinge"
		).get("target_id", "") == "lift_1"
		and editor.draft.find_object("alternate_toggle").is_empty()
		and editor.linking_hinge_id.is_empty()
		and not editor.draft.is_dirty(),
		"Hinge dropdown, field-link reassignment, or Undo did not accept the lift."
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var warning_runtime := editor.playtest_runtime as LevelRuntimeArena
	var warning_lift := (
		warning_runtime.get_level_object(
			"lift_1"
		) as VerticalPlatform
		if is_instance_valid(warning_runtime)
		else null
	)
	var warning_runtime_ref: WeakRef = weakref(warning_runtime)
	var warning_lift_ref: WeakRef = weakref(warning_lift)
	if is_instance_valid(warning_lift):
		warning_lift.warning_time = 10.0
		warning_lift.request_toggle()
	var warning_started := (
		is_instance_valid(warning_lift)
		and warning_lift.is_transitioning
		and not warning_lift.is_moving
		and warning_lift.target_preview.visible
	)
	var warning_runtime_id := warning_runtime.get_instance_id()
	warning_runtime.call("_reload_scene")
	await _wait_for_replaced_playtest(editor, warning_runtime_id)

	var moving_runtime := editor.playtest_runtime as LevelRuntimeArena
	var moving_lift := (
		moving_runtime.get_level_object(
			"lift_1"
		) as VerticalPlatform
		if is_instance_valid(moving_runtime)
		else null
	)
	var moving_runtime_ref: WeakRef = weakref(moving_runtime)
	var moving_lift_ref: WeakRef = weakref(moving_lift)
	if is_instance_valid(moving_lift):
		moving_lift.warning_time = 0.0
		moving_lift.travel_time = 1.0
		moving_lift.request_toggle()
	var movement_started := await _wait_for_lift_motion(moving_lift)
	var moving_runtime_id := moving_runtime.get_instance_id()
	moving_runtime.call("_reload_scene")
	await _wait_for_replaced_playtest(editor, moving_runtime_id)

	var restarted_runtime := (
		editor.playtest_runtime as LevelRuntimeArena
	)
	var restarted_lift := (
		restarted_runtime.get_level_object(
			"lift_1"
		) as VerticalPlatform
		if is_instance_valid(restarted_runtime)
		else null
	)
	var restarted_hinge := (
		restarted_runtime.get_level_object(
			"lift_hinge"
		) as Hinge
		if is_instance_valid(restarted_runtime)
		else null
	)
	_expect(
		warning_started
		and movement_started
		and warning_runtime_ref.get_ref() == null
		and warning_lift_ref.get_ref() == null
		and moving_runtime_ref.get_ref() == null
		and moving_lift_ref.get_ref() == null
		and is_instance_valid(restarted_runtime)
		and restarted_runtime.level_loaded
		and is_instance_valid(restarted_lift)
		and not restarted_lift.is_transitioning
		and not restarted_lift.is_lowered
		and restarted_lift.platform.position.is_equal_approx(
			Vector2.ZERO
		)
		and is_instance_valid(restarted_hinge)
		and restarted_hinge.target == restarted_lift,
		"Restart did not replace warning and moving lift playtests cleanly."
	)

	var stop_lift_ref: WeakRef = weakref(restarted_lift)
	if is_instance_valid(restarted_lift):
		restarted_lift.warning_time = 0.0
		restarted_lift.travel_time = 1.0
		restarted_lift.request_toggle()
	var stop_movement_started := await _wait_for_lift_motion(
		restarted_lift
	)
	editor.call("_stop_playtest")
	await process_frame
	await process_frame
	_expect(
		stop_movement_started
		and stop_lift_ref.get_ref() == null
		and _count_lifts(editor) == 0,
		"Lift survived stopping the embedded playtest."
	)
	await _cleanup_current_scene()


func _make_forward_reference_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "lift_forward_smoke",
		"title": "LIFT FORWARD SMOKE",
		"objective": "TEST",
		"clear_message": "CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "lift_hinge",
				"type": "hinge",
				"position": [250, 468],
				"target_id": "lift_1",
			},
			{
				"id": "floor",
				"type": "solid_rect",
				"rect": [32, 496, 328, 44],
			},
			{
				"id": "cover",
				"type": "solid_rect",
				"rect": [324, 430, 36, 66],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [120, 450],
			},
			{
				"id": "shooter_1",
				"type": "shooter_enemy",
				"position": [439, 270],
			},
			{
				"id": "lift_1",
				"type": "vertical_platform",
				"position": [460, 330],
			},
		],
	}


func _make_bounds_level(lift_position: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "lift_bounds_smoke",
		"title": "LIFT BOUNDS SMOKE",
		"objective": "TEST",
		"clear_message": "CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [200, 200],
			},
			{
				"id": "shooter_1",
				"type": "shooter_enemy",
				"position": [700, 200],
			},
			{
				"id": "lift_hinge",
				"type": "hinge",
				"position": [300, 400],
				"target_id": "lift_1",
			},
			{
				"id": "lift_1",
				"type": "vertical_platform",
				"position": lift_position.duplicate(),
			},
		],
	}


func _create_embedded_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded["ok"]),
		"Could not encode embedded lift fixture: %s"
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


func _wait_for_lift(
	lift: VerticalPlatform,
	target_lowered: bool
) -> bool:
	for _frame in range(180):
		await physics_frame
		if (
			is_instance_valid(lift)
			and not lift.is_transitioning
			and lift.is_lowered == target_lowered
		):
			return true
	return false


func _wait_for_lift_motion(lift: VerticalPlatform) -> bool:
	for _frame in range(30):
		await process_frame
		await physics_frame
		if is_instance_valid(lift) and lift.is_moving:
			return true
	return false


func _wait_for_replaced_playtest(
	editor: LevelEditor,
	old_runtime_id: int
) -> void:
	for _frame in range(30):
		await process_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and (
				editor.playtest_runtime.get_instance_id()
				!= old_runtime_id
			)
		):
			return


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


func _option_has_metadata(
	options: OptionButton,
	expected: String
) -> bool:
	if not is_instance_valid(options):
		return false
	for index in options.item_count:
		if str(options.get_item_metadata(index)) == expected:
			return true
	return false


func _count_lifts(node: Node) -> int:
	var count := 1 if node is VerticalPlatform else 0
	for child: Node in node.get_children():
		count += _count_lifts(child)
	return count


func _load_entry_index(editor: LevelEditor, entry_id: String) -> int:
	for index in editor.load_entries.size():
		var entry: Dictionary = editor.load_entries[index]
		if entry.get("id", "") == entry_id:
			return index
	return -1


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


func _expect_valid(data: Dictionary, label: String) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(
		bool(result["ok"]),
		"Validator rejected %s: %s."
		% [label, str(result["errors"])]
	)


func _expect_invalid(data: Dictionary, label: String) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(not bool(result["ok"]), "Validator accepted %s." % label)


func _expect_invalid_with_fragments(
	data: Dictionary,
	label: String,
	fragments: Array[String]
) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	var has_all_fragments := true
	for fragment: String in fragments:
		if not _contains_text(result["errors"], fragment):
			has_all_fragments = false
			break
	_expect(
		not bool(result["ok"]) and has_all_fragments,
		(
			"Validator did not reject %s with %s; got %s."
			% [label, str(fragments), str(result["errors"])]
		)
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const RUNTIME_SCENE := preload("res://scenes/data_arena_01.tscn")
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)

var failures: Array[String] = []
var active_test_scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_builtin_fixture()
	await _test_real_exam_solution()
	await _test_editor_lifecycle()

	if failures.is_empty():
		print("EXAM_ARENA_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_builtin_fixture() -> void:
	var builtins := LEVEL_STORAGE.list_builtin_levels()
	var arena_07_index := _dictionary_index_by_id(
		builtins,
		"arena_07_data"
	)
	var arena_08_index := _dictionary_index_by_id(
		builtins,
		"arena_08_data"
	)
	_expect(
		arena_07_index >= 0
		and arena_07_index < arena_08_index
		and builtins[arena_08_index] == {
			"id": "arena_08_data",
			"path": "res://levels/arena_08.json",
			"title": "Arena 08 / Экзамен",
		},
		"Built-in catalog does not expose Arena 08 after Arena 07."
	)

	var loaded := LEVEL_STORAGE.load_builtin_level("arena_08_data")
	_expect(
		bool(loaded.get("ok", false))
		and loaded.get("path", "") == "res://levels/arena_08.json"
		and (loaded.get("warnings", []) as Array).is_empty(),
		"Arena 08 built-in JSON did not load cleanly."
	)
	if not bool(loaded.get("ok", false)):
		return

	var data: Dictionary = loaded["data"]
	var fixture_ids: Array[String] = []
	for object: Dictionary in data.get("objects", []):
		fixture_ids.append(str(object.get("id", "")))
	_expect(
		data.keys().size() == 7
		and data.get("schema_version", 0) == 1
		and data.get("level_id", "") == "arena_08_data"
		and data.get("title", "")
		== "GRAYBOX  /  DATA ARENA 08  /  ЭКЗАМЕН"
		and data.get("objective", "")
		== "ТРИ ВРАГА  /  ТРИ МЕХАНИЗМА"
		and data.get("clear_message", "")
		== "ЭКЗАМЕН ПРОЙДЕН  /  ПЕРЕЗАПУСК..."
		and data.get("canvas", {}) == {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		}
		and fixture_ids == [
			"left_floor",
			"right_floor",
			"cover",
			"player_start",
			"patrol_1",
			"shove_1",
			"shooter_1",
			"bridge_1",
			"catapult_1",
			"lift_1",
			"bridge_hinge",
			"catapult_hinge",
			"lift_hinge",
		],
		"Arena 08 metadata or stable object order drifted."
	)
	_expect(
		_object_by_id(data, "left_floor").get(
			"rect",
			[]
		) == [32, 496, 288, 44]
		and _object_by_id(data, "right_floor").get(
			"rect",
			[]
		) == [640, 496, 160, 44]
		and _object_by_id(data, "cover").get(
			"rect",
			[]
		) == [764, 430, 36, 66]
		and _object_by_id(data, "player_start").get(
			"position",
			[]
		) == [140, 450]
		and _object_by_id(data, "patrol_1").get(
			"position",
			[]
		) == [430, 250]
		and _object_by_id(data, "patrol_1").get("speed", 0) == 40
		and _object_by_id(data, "patrol_1").get(
			"direction",
			0
		) == 1
		and _object_by_id(data, "shove_1").get(
			"position",
			[]
		) == [480, 430]
		and _object_by_id(data, "shove_1").get(
			"direction",
			0
		) == 1
		and _object_by_id(data, "shove_1").get(
			"behavior_preset",
			""
		) == "exam"
		and _object_by_id(data, "shooter_1").get(
			"position",
			[]
		) == [819, 270]
		and _object_by_id(data, "shooter_1").get(
			"behavior_preset",
			""
		) == "exam",
		"Arena 08 static geometry or actors drifted."
	)
	_expect(
		_object_by_id(data, "bridge_1").get(
			"rect",
			[]
		) == [380, 476, 200, 20]
		and bool(
			_object_by_id(data, "bridge_1").get(
				"starts_active",
				false
			)
		)
		and _object_by_id(data, "catapult_1").get(
			"position",
			[]
		) == [340, 320]
		and _object_by_id(data, "catapult_1").get(
			"behavior_preset",
			""
		) == "exam"
		and _object_by_id(data, "lift_1").get(
			"position",
			[]
		) == [840, 330]
		and _link_matches(
			data,
			"bridge_hinge",
			[460, 455],
			"bridge_1"
		)
		and _link_matches(
			data,
			"catapult_hinge",
			[680, 390],
			"catapult_1"
		)
		and _link_matches(
			data,
			"lift_hinge",
			[750, 468],
			"lift_1"
		),
		"Arena 08 mechanisms or links drifted."
	)

	var encoded_once := LEVEL_DATA_CODEC.encode(data)
	var decoded := LEVEL_DATA_CODEC.decode_text(
		encoded_once.get("text", "")
	)
	var encoded_twice := LEVEL_DATA_CODEC.encode(
		decoded.get("data", {})
	)
	_expect(
		bool(encoded_once.get("ok", false))
		and bool(decoded.get("ok", false))
		and bool(encoded_twice.get("ok", false))
		and encoded_once.get("text", "")
		== encoded_twice.get("text", ""),
		"Arena 08 JSON is not deterministic across a round trip."
	)
	var reserved_id := (
		LEVEL_STORAGE.next_available_level_id("arena_08_data")
	)
	_expect(
		bool(reserved_id.get("ok", false))
		and reserved_id.get("data", "") != "arena_08_data",
		"Generated user ID collided with the Arena 08 built-in."
	)


func _test_real_exam_solution() -> void:
	var loaded := LEVEL_STORAGE.load_builtin_level("arena_08_data")
	if not bool(loaded.get("ok", false)):
		failures.append("Could not prepare the Arena 08 fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 08 embedded playtest did not load.")
		await _cleanup_current_scene()
		return
	arena.clear_restart_delay = 10.0

	var left_floor := (
		arena.get_level_object("left_floor") as LevelSolidRect
	)
	var right_floor := (
		arena.get_level_object("right_floor") as LevelSolidRect
	)
	var cover := arena.get_level_object("cover") as LevelSolidRect
	var player := arena.get_level_object("player_start") as Player
	var patrol := arena.get_level_object("patrol_1") as PatrolEnemy
	var shove := arena.get_level_object("shove_1") as ShoveEnemy
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	var bridge := arena.get_level_object("bridge_1") as TogglePlatform
	var catapult := (
		arena.get_level_object("catapult_1") as RotatingPlatform
	)
	var lift := arena.get_level_object("lift_1") as VerticalPlatform
	var bridge_hinge := (
		arena.get_level_object("bridge_hinge") as Hinge
	)
	var catapult_hinge := (
		arena.get_level_object("catapult_hinge") as Hinge
	)
	var lift_hinge := arena.get_level_object("lift_hinge") as Hinge
	var bridge_cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_bridge_hinge"
	) as Line2D
	var catapult_cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_catapult_hinge"
	) as Line2D
	var lift_cable := arena.get_node_or_null(
		"Geometry/LevelObjects/Link_lift_hinge"
	) as Line2D
	_expect(
		is_instance_valid(left_floor)
		and is_instance_valid(right_floor)
		and is_instance_valid(cover)
		and is_instance_valid(player)
		and is_instance_valid(patrol)
		and is_instance_valid(shove)
		and is_instance_valid(shooter)
		and is_instance_valid(bridge)
		and is_instance_valid(catapult)
		and is_instance_valid(lift)
		and is_instance_valid(bridge_hinge)
		and is_instance_valid(catapult_hinge)
		and is_instance_valid(lift_hinge)
		and is_instance_valid(bridge_cable)
		and is_instance_valid(catapult_cable)
		and is_instance_valid(lift_cable),
		"Builder did not create every Arena 08 object."
	)
	if (
		not is_instance_valid(left_floor)
		or not is_instance_valid(right_floor)
		or not is_instance_valid(cover)
		or not is_instance_valid(player)
		or not is_instance_valid(patrol)
		or not is_instance_valid(shove)
		or not is_instance_valid(shooter)
		or not is_instance_valid(bridge)
		or not is_instance_valid(catapult)
		or not is_instance_valid(lift)
		or not is_instance_valid(bridge_hinge)
		or not is_instance_valid(catapult_hinge)
		or not is_instance_valid(lift_hinge)
		or not is_instance_valid(bridge_cable)
		or not is_instance_valid(catapult_cable)
		or not is_instance_valid(lift_cable)
	):
		await _cleanup_current_scene()
		return

	_expect(
		_exam_presets_match(shove, shooter, catapult)
		and _solid_matches(
			left_floor,
			Vector2(176, 518),
			Vector2(288, 44)
		)
		and _solid_matches(
			right_floor,
			Vector2(720, 518),
			Vector2(160, 44)
		)
		and _solid_matches(
			cover,
			Vector2(782, 463),
			Vector2(36, 66)
		)
		and is_equal_approx(patrol.patrol_speed, 40.0)
		and patrol.patrol_direction == 1.0
		and bridge.position.is_equal_approx(Vector2(480, 486))
		and bridge.platform_size.is_equal_approx(Vector2(200, 20))
		and bridge.is_active
		and is_equal_approx(bridge.transition_time, 0.18)
		and catapult.position.is_equal_approx(Vector2(340, 320))
		and lift.position.is_equal_approx(Vector2(840, 330))
		and lift.travel_offset.is_equal_approx(Vector2(0, 136))
		and is_equal_approx(lift.warning_time, 0.25)
		and is_equal_approx(lift.travel_time, 1.0)
		and not lift.starts_lowered
		and bridge_hinge.target == bridge
		and catapult_hinge.target == catapult
		and lift_hinge.target == lift
		and is_equal_approx(bridge_hinge.cooldown, 0.35)
		and is_equal_approx(catapult_hinge.cooldown, 0.35)
		and is_equal_approx(lift_hinge.cooldown, 0.35)
		and _link_line_matches(
			bridge_cable,
			"bridge_hinge",
			PackedVector2Array(
				[Vector2(460, 455), Vector2(480, 486)]
			)
		)
		and _link_line_matches(
			catapult_cable,
			"catapult_hinge",
			PackedVector2Array(
				[Vector2(680, 390), Vector2(340, 320)]
			)
		)
		and _link_line_matches(
			lift_cable,
			"lift_hinge",
			PackedVector2Array(
				[Vector2(750, 468), Vector2(840, 330)]
			)
		)
		and arena.enemies_remaining == 3,
		"Arena 08 exam presets, geometry, links, or enemy count drifted."
	)

	for _frame in range(60):
		await physics_frame
		if (
			player.is_on_floor()
			and patrol.is_on_floor()
			and shove.is_on_floor()
			and shooter.is_on_floor()
		):
			break
	_expect(
		player.global_position.distance_to(Vector2(140, 476)) <= 1.0
		and absf(patrol.global_position.y - 292.0) <= 1.0
		and patrol.global_position.x >= 355.0
		and patrol.global_position.x <= 505.0
		and shove.global_position.distance_to(Vector2(480, 457)) <= 1.0
		and shooter.global_position.distance_to(Vector2(819, 301)) <= 1.0,
		(
			"Arena 08 actors did not settle on their legacy supports: "
			+ "player=%s patrol=%s shove=%s shooter=%s."
		) % [
			player.global_position,
			patrol.global_position,
			shove.global_position,
			shooter.global_position,
		]
	)

	# Keep the unrelated ranged threat deterministic after proving its preset.
	shooter.aim_time = 1000.0
	shooter.call("_enter_ready")

	player.global_position = Vector2(390, 456)
	player.velocity = Vector2.ZERO
	var saw_shove_telegraph := false
	for _frame in range(30):
		await physics_frame
		if shove.state == ShoveEnemy.State.TELEGRAPH:
			saw_shove_telegraph = true
			break
	_expect(
		saw_shove_telegraph
		and shove.lunge_direction == -1.0
		and shove.state_time_remaining > 1.0,
		"Player did not provoke the long Arena 08 shove telegraph."
	)
	if not saw_shove_telegraph:
		await _cleanup_current_scene()
		return

	player.global_position = Vector2(700, 476)
	player.velocity = Vector2.ZERO
	var saw_shove_lunge := false
	var saw_bridge_transition := false
	var bridge_was_disabled := false
	for _frame in range(180):
		await physics_frame
		saw_shove_lunge = (
			saw_shove_lunge
			or is_instance_valid(shove)
			and shove.state == ShoveEnemy.State.LUNGE
		)
		saw_bridge_transition = (
			saw_bridge_transition or bridge.is_transitioning
		)
		bridge_was_disabled = (
			bridge_was_disabled
			or not bridge.is_active
			and (
				bridge.get_node(
					"CollisionShape2D"
				) as CollisionShape2D
			).disabled
		)
		if arena.enemies_remaining == 2:
			break
	await process_frame
	_expect(
		saw_shove_lunge
		and saw_bridge_transition
		and bridge_was_disabled
		and arena.enemies_remaining == 2
		and not is_instance_valid(shove),
		(
			"Real shove lunge did not hit the bridge hinge and fall: "
			+ "lunge=%s transition=%s disabled=%s enemies=%d "
			+ "shove_valid=%s shove_pos=%s."
		) % [
			saw_shove_lunge,
			saw_bridge_transition,
			bridge_was_disabled,
			arena.enemies_remaining,
			is_instance_valid(shove),
			shove.global_position if is_instance_valid(shove) else Vector2.ZERO,
		]
	)

	var launch_counts: Array[int] = []
	catapult.launched.connect(
		func(body_count: int) -> void:
			launch_counts.append(body_count)
	)
	player.global_position = Vector2(646, 390)
	player.velocity = Vector2.ZERO
	_face_player(player, 1.0)
	await _press_physical_key(KEY_X)
	var saw_catapult_transition := false
	var patrol_was_launched := false
	for _frame in range(180):
		await physics_frame
		saw_catapult_transition = (
			saw_catapult_transition or catapult.is_transitioning
		)
		patrol_was_launched = (
			patrol_was_launched
			or not launch_counts.is_empty()
			and launch_counts[0] == 1
		)
		if arena.enemies_remaining == 1:
			break
	await process_frame
	_expect(
		saw_catapult_transition
		and patrol_was_launched
		and arena.enemies_remaining == 1
		and not is_instance_valid(patrol),
		(
			"Real player attack did not launch the patrol into the center pit: "
			+ "transition=%s launched=%s body_count=%d enemies=%d "
			+ "patrol_valid=%s patrol_pos=%s."
		) % [
			saw_catapult_transition,
			patrol_was_launched,
			launch_counts[0] if not launch_counts.is_empty() else -1,
			arena.enemies_remaining,
			is_instance_valid(patrol),
			(
				patrol.global_position
				if is_instance_valid(patrol)
				else Vector2.ZERO
			),
		]
	)

	player.global_position = Vector2(716, 468)
	player.velocity = Vector2.ZERO
	_face_player(player, 1.0)
	await _press_physical_key(KEY_X)
	var saw_lift_transition := false
	for _frame in range(120):
		await physics_frame
		saw_lift_transition = (
			saw_lift_transition or lift.is_transitioning
		)
		if lift.is_lowered and not lift.is_transitioning:
			break
	_expect(
		saw_lift_transition
		and lift.is_lowered
		and lift.platform.position.is_equal_approx(Vector2(0, 136))
		and absf(shooter.global_position.y - 437.0) <= 2.0,
		"Real player attack did not lower the Arena 08 shooter."
	)

	player.global_position = Vector2(780, 410)
	player.velocity = Vector2.ZERO
	_face_player(player, 1.0)
	await physics_frame
	await _press_physical_key(KEY_X)
	var shooter_was_hit := false
	for _frame in range(240):
		await physics_frame
		shooter_was_hit = (
			shooter_was_hit
			or is_instance_valid(shooter)
			and shooter.knockback_time_remaining > 0.0
		)
		if arena.restart_scheduled:
			break
	await process_frame
	_expect(
		shooter_was_hit
		and is_instance_valid(player)
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR,
		"Final real player attack did not clear Arena 08."
	)
	await _cleanup_current_scene()


func _test_editor_lifecycle() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	active_test_scene = editor
	await process_frame

	var arena_08_index := _dictionary_index_by_id(
		editor.load_entries,
		"arena_08_data"
	)
	_expect(
		arena_08_index >= 0
		and editor.load_entries[arena_08_index].get("kind", "")
		== "builtin",
		"Editor does not list Arena 08 as a built-in example."
	)
	if arena_08_index < 0:
		await _cleanup_current_scene()
		return
	editor.call("_perform_load_selected_level", arena_08_index)
	await process_frame

	var preset_ids := ["shove_1", "shooter_1", "catapult_1"]
	var presets_are_exam := true
	for object_id: String in preset_ids:
		editor.call("_select_object", object_id)
		await process_frame
		var options := (
			_find_property_editor(editor, "PRESET") as OptionButton
		)
		presets_are_exam = (
			presets_are_exam
			and _selected_option_metadata(options) == "exam"
			and "PRESET EXAM" in editor.inspector_hint.text
		)
	var links_are_resolved := true
	for pair: Array in [
		["bridge_hinge", "bridge_1"],
		["catapult_hinge", "catapult_1"],
		["lift_hinge", "lift_1"],
	]:
		editor.call("_select_object", pair[0])
		await process_frame
		var options := (
			_find_property_editor(editor, "TARGET") as OptionButton
		)
		links_are_resolved = (
			links_are_resolved
			and _selected_option_metadata(options) == pair[1]
		)
	var draft_before := editor.draft.to_dictionary()
	_expect(
		editor.source_label == "ПРИМЕР"
		and editor.loaded_user_level_id.is_empty()
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and presets_are_exam
		and links_are_resolved,
		"Editor did not preserve Arena 08 presets or links."
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var runtime := editor.playtest_runtime as LevelRuntimeArena
	var runtime_shove := (
		runtime.get_level_object("shove_1") as ShoveEnemy
		if is_instance_valid(runtime)
		else null
	)
	var runtime_catapult := (
		runtime.get_level_object("catapult_1") as RotatingPlatform
		if is_instance_valid(runtime)
		else null
	)
	_expect(
		is_instance_valid(runtime)
		and runtime.level_loaded
		and is_instance_valid(runtime_shove)
		and is_zero_approx(runtime_shove.patrol_speed)
		and is_instance_valid(runtime_catapult)
		and runtime_catapult.launch_impulse.is_equal_approx(
			Vector2(180, -80)
		),
		"Editor playtest did not build the Arena 08 exam presets."
	)
	if (
		not is_instance_valid(runtime)
		or not is_instance_valid(runtime_shove)
		or not is_instance_valid(runtime_catapult)
	):
		editor.call("_stop_playtest")
		await _cleanup_current_scene()
		return

	var old_runtime_ref: WeakRef = weakref(runtime)
	var old_shove_ref: WeakRef = weakref(runtime_shove)
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
	var restarted_runtime := editor.playtest_runtime as LevelRuntimeArena
	var restarted_shove := (
		restarted_runtime.get_level_object("shove_1") as ShoveEnemy
		if is_instance_valid(restarted_runtime)
		else null
	)
	_expect(
		old_runtime_ref.get_ref() == null
		and old_shove_ref.get_ref() == null
		and is_instance_valid(restarted_runtime)
		and restarted_runtime.level_loaded
		and is_instance_valid(restarted_shove)
		and is_zero_approx(restarted_shove.patrol_speed),
		"Restart did not rebuild the Arena 08 snapshot cleanly."
	)

	var stop_runtime_ref: WeakRef = weakref(restarted_runtime)
	var stop_shove_ref: WeakRef = weakref(restarted_shove)
	editor.call("_stop_playtest")
	await process_frame
	await process_frame
	_expect(
		stop_runtime_ref.get_ref() == null
		and stop_shove_ref.get_ref() == null
		and not is_instance_valid(editor.playtest_runtime)
		and editor.editor_view.visible
		and not editor.playtest_overlay.visible
		and editor.draft.to_dictionary() == draft_before
		and not editor.draft.is_dirty(),
		"Stopping Arena 08 playtest changed the draft or leaked runtime nodes."
	)
	await _cleanup_current_scene()


func _create_embedded_runtime(
	data: Dictionary
) -> LevelRuntimeArena:
	var encoded := LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode Arena 08 fixture: %s"
		% str(encoded.get("errors", []))
	)
	if not bool(encoded.get("ok", false)):
		return null

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(encoded["text"])
	root.add_child(arena)
	active_test_scene = arena
	await process_frame
	return arena


func _face_player(player: Player, direction: float) -> void:
	player.facing_direction = direction
	player.visual.scale.x = direction
	player.attack_pivot.scale.x = direction


func _exam_presets_match(
	shove: ShoveEnemy,
	shooter: ShooterEnemy,
	catapult: RotatingPlatform
) -> bool:
	return (
		shove.patrol_direction == 1.0
		and is_zero_approx(shove.patrol_speed)
		and is_equal_approx(shove.detection_range, 90.0)
		and is_equal_approx(shove.vertical_detection_tolerance, 48.0)
		and is_equal_approx(shove.telegraph_time, 1.4)
		and is_equal_approx(shove.lunge_speed, 420.0)
		and is_equal_approx(shove.lunge_time, 0.28)
		and is_equal_approx(shove.recovery_time, 0.55)
		and is_equal_approx(shove.shove_horizontal_impulse, 520.0)
		and is_equal_approx(shove.shove_vertical_impulse, -140.0)
		and is_equal_approx(shooter.line_length, 900.0)
		and is_equal_approx(shooter.aim_time, 1.0)
		and is_equal_approx(shooter.aim_lock_time, 0.26)
		and is_equal_approx(shooter.cooldown_time, 1.5)
		and is_equal_approx(shooter.muzzle_flash_time, 0.1)
		and is_equal_approx(catapult.warning_time, 0.3)
		and is_equal_approx(catapult.swing_out_time, 0.18)
		and is_equal_approx(catapult.swing_hold_time, 0.08)
		and is_equal_approx(catapult.return_time, 0.28)
		and is_equal_approx(catapult.clearance_time, 0.1)
		and catapult.clearance_attempts == 2
		and is_equal_approx(catapult.swing_angle_degrees, 55.0)
		and is_equal_approx(catapult.launch_direction, 1.0)
		and catapult.launch_impulse.is_equal_approx(
			Vector2(180, -80)
		)
		and catapult.clearance_impulse.is_equal_approx(
			Vector2(420, -360)
		)
	)


func _solid_matches(
	solid: LevelSolidRect,
	expected_position: Vector2,
	expected_size: Vector2
) -> bool:
	var collision := solid.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	var shape := collision.shape as RectangleShape2D
	return (
		solid.position.is_equal_approx(expected_position)
		and solid.rect_size.is_equal_approx(expected_size)
		and not solid.is_one_way
		and is_instance_valid(shape)
		and shape.size.is_equal_approx(expected_size)
		and not collision.one_way_collision
	)


func _link_line_matches(
	line: Line2D,
	source_id: String,
	expected_points: PackedVector2Array
) -> bool:
	return (
		line.points == expected_points
		and line.get_meta("level_link_source_id", "") == source_id
	)


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
	var scene := active_test_scene
	active_test_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
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


func _dictionary_index_by_id(
	entries: Array,
	entry_id: String
) -> int:
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if entry.get("id", "") == entry_id:
			return index
	return -1


func _object_by_id(
	data: Dictionary,
	object_id: String
) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _link_matches(
	data: Dictionary,
	hinge_id: String,
	position: Array,
	target_id: String
) -> bool:
	var hinge := _object_by_id(data, hinge_id)
	return (
		hinge.get("position", []) == position
		and hinge.get("target_id", "") == target_id
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

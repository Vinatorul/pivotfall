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
	await _test_builder_order_and_real_projectile()
	await _test_cover_blocks_first_shot()
	await _test_arena_05_real_clear()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("SHOOTER_ENEMY_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_builtin_schema_and_preview() -> void:
	var builtins := LEVEL_STORAGE.list_builtin_levels()
	_expect(
		builtins.size() >= 3
		and builtins[0]["id"] == "arena_01_data"
		and builtins[1]["id"] == "arena_03_data"
		and builtins[2]["id"] == "arena_05_data",
		"Built-in catalog does not expose Arena 05 after 01 and 03."
	)

	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_05_data")
	)
	_expect(
		bool(loaded["ok"])
		and loaded["data"]["level_id"] == "arena_05_data"
		and _object_by_id(
			loaded.get("data", {}),
			"shooter_1"
		).get("type", "") == "shooter_enemy",
		"Arena 05 did not load with its shooter."
	)
	if not bool(loaded["ok"]):
		return
	var arena_05: Dictionary = loaded["data"]
	var fixture_ids: Array[String] = []
	for object: Dictionary in arena_05["objects"]:
		fixture_ids.append(str(object["id"]))
	_expect(
		fixture_ids == [
			"floor",
			"cover",
			"player_start",
			"shooter_1",
		]
		and _object_by_id(
			arena_05,
			"floor"
		).get("rect", []) == [32, 496, 800, 44]
		and _object_by_id(
			arena_05,
			"cover"
		).get("rect", []) == [454, 416, 52, 80]
		and _object_by_id(
			arena_05,
			"player_start"
		).get("position", []) == [120, 450]
		and _object_by_id(
			arena_05,
			"shooter_1"
		).get("position", []) == [780, 450],
		"Arena 05 fixture geometry or stable object order drifted."
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(loaded["data"])
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
		"Arena 05 JSON is not deterministic across a round trip."
	)

	var reserved_id: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("arena_05_data")
	)
	_expect(
		bool(reserved_id["ok"])
		and reserved_id["data"] != "arena_05_data",
		"Generated user ID collided with the Arena 05 built-in."
	)

	var normalized: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			_make_open_lane_level()
		)
	)
	var canonical_shooter := _object_by_id(
		normalized.get("data", {}),
		"shooter_1"
	)
	var canonical_keys := canonical_shooter.keys()
	canonical_keys.sort()
	_expect(
		bool(normalized["ok"])
		and canonical_keys == ["id", "position", "type"],
		"Shooter schema is not the compact id/type/position contract."
	)

	for invalid_key: String in [
		"direction",
		"speed",
		"line_length",
		"aim_time",
		"aim_lock_time",
		"cooldown_time",
		"projectile_scene",
		"projectile_speed",
		"horizontal_impulse",
	]:
		var injected := _make_open_lane_level()
		_object_by_id(injected, "shooter_1")[invalid_key] = 1
		_expect_invalid(
			injected,
			"shooter enemy with internal '%s' tuning" % invalid_key
		)

	var clipped_actor := _make_open_lane_level()
	_object_by_id(clipped_actor, "shooter_1")["position"] = [48, 450]
	_expect_invalid(
		clipped_actor,
		"shooter collider clipping the immutable left wall"
	)

	var boundary_actor := _make_open_lane_level()
	_object_by_id(boundary_actor, "shooter_1")["position"] = [49, 450]
	_expect(
		bool(
			LEVEL_DATA_VALIDATOR.validate_and_normalize(
				boundary_actor
			)["ok"]
		),
		"Validator rejected a shooter exactly inside the left boundary."
	)

	var unsupported := _make_open_lane_level()
	_object_by_id(unsupported, "shooter_1")["position"] = [560, 200]
	var unsupported_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(unsupported)
	)
	_expect(
		bool(unsupported_result["ok"])
		and _contains_text(
			unsupported_result["warnings"],
			"no solid support"
		),
		"Unsupported shooter did not get the shared support warning."
	)

	var blockers: Array[Dictionary] = [
		{
			"id": "cover",
			"rect": Rect2(454, 416, 52, 80),
		},
	]
	var covered_preview := LevelEditorCanvas.shooter_aim_preview(
		Vector2(780, 450),
		Vector2(120, 450),
		blockers
	)
	var open_preview := LevelEditorCanvas.shooter_aim_preview(
		Vector2(780, 450),
		Vector2(120, 450),
		[]
	)
	var far_preview := LevelEditorCanvas.shooter_aim_preview(
		Vector2(900, 450),
		Vector2(-20, 450),
		[]
	)
	var grazing_preview := LevelEditorCanvas.shooter_aim_preview(
		Vector2(780, 450),
		Vector2(120, 446),
		[
			{
				"id": "grazing_cover",
				"rect": Rect2(454, 450, 52, 2),
			},
		]
	)
	var close_preview := LevelEditorCanvas.shooter_aim_preview(
		Vector2(500, 450),
		Vector2(510, 446),
		[]
	)
	_expect(
		bool(covered_preview["in_range"])
		and covered_preview["blocker_id"] == "cover"
		and absf(covered_preview["line_end"].x - 506.0) < 1.0,
		"Shooter preview did not clip the aim line at the cover face."
	)
	_expect(
		open_preview["blocker_id"] == ""
		and open_preview["line_end"].distance_to(
			Vector2(120, 450)
		) < 0.1,
		"Open shooter preview does not end at the player spawn."
	)
	_expect(
		not bool(far_preview["in_range"])
		and far_preview["line_end"].distance_to(
			far_preview["muzzle"]
		) <= 900.01,
		"Out-of-range preview did not expose the fixed 900 px limit."
	)
	_expect(
		grazing_preview["blocker_id"] == "grazing_cover"
		and absf(grazing_preview["line_end"].x - 506.0) < 1.0,
		"Shooter preview ignored a cover grazed by the projectile radius."
	)
	_expect(
		close_preview["line_end"].distance_to(
			Vector2(546, 446)
		) < 0.1,
		"Close-range shooter preview drifted from the runtime muzzle ray."
	)


func _test_builder_order_and_real_projectile() -> void:
	var arena := await _create_embedded_runtime(
		_make_open_lane_level()
	)
	_expect(
		is_instance_valid(arena) and arena.level_loaded,
		"Embedded shooter level did not load."
	)
	if not is_instance_valid(arena) or not arena.level_loaded:
		await _cleanup_current_scene()
		return

	var enemy := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	_expect(
		is_instance_valid(enemy)
		and is_instance_valid(player)
		and enemy.get_parent() == arena.get_node("Actors")
		and arena.enemies_remaining == 1,
		"Builder did not place and count the shooter as an enemy actor."
	)
	if not is_instance_valid(enemy) or not is_instance_valid(player):
		await _cleanup_current_scene()
		return

	var enemy_shape := (
		enemy.get_node("CollisionShape2D") as CollisionShape2D
	).shape as RectangleShape2D
	_expect(
		(enemy_shape.size * 0.5).is_equal_approx(
			Vector2(
				LEVEL_DATA_VALIDATOR.ACTOR_HALF_EXTENTS[
					"shooter_enemy"
				]
			)
		)
		and enemy.gun_pivot.position.is_equal_approx(
			LevelEditorCanvas.SHOOTER_GUN_PIVOT_OFFSET
		)
		and enemy.muzzle.position.is_equal_approx(
			Vector2(LevelEditorCanvas.SHOOTER_MUZZLE_LENGTH, 0)
		)
		and is_equal_approx(
			enemy.line_length,
			LevelEditorCanvas.SHOOTER_LINE_LENGTH
		),
		"Editor shooter geometry or range drifted from the runtime preset."
	)

	player.global_position = Vector2(300, 476)
	player.velocity = Vector2.ZERO

	var shots: Array[Dictionary] = []
	var impacts: Array[Dictionary] = []
	enemy.shot_fired.connect(
		func(projectile: ShooterProjectile) -> void:
			shots.append(
				{
					"direction": projectile.direction,
					"inside_arena": arena.is_ancestor_of(projectile),
					"radius": projectile.collision_radius,
				}
			)
			projectile.impacted.connect(
				func(collider: CollisionObject2D) -> void:
					impacts.append(
						{
							"id": str(
								collider.get_meta(
									"level_object_id",
									""
								)
							),
							"position": projectile.global_position,
							"velocity": player.velocity,
							"lock": player.knockback_time_remaining,
						}
					)
			)
	)

	for _frame in range(60):
		await physics_frame
		if (
			enemy.state == ShooterEnemy.State.AIMING
			and not enemy.aim_is_locked
		):
			break

	player.global_position = Vector2(300, 396)
	await physics_frame
	var saw_vertical_tracking := enemy.aim_direction.y < -0.1
	player.global_position = Vector2(300, 476)

	for _frame in range(180):
		await physics_frame
		if not impacts.is_empty():
			break

	var expected_velocity := Vector2.ZERO
	if not shots.is_empty():
		expected_velocity = (
			shots[0]["direction"] * 520.0
			+ Vector2(0, -140)
		)
	var impact_velocity: Vector2 = (
		impacts[0].get("velocity", Vector2.ZERO)
		if not impacts.is_empty()
		else Vector2.ZERO
	)
	var impact_lock := (
		float(impacts[0].get("lock", 0.0))
		if not impacts.is_empty()
		else 0.0
	)
	_expect(
		enemy.player == player
		and saw_vertical_tracking
		and shots.size() == 1
		and bool(shots[0]["inside_arena"])
		and is_equal_approx(
			float(shots[0]["radius"]),
			LevelEditorCanvas.SHOOTER_PROJECTILE_RADIUS
		)
		and impacts.size() == 1
		and impacts[0]["id"] == "player_start"
		and impact_velocity.distance_to(expected_velocity) < 0.5
		and impact_lock > 0.0,
		(
			"A shooter declared before the player did not reacquire, "
			+ "track, fire an arena-owned projectile, and apply impulse: "
			+ "player=%s vertical=%s shots=%s impacts=%s velocity=%s "
			+ "expected=%s lock=%s"
		)
		% [
			enemy.player == player,
			saw_vertical_tracking,
			str(shots),
			str(impacts),
			impact_velocity,
			expected_velocity,
			impact_lock,
		]
	)
	await _cleanup_current_scene()


func _test_cover_blocks_first_shot() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_05_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 05 cover fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 05 cover fixture did not load.")
		await _cleanup_current_scene()
		return

	var enemy := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	var cover := arena.get_level_object("cover") as StaticBody2D
	var impacts: Array[Dictionary] = []
	enemy.shot_fired.connect(
		func(projectile: ShooterProjectile) -> void:
			projectile.impacted.connect(
				func(collider: CollisionObject2D) -> void:
					impacts.append(
						{
							"id": str(
								collider.get_meta(
									"level_object_id",
									""
								)
							),
							"x": projectile.global_position.x,
						}
					)
			)
	)

	var saw_cover_ray := false
	var target_x := 0.0
	for _frame in range(150):
		await physics_frame
		if enemy.state == ShooterEnemy.State.AIMING:
			enemy.aim_ray.force_raycast_update()
			saw_cover_ray = (
				saw_cover_ray
				or enemy.aim_ray.get_collider() == cover
			)
			target_x = enemy.target_mark.global_position.x
		if not impacts.is_empty():
			break

	_expect(
		saw_cover_ray
		and absf(target_x - 506.0) < 2.0
		and impacts.size() == 1
		and impacts[0]["id"] == "cover"
		and absf(float(impacts[0]["x"]) - 506.0) < 2.0
		and player.knockback_time_remaining <= 0.0
		and absf(player.global_position.x - 120.0) < 2.0,
		"Cover did not block both the telegraph and the first real shot."
	)
	await _cleanup_current_scene()


func _test_arena_05_real_clear() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_05_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 05 clear fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 05 embedded playtest did not load.")
		await _cleanup_current_scene()
		return
	arena.clear_restart_delay = 10.0

	var enemy := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	enemy.line_length = 0.0
	for _frame in range(30):
		await physics_frame

	enemy.global_position = Vector2(800, 477)
	enemy.velocity = Vector2.ZERO
	enemy.call("_enter_ready")
	player.global_position = Vector2(744, 476)
	player.velocity = Vector2.ZERO
	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	await physics_frame
	await _press_physical_key(KEY_X)

	for _frame in range(180):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame

	_expect(
		arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR,
		"A real player attack did not knock the Arena 05 shooter into its pit."
	)
	await _cleanup_current_scene()


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		editor.load_entries.size() >= 3
		and editor.load_entries[2]["id"] == "arena_05_data",
		"Editor does not list Arena 05 after the earlier examples."
	)
	editor.call("_perform_load_selected_level", 2)
	await process_frame
	var builtin_shooter := (
		editor.draft.find_first_object_of_type("shooter_enemy")
	)
	_expect(
		editor.source_label == "ПРИМЕР"
		and editor.loaded_user_level_id.is_empty()
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and builtin_shooter.get("id", "") == "shooter_1",
		"Editor did not open Arena 05 as a clean built-in draft."
	)

	editor.call("_select_object", "shooter_1")
	await process_frame
	_expect(
		is_instance_valid(_find_property_editor(editor, "X"))
		and is_instance_valid(_find_property_editor(editor, "Y"))
		and not is_instance_valid(
			_find_property_editor(editor, "DIRECTION")
		)
		and not is_instance_valid(_find_property_editor(editor, "SPEED"))
		and "900 PX" in editor.inspector_hint.text,
		"Shooter inspector exposed tuning or omitted line-range guidance."
	)

	editor.canvas.grab_focus()
	await process_frame
	await _press_physical_key(KEY_7)
	await process_frame
	var scroll_rect := editor.tool_scroll.get_global_rect()
	var button_rect := editor.shooter_button.get_global_rect()
	_expect(
		editor.active_tool == "shooter_enemy"
		and editor.shooter_button.button_pressed
		and scroll_rect.encloses(button_rect),
		"Physical 7 did not select and reveal the shooter tool."
	)

	editor.canvas.call(
		"_begin_primary_action",
		Vector2(700, 420) * 0.6
	)
	await process_frame
	var placed_id: String = editor.selected_id
	var placed := editor.draft.find_object(placed_id)
	var hit := editor.canvas.call(
		"_hit_test",
		Vector2(700, 420)
	) as Dictionary
	_expect(
		placed.get("type", "") == "shooter_enemy"
		and placed.get("position", []) == [700, 420]
		and placed.keys().size() == 3
		and hit.get("id", "") == placed_id,
		"Shooter palette placement or hit-test broke its compact schema."
	)

	editor.call("_nudge_selected", Vector2i.LEFT, false)
	_expect(
		editor.draft.find_object(placed_id)["position"] == [680, 420],
		"Shooter nudge did not use the editor grid."
	)
	editor.call("_duplicate_selected")
	var duplicate_id: String = editor.selected_id
	var duplicate := editor.draft.find_object(duplicate_id)
	_expect(
		duplicate_id != placed_id
		and duplicate.get("position", []) == [700, 440]
		and duplicate.keys().size() == 3,
		"Shooter duplicate leaked runtime tuning or used the wrong offset."
	)
	editor.call("_undo")
	editor.call("_undo")
	editor.call("_undo")
	_expect(
		editor.draft.find_object(placed_id).is_empty()
		and editor.draft.find_object(duplicate_id).is_empty()
		and not editor.draft.is_dirty(),
		"Shooter actions did not undo to the Arena 05 snapshot."
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var runtime := editor.playtest_runtime as LevelRuntimeArena
	var runtime_shooter := (
		runtime.get_level_object("shooter_1") as ShooterEnemy
		if is_instance_valid(runtime)
		else null
	)
	var projectile_refs: Array[WeakRef] = []
	var projectile_inside_runtime: Array[bool] = []
	if is_instance_valid(runtime_shooter):
		_capture_projectile_shot(
			runtime_shooter,
			runtime,
			projectile_refs,
			projectile_inside_runtime
		)

	for _frame in range(120):
		await physics_frame
		if not projectile_refs.is_empty():
			break

	_expect(
		is_instance_valid(runtime)
		and runtime.level_loaded
		and is_instance_valid(runtime_shooter)
		and projectile_refs.size() == 1
		and bool(projectile_inside_runtime[0]),
		"Editor playtest did not produce an Arena-owned shooter projectile."
	)

	var old_runtime_ref: WeakRef = weakref(runtime)
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
	var restarted_shooter := (
		restarted_runtime.get_level_object(
			"shooter_1"
		) as ShooterEnemy
		if is_instance_valid(restarted_runtime)
		else null
	)
	_expect(
		old_runtime_ref.get_ref() == null
		and projectile_refs[0].get_ref() == null
		and is_instance_valid(restarted_runtime)
		and restarted_runtime.level_loaded
		and is_instance_valid(restarted_shooter),
		"Restart did not replace the runtime and its in-flight projectile."
	)
	if is_instance_valid(restarted_shooter):
		_capture_projectile_shot(
			restarted_shooter,
			restarted_runtime,
			projectile_refs,
			projectile_inside_runtime
		)
	for _frame in range(120):
		await physics_frame
		if projectile_refs.size() >= 2:
			break
	_expect(
		projectile_refs.size() >= 2
		and bool(projectile_inside_runtime[1]),
		"Restarted playtest did not produce an Arena-owned projectile."
	)

	editor.call("_stop_playtest")
	await process_frame
	await process_frame
	var projectile_survived := (
		projectile_refs.size() >= 2
		and projectile_refs[1].get_ref() != null
	)
	_expect(
		not projectile_survived
		and _count_projectiles(editor) == 0,
		"Shooter projectile survived stopping the embedded playtest."
	)
	await _cleanup_current_scene()


func _capture_projectile_shot(
	shooter: ShooterEnemy,
	runtime: LevelRuntimeArena,
	projectile_refs: Array[WeakRef],
	projectile_inside_runtime: Array[bool]
) -> void:
	shooter.shot_fired.connect(
		func(projectile: ShooterProjectile) -> void:
			projectile_refs.append(weakref(projectile))
			projectile_inside_runtime.append(
				runtime.is_ancestor_of(projectile)
			)
	)


func _make_open_lane_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "shooter_smoke",
		"title": "SHOOTER SMOKE",
		"objective": "TEST",
		"clear_message": "CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "floor",
				"type": "solid_rect",
				"rect": [32, 496, 896, 44],
			},
			{
				"id": "shooter_1",
				"type": "shooter_enemy",
				"position": [700, 450],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [300, 450],
			},
		],
	}


func _create_embedded_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded["ok"]),
		"Could not encode embedded shooter fixture: %s"
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


func _count_projectiles(node: Node) -> int:
	var count := 1 if node is ShooterProjectile else 0
	for child: Node in node.get_children():
		count += _count_projectiles(child)
	return count


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


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

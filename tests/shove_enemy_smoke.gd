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
	_test_builtin_and_schema()
	await _test_builder_order_and_real_shove()
	await _test_arena_03_real_clear()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("SHOVE_ENEMY_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_builtin_and_schema() -> void:
	var builtins := LEVEL_STORAGE.list_builtin_levels()
	var builtin_ids: Array[String] = []
	for entry: Dictionary in builtins:
		builtin_ids.append(str(entry.get("id", "")))
	_expect(
		builtin_ids.has("arena_01_data")
		and builtin_ids.has("arena_03_data"),
		"Built-in level catalog does not expose Arena 01 and Arena 03."
	)

	var arena_01: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_01_data")
	)
	var arena_03: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_03_data")
	)
	_expect(
		bool(arena_01["ok"])
		and bool(arena_03["ok"])
		and arena_03["data"]["level_id"] == "arena_03_data",
		"One of the built-in data levels did not load."
	)
	_expect(
		not bool(
			LEVEL_STORAGE.load_builtin_level("missing_builtin")["ok"]
		),
		"Storage accepted an unknown built-in level ID."
	)
	var reserved_id: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("arena_03_data")
	)
	_expect(
		bool(reserved_id["ok"])
		and reserved_id["data"] != "arena_03_data",
		"Generated user ID collided with the Arena 03 built-in."
	)
	if not bool(arena_03["ok"]):
		return

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(
		arena_03["data"]
	)
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
		"Arena 03 JSON is not deterministic across a round trip."
	)

	var canonical_fixture := _make_continuous_floor_level()
	_object_by_id(canonical_fixture, "shove_1").erase("direction")
	var normalized: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			canonical_fixture
		)
	)
	_expect(
		bool(normalized["ok"])
		and _object_by_id(
			normalized["data"],
			"shove_1"
		).get("direction", 0) == -1,
		"A shove-only enemy level was rejected or missed direction=-1."
	)
	if bool(normalized["ok"]):
		var canonical_shove := _object_by_id(
			normalized["data"],
			"shove_1"
		)
		_expect(
			not canonical_shove.has("speed")
			and not canonical_shove.has("telegraph_time"),
			"Canonical shove data leaked internal combat tuning."
		)

	for invalid_key: String in [
		"speed",
		"telegraph_time",
		"lunge_speed",
		"shove_horizontal_impulse",
	]:
		var injected := _make_continuous_floor_level()
		_object_by_id(injected, "shove_1")[invalid_key] = 1
		_expect_invalid(
			injected,
			"shove enemy with internal '%s' tuning" % invalid_key
		)

	var wrong_direction := _make_continuous_floor_level()
	_object_by_id(wrong_direction, "shove_1")["direction"] = 0
	_expect_invalid(wrong_direction, "shove enemy with direction 0")

	var clipped_actor := _make_continuous_floor_level()
	_object_by_id(clipped_actor, "shove_1")["position"] = [47, 450]
	_expect_invalid(
		clipped_actor,
		"shove collider clipping the immutable left wall"
	)

	var short_runway := _make_continuous_floor_level()
	_object_by_id(short_runway, "shove_1")["position"] = [70, 450]
	_object_by_id(short_runway, "shove_1")["direction"] = -1
	var short_runway_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(short_runway)
	)
	_expect(
		bool(short_runway_result["ok"])
		and _contains_text(
			short_runway_result["warnings"],
			"less than 48 px"
		),
		"Validator did not warn about a shove spawn with little runway."
	)

	var unsupported := _make_continuous_floor_level()
	_object_by_id(unsupported, "shove_1")["position"] = [560, 200]
	var unsupported_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(unsupported)
	)
	_expect(
		bool(unsupported_result["ok"])
		and _contains_text(
			unsupported_result["warnings"],
			"no solid support"
		)
		and not _contains_text(
			unsupported_result["warnings"],
			"less than 48 px"
		),
		"Unsupported shove did not get the focused support warning."
	)

	_expect(
		LevelEditorCanvas.shove_detection_rect(
			Vector2(500, 300)
		).is_equal_approx(Rect2(320, 252, 360, 96)),
		"Editor shove detection preview drifted from ±180 × ±48."
	)


func _test_builder_order_and_real_shove() -> void:
	var arena := await _create_embedded_runtime(
		_make_continuous_floor_level()
	)
	_expect(
		is_instance_valid(arena) and arena.level_loaded,
		"Embedded shove level did not load."
	)
	if not is_instance_valid(arena) or not arena.level_loaded:
		await _cleanup_current_scene()
		return

	var enemy := arena.get_level_object("shove_1") as ShoveEnemy
	var player := arena.get_level_object("player_start") as Player
	_expect(
		is_instance_valid(enemy)
		and is_instance_valid(player)
		and enemy.get_parent() == arena.get_node("Actors")
		and absf(enemy.position.x - 560.0) < 12.0
		and enemy.patrol_direction == -1.0
		and is_equal_approx(enemy.patrol_speed, 55.0)
		and arena.enemies_remaining == 1,
		(
			"Builder did not preserve the fixed shove preset and placement: "
			+ "enemy=%s player=%s parent=%s position=%s direction=%s "
			+ "speed=%s count=%s"
		)
		% [
			is_instance_valid(enemy),
			is_instance_valid(player),
			enemy.get_parent() if is_instance_valid(enemy) else null,
			enemy.position if is_instance_valid(enemy) else Vector2.ZERO,
			enemy.patrol_direction if is_instance_valid(enemy) else 0.0,
			enemy.patrol_speed if is_instance_valid(enemy) else 0.0,
			arena.enemies_remaining,
		]
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
				LEVEL_DATA_VALIDATOR.ACTOR_HALF_EXTENTS["shove_enemy"]
			)
		),
		"Validator shove bounds drifted from the runtime collider."
	)

	var saw_telegraph := false
	var saw_lunge := false
	var player_was_shoved := false
	for _frame in range(180):
		await physics_frame
		saw_telegraph = (
			saw_telegraph
			or enemy.state == ShoveEnemy.State.TELEGRAPH
		)
		saw_lunge = saw_lunge or enemy.state == ShoveEnemy.State.LUNGE
		player_was_shoved = (
			player_was_shoved
			or player.knockback_time_remaining > 0.0
			or player.velocity.x < -100.0
		)
		if saw_lunge and player_was_shoved:
			break

	_expect(
		enemy.player == player
		and saw_telegraph
		and saw_lunge
		and player_was_shoved,
		(
			"A shove declared before the player did not reacquire, "
			+ "telegraph, lunge, and apply a real impulse."
		)
	)
	await _cleanup_current_scene()


func _test_arena_03_real_clear() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_03_data")
	)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare the Arena 03 clear fixture.")
		return

	var arena := await _create_embedded_runtime(loaded["data"])
	if not is_instance_valid(arena) or not arena.level_loaded:
		failures.append("Arena 03 embedded playtest did not load.")
		await _cleanup_current_scene()
		return
	arena.clear_restart_delay = 10.0

	var enemy := arena.get_level_object("shove_1") as ShoveEnemy
	var player := arena.get_level_object("player_start") as Player
	enemy.detection_range = 0.0
	enemy.patrol_speed = 0.0
	for _frame in range(30):
		await physics_frame

	enemy.global_position = Vector2(590, 477)
	enemy.velocity = Vector2.ZERO
	enemy.call("_enter_patrol")
	player.global_position = Vector2(650, 476)
	player.velocity = Vector2.ZERO
	player.facing_direction = -1.0
	player.visual.scale.x = -1.0
	player.attack_pivot.scale.x = -1.0
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
		"A real player attack did not clear the Arena 03-like pit setup."
	)
	await _cleanup_current_scene()


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	var arena_03_index := _load_entry_index(editor, "arena_03_data")
	_expect(
		arena_03_index >= 0,
		"Editor does not list the Arena 03 built-in."
	)
	if arena_03_index < 0:
		await _cleanup_current_scene()
		return
	editor.call("_perform_load_selected_level", arena_03_index)
	await process_frame
	var builtin_shove := (
		editor.draft.find_first_object_of_type("shove_enemy")
	)
	_expect(
		editor.source_label == "ПРИМЕР"
		and editor.loaded_user_level_id.is_empty()
		and not editor.draft.is_dirty()
		and bool(editor.validation_result.get("ok", false))
		and builtin_shove.get("id", "") == "shove_1",
		"Editor did not open the Arena 03-like built-in as a clean draft."
	)

	editor.call("_select_object", "shove_1")
	await process_frame
	var direction_options := (
		_find_property_editor(editor, "DIRECTION") as OptionButton
	)
	_expect(
		is_instance_valid(direction_options)
		and not is_instance_valid(_find_property_editor(editor, "SPEED"))
		and "±180" in editor.inspector_hint.text,
		"Shove inspector exposed tuning or omitted direction/range guidance."
	)
	if is_instance_valid(direction_options):
		direction_options.select(1)
		direction_options.item_selected.emit(1)
		await process_frame
		_expect(
			editor.draft.find_object("shove_1")["direction"] == 1
			and bool(editor.validation_result.get("ok", false)),
			"Shove inspector did not apply a valid patrol direction."
		)
		editor.call("_undo")
		await process_frame

	editor.canvas.grab_focus()
	await process_frame
	await _press_physical_key(KEY_6)
	_expect(
		editor.active_tool == "shove_enemy"
		and editor.shove_button.button_pressed,
		"Physical 6 did not select the shove tool."
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
		placed.get("type", "") == "shove_enemy"
		and placed.get("position", []) == [700, 420]
		and placed.get("direction", 0) == -1
		and not placed.has("speed")
		and hit.get("id", "") == placed_id,
		"Shove palette placement or hit-test produced the wrong object."
	)

	editor.call("_nudge_selected", Vector2i.LEFT, false)
	_expect(
		editor.draft.find_object(placed_id)["position"] == [680, 420],
		"Shove nudge did not use the editor grid."
	)
	editor.call("_duplicate_selected")
	var duplicate_id: String = editor.selected_id
	_expect(
		duplicate_id != placed_id
		and editor.draft.find_object(duplicate_id).get(
			"position",
			[]
		) == [700, 440]
		and not editor.draft.find_object(duplicate_id).has("speed"),
		"Shove duplicate did not preserve the compact schema."
	)
	editor.call("_undo")
	editor.call("_undo")
	editor.call("_undo")
	_expect(
		editor.draft.find_object(placed_id).is_empty()
		and editor.draft.find_object(duplicate_id).is_empty()
		and not editor.draft.is_dirty(),
		"Shove editor actions did not undo back to the built-in snapshot."
	)

	editor.call("_start_playtest")
	await process_frame
	await process_frame
	var runtime := editor.playtest_runtime
	var runtime_shove := (
		runtime.get_level_object("shove_1") as ShoveEnemy
		if is_instance_valid(runtime)
		else null
	)
	_expect(
		is_instance_valid(runtime)
		and runtime.level_loaded
		and is_instance_valid(runtime_shove)
		and runtime_shove.patrol_direction == -1.0,
		"Editor playtest did not preserve the shove type and direction."
	)
	editor.call("_stop_playtest")
	await process_frame

	var tool_scroll := editor.get_node(
		"EditorView/PalettePanel/ToolScroll"
	) as ScrollContainer
	_expect(
		is_instance_valid(tool_scroll)
		and editor.shove_button.visible
		and editor.duplicate_button.get_global_rect().end.y <= 540.0
		and editor.delete_button.get_global_rect().end.y <= 540.0,
		"Scrollable palette hid the shove tool or fixed edit actions."
	)
	await _cleanup_current_scene()


func _make_continuous_floor_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "shove_smoke",
		"title": "SHOVE SMOKE",
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
				"id": "shove_1",
				"type": "shove_enemy",
				"position": [560, 450],
				"direction": -1,
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [420, 450],
			},
		],
	}


func _create_embedded_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded["ok"]),
		"Could not encode embedded shove fixture: %s"
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

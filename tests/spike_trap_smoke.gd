extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const LEVEL_BEHAVIOR_PRESETS := preload(
	"res://scripts/levels/level_behavior_presets.gd"
)
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

const SPIKE_RECT := Rect2(400.0, 476.0, 120.0, 20.0)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_schema_and_round_trip()
	await _test_builder_and_player_hazard()
	await _cleanup_current_scene()
	await _test_all_enemy_types_and_clear()
	await _cleanup_current_scene()
	await _test_editor_vertical_slice()
	await _cleanup_current_scene()

	if failures.is_empty():
		print("SPIKE_TRAP_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_schema_and_round_trip() -> void:
	var source := _make_level()
	var validation: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(source)
	)
	_expect(
		bool(validation.get("ok", false))
		and validation.get("warnings", []).is_empty(),
		"Validator rejected a valid spike_trap fixture: %s / %s"
		% [validation.get("errors", []), validation.get("warnings", [])]
	)
	if not bool(validation.get("ok", false)):
		return

	var canonical_spike := _object_by_id(
		validation["data"],
		"spikes"
	)
	var canonical_keys: Array = canonical_spike.keys()
	canonical_keys.sort()
	_expect(
		canonical_spike.get("type") == "spike_trap"
		and canonical_spike.get("rect") == [400, 476, 120, 20]
		and canonical_keys == ["id", "rect", "type"],
		"spike_trap did not preserve its closed canonical contract: %s"
		% [canonical_spike]
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(
		validation["data"]
	)
	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		str(encoded_once.get("text", ""))
	)
	var encoded_twice: Dictionary = LEVEL_DATA_CODEC.encode(
		decoded.get("data", {})
	)
	_expect(
		bool(encoded_once.get("ok", false))
		and bool(decoded.get("ok", false))
		and bool(encoded_twice.get("ok", false))
		and encoded_once.get("text") == encoded_twice.get("text"),
		"spike_trap JSON did not survive a deterministic round trip."
	)

	var wrong_height := _make_level()
	_object_by_id(wrong_height, "spikes")["rect"] = [400, 456, 120, 40]
	_expect_invalid_with(
		wrong_height,
		"height must be exactly 20",
		"spike_trap with a noncanonical height"
	)

	var wrong_width := _make_level()
	_object_by_id(wrong_width, "spikes")["rect"] = [400, 476, 19, 20]
	_expect_invalid_with(
		wrong_width,
		"width must be at least 20",
		"spike_trap narrower than one tooth"
	)

	var outside_playfield := _make_level()
	_object_by_id(outside_playfield, "spikes")["rect"] = [20, 476, 120, 20]
	_expect_invalid_with(
		outside_playfield,
		"runtime playfield",
		"spike_trap outside the runtime playfield"
	)

	var unknown_property := _make_level()
	_object_by_id(unknown_property, "spikes")["damage"] = 1
	_expect_invalid_with(
		unknown_property,
		"unknown key 'damage'",
		"spike_trap with an open-ended damage property"
	)

	var spawn_overlap := _make_level()
	_object_by_id(spawn_overlap, "player_start")["position"] = [460, 476]
	_expect_invalid_with(
		spawn_overlap,
		"collision bounds overlap spike trap 'spikes'",
		"player spawn overlapping a spike_trap"
	)

	var solid_overlap := _make_level()
	_object_by_id(solid_overlap, "floor")["rect"] = [32, 480, 896, 60]
	_expect_invalid_with(
		solid_overlap,
		"overlaps solid_rect 'floor'",
		"solid overlapping a spike_trap"
	)

	var spike_overlap := _make_level()
	spike_overlap["objects"].append(
		{
			"id": "spikes_2",
			"type": "spike_trap",
			"rect": [500, 476, 120, 20],
		}
	)
	_expect_invalid_with(
		spike_overlap,
		"overlaps spike_trap 'spikes_2'",
		"two overlapping spike_traps"
	)


func _test_builder_and_player_hazard() -> void:
	var arena := await _create_runtime()
	if not is_instance_valid(arena):
		return

	var spikes := arena.get_level_object("spikes") as SpikeTrap
	var player := arena.get_level_object("player_start") as Player
	var geometry_parent := arena.get_node_or_null(
		"Geometry/LevelObjects"
	)
	var collision: CollisionShape2D = null
	var shape: RectangleShape2D = null
	if is_instance_valid(spikes):
		collision = spikes.get_node_or_null(
			"CollisionShape2D"
		) as CollisionShape2D
	if is_instance_valid(collision):
		shape = collision.shape as RectangleShape2D
	_expect(
		is_instance_valid(spikes)
		and spikes.get_parent() == geometry_parent
		and spikes.position.is_equal_approx(SPIKE_RECT.get_center())
		and spikes.trap_size.is_equal_approx(SPIKE_RECT.size)
		and is_instance_valid(shape)
		and shape.size.is_equal_approx(SPIKE_RECT.size)
		and spikes.collision_layer == 0
		and spikes.collision_mask == 6
		and spikes.monitoring
		and not spikes.monitorable
		and not spikes.body_entered.get_connections().is_empty(),
		"Builder did not preserve spike parent, rect, mask, or resolver link."
	)
	if not is_instance_valid(spikes) or not is_instance_valid(player):
		return

	var hazard_feedback := arena.hazard_feedback as ArenaHazardFeedback
	var impact_feedback := arena.impact_feedback as ArenaImpactFeedback
	var initial_generation := arena.outcome_generation
	player.global_position = Vector2(460.0, 440.0)
	player.velocity = Vector2.ZERO
	for _frame in range(90):
		await physics_frame
		if player.is_defeated:
			break
	_expect(
		player.is_defeated
		and player.defeat_cause == Player.DefeatCause.HAZARD
		and player.is_combat_defeat_active
		and not player.is_falling_out
		and arena.status_label.text == "ШИПЫ  /  ПЕРЕЗАПУСК..."
		and arena.pending_outcome == Arena.Outcome.FALL
		and arena.outcome_generation == initial_generation + 1
		and impact_feedback.defeat_count == 1
		and impact_feedback.last_defeat_direction.is_equal_approx(
			Vector2.UP
		)
		and hazard_feedback.fall_count == 0,
		(
			"Spike contact did not use the HAZARD combat-feedback path: "
			+ "cause=%s combat=%s falling=%s status=%s outcome=%s "
			+ "defeats=%s pit_falls=%s direction=%s."
		)
		% [
			player.defeat_cause,
			player.is_combat_defeat_active,
			player.is_falling_out,
			arena.status_label.text,
			arena.pending_outcome,
			impact_feedback.defeat_count,
			hazard_feedback.fall_count,
			impact_feedback.last_defeat_direction,
		]
	)

	spikes.body_entered.emit(player)
	spikes.body_entered.emit(player)
	await process_frame
	_expect(
		arena.outcome_generation == initial_generation + 1
		and impact_feedback.defeat_count == 1
		and hazard_feedback.fall_count == 0,
		"Repeated spike callbacks duplicated player outcome or feedback."
	)


func _test_all_enemy_types_and_clear() -> void:
	var arena := await _create_runtime()
	if not is_instance_valid(arena):
		return

	var spikes := arena.get_level_object("spikes") as SpikeTrap
	var patrol := arena.get_level_object("patrol_1") as PatrolEnemy
	var shove := arena.get_level_object("shove_1") as ShoveEnemy
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	var hazard_feedback := arena.hazard_feedback as ArenaHazardFeedback
	var impact_feedback := arena.impact_feedback as ArenaImpactFeedback
	_expect(
		is_instance_valid(spikes)
		and is_instance_valid(patrol)
		and is_instance_valid(shove)
		and is_instance_valid(shooter)
		and is_instance_valid(player)
		and arena.enemies_remaining == 3,
		"Enemy spike fixture did not build patrol, shove, and shooter."
	)
	if (
		not is_instance_valid(patrol)
		or not is_instance_valid(shove)
		or not is_instance_valid(shooter)
	):
		return

	var patrol_ref: WeakRef = weakref(patrol)
	await _drop_body_on_spikes(patrol)
	_expect(
		not is_instance_valid(patrol_ref.get_ref())
		and arena.enemies_remaining == 2
		and arena.pending_outcome == Arena.Outcome.NONE
		and hazard_feedback.elimination_count == 1
		and hazard_feedback.clear_count == 0
		and impact_feedback.elimination_count == 1
		and impact_feedback.clear_count == 0,
		"Spike trap did not eliminate patrol as a non-final enemy."
	)

	var shove_ref: WeakRef = weakref(shove)
	await _drop_body_on_spikes(shove)
	_expect(
		not is_instance_valid(shove_ref.get_ref())
		and arena.enemies_remaining == 1
		and arena.pending_outcome == Arena.Outcome.NONE
		and hazard_feedback.elimination_count == 2
		and impact_feedback.elimination_count == 2,
		"Spike trap did not eliminate shove as a non-final enemy."
	)

	var shooter_ref: WeakRef = weakref(shooter)
	await _drop_body_on_spikes(shooter)
	_expect(
		not is_instance_valid(shooter_ref.get_ref())
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and arena.restart_scheduled
		and arena.status_label.text == "CLEAR"
		and hazard_feedback.elimination_count == 3
		and hazard_feedback.clear_count == 1
		and impact_feedback.elimination_count == 3
		and impact_feedback.clear_count == 1
		and impact_feedback.last_elimination_direction.is_equal_approx(
			Vector2.UP
		)
		and impact_feedback.last_elimination_was_clear
		and not player.is_defeated,
		"Last shooter spike elimination did not produce one CLEAR outcome."
	)


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		is_instance_valid(editor.spike_button)
		and editor.spike_button.text.begins_with("K")
		and "ШИПЫ" in editor.spike_button.text,
		"Editor did not expose the K spike palette button."
	)
	editor.call("_set_tool", "select")
	editor.spike_button.emit_signal("pressed")
	_expect(
		editor.active_tool == "spike_trap"
		and editor.spike_button.button_pressed,
		"Spike palette button did not select spike_trap."
	)
	editor.call("_set_tool", "select")
	await _press_physical_key(KEY_K)
	_expect(
		editor.active_tool == "spike_trap"
		and editor.spike_button.button_pressed,
		"Physical K did not select spike_trap."
	)

	_expect(
		editor.canvas.call(
			"_default_rect",
			Vector2(420, 300),
			"spike_trap"
		) == [420, 300, 120, 20],
		"Spike click default is not the canonical 120 x 20 rect."
	)
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(420, 300) * 0.6
	)
	editor.canvas.call(
		"_update_drag",
		Vector2(540, 300) * 0.6
	)
	editor.canvas.call(
		"_finish_primary_action",
		Vector2(540, 300) * 0.6
	)
	await process_frame
	var spike_id: String = editor.selected_id
	var placed := editor.draft.find_object(spike_id)
	_expect(
		placed.get("type") == "spike_trap"
		and placed.get("rect") == [420, 300, 120, 20]
		and bool(editor.validation_result.get("ok", false)),
		"Canvas drag did not place a valid canonical spike_trap."
	)

	editor.call("_set_tool", "select")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(480, 310) * 0.6
	)
	editor.canvas.call(
		"_update_drag",
		Vector2(500, 310) * 0.6
	)
	editor.canvas.call(
		"_finish_primary_action",
		Vector2(500, 310) * 0.6
	)
	await process_frame
	var moved := editor.draft.find_object(spike_id)
	_expect(
		moved.get("rect") == [440, 300, 120, 20],
		"Canvas select drag did not move spike_trap by one grid step."
	)

	editor.call("_duplicate_selected")
	await process_frame
	var duplicate_id: String = editor.selected_id
	var duplicate := editor.draft.find_object(duplicate_id)
	_expect(
		not duplicate_id.is_empty()
		and duplicate_id != spike_id
		and duplicate.get("type") == "spike_trap"
		and duplicate.get("rect") == [460, 320, 120, 20]
		and bool(editor.validation_result.get("ok", false)),
		"Duplicate did not preserve and safely offset spike_trap."
	)

	var x_field := _find_property_editor(editor, "X") as LineEdit
	var y_field := _find_property_editor(editor, "Y") as LineEdit
	var width_field := _find_property_editor(editor, "WIDTH") as LineEdit
	var height_label := _find_property_editor(editor, "HEIGHT") as Label
	_expect(
		is_instance_valid(x_field)
		and x_field.text == "460"
		and is_instance_valid(y_field)
		and y_field.text == "320"
		and is_instance_valid(width_field)
		and width_field.text == "120"
		and is_instance_valid(height_label)
		and height_label.text == "20"
		and "СМЕРТЕЛЬНАЯ ЛОВУШКА" in editor.inspector_hint.text,
		"Spike inspector did not expose rect fields and hazard hint."
	)

	editor.call("_start_playtest")
	await process_frame
	await physics_frame
	var playtest := editor.playtest_runtime as LevelRuntimeArena
	var playtest_spike := (
		playtest.get_level_object(duplicate_id) as SpikeTrap
		if is_instance_valid(playtest)
		else null
	)
	var playtest_player := (
		playtest.get_level_object("player_start") as Player
		if is_instance_valid(playtest)
		else null
	)
	_expect(
		is_instance_valid(playtest)
		and playtest.level_loaded
		and is_instance_valid(playtest_spike)
		and is_instance_valid(playtest_player)
		and playtest_spike.trap_size.is_equal_approx(
			Vector2(120.0, 20.0)
		),
		"Editor playtest did not build the duplicated spike_trap."
	)
	if is_instance_valid(playtest_spike) and is_instance_valid(playtest_player):
		playtest_spike.body_entered.emit(playtest_player)
		_expect(
			playtest_player.is_defeated
			and playtest_player.defeat_cause
			== Player.DefeatCause.HAZARD
			and playtest.status_label.text
			== "ШИПЫ  /  ПЕРЕЗАПУСК...",
			"Editor playtest spike did not retain HAZARD behavior."
		)
	if is_instance_valid(playtest):
		editor.call("_stop_playtest")
		await process_frame


func _create_runtime() -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(_make_level())
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode spike_trap runtime fixture: %s"
		% [encoded.get("errors", [])]
	)
	if not bool(encoded.get("ok", false)):
		return null

	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded.get("text", "")))
	runtime.fall_restart_delay = 10.0
	runtime.clear_restart_delay = 10.0
	root.add_child(runtime)
	current_scene = runtime
	await process_frame
	await physics_frame
	_expect(
		runtime.level_loaded and runtime.load_errors.is_empty(),
		"Spike trap runtime fixture did not load: %s"
		% [runtime.load_errors]
	)
	if not runtime.level_loaded:
		return null
	return runtime


func _drop_body_on_spikes(body: CharacterBody2D) -> void:
	body.global_position = Vector2(460.0, 440.0)
	body.velocity = Vector2.ZERO
	var body_ref: WeakRef = weakref(body)
	for _frame in range(90):
		await physics_frame
		if not is_instance_valid(body_ref.get_ref()):
			break
	await process_frame


func _make_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "spike_trap_smoke",
		"title": "SPIKE TRAP SMOKE",
		"objective": "TEST HAZARDS",
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
				"one_way": false,
			},
			{
				"id": "shot_blocker",
				"type": "solid_rect",
				"rect": [560, 400, 20, 96],
				"one_way": false,
			},
			{
				"id": "spikes",
				"type": "spike_trap",
				"rect": [400, 476, 120, 20],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [120, 450],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [650, 450],
				"direction": 1,
				"speed": 20,
			},
			{
				"id": "shove_1",
				"type": "shove_enemy",
				"position": [760, 450],
				"direction": 1,
				"behavior_preset": (
					LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
				),
			},
			{
				"id": "shooter_1",
				"type": "shooter_enemy",
				"position": [880, 450],
				"behavior_preset": (
					LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
				),
			},
		],
	}


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _expect_invalid_with(
	data: Dictionary,
	needle: String,
	label: String
) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(
		not bool(result.get("ok", false))
		and _contains_text(result.get("errors", []), needle),
		"Validator accepted %s or missed '%s': %s"
		% [label, needle, result.get("errors", [])]
	)


func _contains_text(values: Array, needle: String) -> bool:
	for value: Variant in values:
		if needle in str(value):
			return true
	return false


func _press_physical_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame

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


func _cleanup_current_scene() -> void:
	var scene := current_scene
	current_scene = null
	if not is_instance_valid(scene):
		return
	scene.queue_free()
	await scene.tree_exited


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

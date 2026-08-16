extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_schema_and_round_trip()
	await _test_builder_collection_and_jump_contract()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("DOUBLE_JUMP_PICKUP_SMOKE_OK")
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
		bool(validation.get("ok", false)),
		"Validator rejected a valid double_jump_pickup: %s"
		% [validation.get("errors", [])]
	)
	if not bool(validation.get("ok", false)):
		return

	var canonical_pickup := _object_by_id(
		validation["data"],
		"double_jump"
	)
	var canonical_keys: Array = canonical_pickup.keys()
	canonical_keys.sort()
	_expect(
		canonical_pickup.get("type") == "double_jump_pickup"
		and canonical_pickup.get("position") == [300, 450]
		and canonical_keys == ["id", "position", "type"],
		"double_jump_pickup did not preserve its closed canonical contract: %s"
		% [canonical_pickup]
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
		"double_jump_pickup JSON did not survive a deterministic round trip."
	)

	var edge_position := _make_level()
	_object_by_id(edge_position, "double_jump")["position"] = [44, 44]
	var edge_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(edge_position)
	)
	_expect(
		bool(edge_result.get("ok", false)),
		"Validator rejected a pickup whose 12px radius touches the playfield edge."
	)

	var outside_playfield := _make_level()
	_object_by_id(outside_playfield, "double_jump")["position"] = [43, 44]
	_expect_invalid_with(
		outside_playfield,
		"runtime playfield",
		"double_jump_pickup outside the runtime playfield"
	)

	var missing_position := _make_level()
	_object_by_id(missing_position, "double_jump").erase("position")
	_expect_invalid_with(
		missing_position,
		"missing required key 'position'",
		"double_jump_pickup without a position"
	)

	var malformed_position := _make_level()
	_object_by_id(malformed_position, "double_jump")["position"] = [300]
	_expect_invalid_with(
		malformed_position,
		"exactly 2 integers",
		"double_jump_pickup with a malformed position"
	)

	var unknown_property := _make_level()
	_object_by_id(unknown_property, "double_jump")["duration"] = 10
	_expect_invalid_with(
		unknown_property,
		"unknown key 'duration'",
		"double_jump_pickup with an open-ended property"
	)


func _test_builder_collection_and_jump_contract() -> void:
	var runtime := await _create_runtime()
	if not is_instance_valid(runtime):
		return

	var player := runtime.get_level_object("player_start") as Player
	var enemy := runtime.get_level_object("patrol_1") as PatrolEnemy
	var pickup := (
		runtime.get_level_object("double_jump") as DoubleJumpPickup
	)
	var collision := (
		pickup.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(pickup)
		else null
	)
	var circle := (
		collision.shape as CircleShape2D
		if is_instance_valid(collision)
		else null
	)
	_expect(
		runtime.level_loaded
		and is_instance_valid(player)
		and is_instance_valid(enemy)
		and is_instance_valid(pickup)
		and pickup.get_parent() == runtime.get_node("Geometry/LevelObjects")
		and pickup.position == Vector2(300, 450)
		and is_instance_valid(circle)
		and is_equal_approx(circle.radius, 12.0),
		"Builder did not register the canonical double-jump pickup scene."
	)
	if (
		not is_instance_valid(player)
		or not is_instance_valid(enemy)
		or not is_instance_valid(pickup)
	):
		await _free_runtime(runtime)
		return

	var collected_players: Array[Player] = []
	pickup.collected.connect(
		func(collected_player: Player) -> void:
			collected_players.append(collected_player)
	)
	pickup.call("_on_body_entered", enemy)
	_expect(
		not pickup.is_collected
		and pickup.visible
		and not pickup.is_queued_for_deletion()
		and collected_players.is_empty(),
		"A non-player body consumed the double-jump pickup."
	)

	var landed := await _wait_until_grounded(player)
	_expect(landed, "Player did not settle on the smoke-test floor.")
	if not landed:
		await _free_runtime(runtime)
		return

	player.jump_requested = true
	await physics_frame
	_expect(
		not player.is_on_floor() and player.velocity.y < 0.0,
		"Player did not perform the initial ground jump."
	)
	player.velocity.y = 100.0
	player.jump_requested = true
	await physics_frame
	_expect(
		not player.has_double_jump
		and not player.air_jump_available
		and player.velocity.y > 100.0,
		"Player performed an air jump before collecting the pickup."
	)

	pickup.call("_on_body_entered", player)
	pickup.call("_on_body_entered", player)
	_expect(
		pickup.is_collected
		and not pickup.visible
		and pickup.is_queued_for_deletion()
		and player.has_double_jump
		and player.air_jump_available
		and collected_players == [player],
		"Player collection did not atomically unlock and consume the pickup once."
	)

	player.velocity.y = 100.0
	player.jump_requested = true
	await physics_frame
	_expect(
		is_equal_approx(player.velocity.y, player.jump_velocity)
		and not player.air_jump_available,
		"The first airborne press after pickup did not perform one air jump."
	)
	player.velocity.y = 100.0
	player.jump_requested = true
	await physics_frame
	_expect(
		player.velocity.y > 100.0 and not player.air_jump_available,
		"A third jump was accepted before landing."
	)

	var repeated_unlock := player.unlock_double_jump()
	_expect(
		repeated_unlock and not player.air_jump_available,
		"Repeated unlock refilled an already spent airborne charge."
	)

	player.air_jump_available = true
	player.knockback_time_remaining = 0.2
	player.velocity.y = 100.0
	player.jump_requested = true
	await physics_frame
	_expect(
		player.air_jump_available
		and not is_equal_approx(player.velocity.y, player.jump_velocity),
		"A control-locked jump consumed the airborne charge."
	)
	player.knockback_time_remaining = 0.0
	player.air_jump_available = false
	player.position = Vector2(150, 430)
	player.velocity = Vector2(0, 180)
	landed = await _wait_until_grounded(player)
	_expect(
		landed and player.air_jump_available,
		"Landing did not refill the unlocked airborne jump."
	)
	if landed:
		player.jump_requested = true
		await physics_frame
		player.velocity.y = 100.0
		player.jump_requested = true
		await physics_frame
		_expect(
			is_equal_approx(player.velocity.y, player.jump_velocity)
			and not player.air_jump_available,
			"The refilled airborne jump was not usable after landing."
		)

	await _free_runtime(runtime)

	var fresh_runtime := await _create_runtime()
	if not is_instance_valid(fresh_runtime):
		return
	var fresh_player := (
		fresh_runtime.get_level_object("player_start") as Player
	)
	var fresh_pickup := (
		fresh_runtime.get_level_object("double_jump") as DoubleJumpPickup
	)
	_expect(
		is_instance_valid(fresh_player)
		and is_instance_valid(fresh_pickup)
		and not fresh_player.has_double_jump
		and not fresh_player.air_jump_available
		and not fresh_pickup.is_collected
		and fresh_pickup.visible,
		"A fresh arena runtime did not reset the unlock and respawn the pickup."
	)
	if is_instance_valid(fresh_player) and is_instance_valid(fresh_pickup):
		fresh_player.is_defeated = true
		fresh_pickup.call("_on_body_entered", fresh_player)
		var rejected_defeat := not fresh_pickup.is_collected
		fresh_player.is_defeated = false
		fresh_player.is_clear_celebrating = true
		fresh_pickup.call("_on_body_entered", fresh_player)
		_expect(
			rejected_defeat
			and not fresh_pickup.is_collected
			and not fresh_player.has_double_jump,
			"Defeated or clear-locked player consumed the pickup."
		)
	await _free_runtime(fresh_runtime)


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		is_instance_valid(editor.double_jump_button)
		and editor.double_jump_button.text.begins_with("J"),
		"Editor did not expose the J double-jump pickup palette button."
	)
	await _press_physical_key(KEY_J)
	_expect(
		editor.active_tool == "double_jump_pickup"
		and editor.double_jump_button.button_pressed,
		"Physical J did not select the double_jump_pickup tool."
	)

	editor.canvas.call(
		"_begin_primary_action",
		Vector2(300, 420) * 0.6
	)
	await process_frame
	var pickup_id := editor.selected_id
	var placed := editor.draft.find_object(pickup_id)
	_expect(
		placed.get("type") == "double_jump_pickup"
		and placed.get("position") == [300, 420]
		and bool(editor.validation_result.get("ok", false)),
		"Editor did not place a canonical double_jump_pickup point object."
	)

	editor.call("_set_tool", "select")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(300, 420) * 0.6
	)
	editor.canvas.call(
		"_update_drag",
		Vector2(320, 400) * 0.6
	)
	editor.canvas.call(
		"_finish_primary_action",
		Vector2(320, 400) * 0.6
	)
	await process_frame
	var moved := editor.draft.find_object(pickup_id)
	_expect(
		moved.get("position") == [320, 400],
		"Canvas hit-test and drag did not move the pickup as a point object."
	)

	editor.call("_duplicate_selected")
	await process_frame
	var duplicate_id := editor.selected_id
	var duplicate := editor.draft.find_object(duplicate_id)
	_expect(
		not duplicate_id.is_empty()
		and duplicate_id != pickup_id
		and duplicate.get("type") == "double_jump_pickup"
		and duplicate.get("position") == [340, 420],
		"Duplicate did not preserve and offset the pickup contract."
	)

	var x_field := _find_property_editor(editor, "X") as LineEdit
	var y_field := _find_property_editor(editor, "Y") as LineEdit
	_expect(
		is_instance_valid(x_field)
		and is_instance_valid(y_field)
		and x_field.text == "340"
		and y_field.text == "420"
		and "ДВОЙНОЙ ПРЫЖОК" in editor.inspector_hint.text,
		"Pickup inspector did not expose position and the arena-lifetime hint."
	)

	editor.call("_start_playtest")
	await process_frame
	await physics_frame
	var playtest := editor.playtest_runtime as LevelRuntimeArena
	var playtest_pickup := (
		playtest.get_level_object(duplicate_id) as DoubleJumpPickup
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
		and is_instance_valid(playtest_pickup)
		and is_instance_valid(playtest_player)
		and not playtest_player.has_double_jump,
		"Editor playtest did not build the pickup and a locked player."
	)
	if (
		is_instance_valid(playtest_pickup)
		and is_instance_valid(playtest_player)
	):
		playtest_pickup.call("_on_body_entered", playtest_player)
		_expect(
			playtest_player.has_double_jump
			and playtest_pickup.is_collected,
			"Editor playtest pickup did not unlock double jump."
		)
	if is_instance_valid(playtest):
		editor.call("_stop_playtest")
		await process_frame

	current_scene = null
	editor.queue_free()
	await editor.tree_exited


func _create_runtime() -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(_make_level())
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode the double-jump pickup runtime fixture: %s"
		% [encoded.get("errors", [])]
	)
	if not bool(encoded.get("ok", false)):
		return null

	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded.get("text", "")))
	root.add_child(runtime)
	await process_frame
	await physics_frame
	_expect(
		runtime.level_loaded,
		"Double-jump pickup runtime fixture did not load: %s"
		% [runtime.load_errors]
	)
	if not runtime.level_loaded:
		await _free_runtime(runtime)
		return null
	return runtime


func _free_runtime(runtime: LevelRuntimeArena) -> void:
	if not is_instance_valid(runtime):
		return
	runtime.queue_free()
	await runtime.tree_exited


func _wait_until_grounded(player: Player, frames := 120) -> bool:
	for _frame in frames:
		if not is_instance_valid(player):
			return false
		if player.is_on_floor():
			return true
		await physics_frame
	return is_instance_valid(player) and player.is_on_floor()


func _make_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "double_jump_pickup_smoke",
		"title": "DOUBLE JUMP PICKUP SMOKE",
		"objective": "COLLECT AND JUMP",
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
				"id": "player_start",
				"type": "player_spawn",
				"position": [150, 450],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [760, 450],
				"direction": -1,
				"speed": 0,
			},
			{
				"id": "double_jump",
				"type": "double_jump_pickup",
				"position": [300, 450],
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

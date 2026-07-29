extends SceneTree

const LEVEL_PATH := "res://levels/arena_01.json"
const RUNTIME_SCENE := preload(
	"res://scenes/data_arena_01.tscn"
)
const PATROL_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const RUNTIME_SCRIPT := preload(
	"res://scripts/levels/level_runtime_arena.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_codec_round_trip()
	_test_invalid_data()
	await _test_runtime_snapshot_and_idle()
	await _test_real_attack_clears_level()
	await _test_player_fall_reloads_level()
	await _test_manual_restart()

	if failures.is_empty():
		print("LEVEL_FOUNDATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_codec_round_trip() -> void:
	var loaded: Dictionary = LEVEL_DATA_CODEC.load_file(LEVEL_PATH)
	_expect(bool(loaded["ok"]), "Valid Arena 01 JSON was rejected.")
	if not bool(loaded["ok"]):
		return

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(loaded["data"])
	_expect(
		bool(encoded_once["ok"]),
		"Normalized Arena 01 data could not be encoded."
	)
	if not bool(encoded_once["ok"]):
		return

	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		encoded_once["text"]
	)
	_expect(
		bool(decoded["ok"]),
		"Encoded Arena 01 JSON did not pass a second validation."
	)
	if not bool(decoded["ok"]):
		return

	var encoded_twice: Dictionary = LEVEL_DATA_CODEC.encode(
		decoded["data"]
	)
	_expect(
		encoded_once["text"] == encoded_twice["text"],
		"JSON encoding is not deterministic across two round trips."
	)


func _test_invalid_data() -> void:
	var loaded: Dictionary = LEVEL_DATA_CODEC.load_file(LEVEL_PATH)
	if not bool(loaded["ok"]):
		failures.append("Could not prepare invalid-data fixtures.")
		return

	var malformed: Dictionary = LEVEL_DATA_CODEC.decode_text("{")
	_expect(
		not bool(malformed["ok"]),
		"Malformed JSON was accepted."
	)

	var non_dictionary: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize([])
	)
	_expect(
		not bool(non_dictionary["ok"]),
		"A non-dictionary JSON root was accepted."
	)

	var unknown_type: Dictionary = loaded["data"].duplicate(true)
	unknown_type["objects"][0]["type"] = "arbitrary_scene"
	_expect_invalid(unknown_type, "unknown object type")

	var duplicate_id: Dictionary = loaded["data"].duplicate(true)
	duplicate_id["objects"][1]["id"] = duplicate_id["objects"][0]["id"]
	_expect_invalid(duplicate_id, "duplicate object ID")

	var unsafe_id: Dictionary = loaded["data"].duplicate(true)
	unsafe_id["objects"][0]["id"] = "left-floor"
	_expect_invalid(unsafe_id, "non-snake-case object ID")

	var missing_player: Dictionary = loaded["data"].duplicate(true)
	for index in range(missing_player["objects"].size() - 1, -1, -1):
		if missing_player["objects"][index]["type"] == "player_spawn":
			missing_player["objects"].remove_at(index)
	_expect_invalid(missing_player, "missing player")

	var out_of_bounds: Dictionary = loaded["data"].duplicate(true)
	out_of_bounds["objects"][0]["rect"] = [900, 496, 368, 44]
	_expect_invalid(out_of_bounds, "out-of-bounds rectangle")

	var unknown_property: Dictionary = loaded["data"].duplicate(true)
	unknown_property["objects"][2]["script_path"] = "res://bad.gd"
	_expect_invalid(unknown_property, "unknown object property")

	var wrong_canvas: Dictionary = loaded["data"].duplicate(true)
	wrong_canvas["canvas"]["width"] = 1280
	_expect_invalid(wrong_canvas, "unsupported canvas size")

	var spawn_inside_floor: Dictionary = loaded["data"].duplicate(true)
	spawn_inside_floor["objects"][2]["position"] = [150, 510]
	_expect_invalid(spawn_inside_floor, "spawn inside solid geometry")

	var spawn_clipping_floor: Dictionary = loaded["data"].duplicate(true)
	spawn_clipping_floor["objects"][2]["position"] = [150, 495]
	_expect_invalid(spawn_clipping_floor, "spawn collider clipping a floor")

	var spawn_clipping_wall: Dictionary = loaded["data"].duplicate(true)
	spawn_clipping_wall["objects"][2]["position"] = [40, 450]
	_expect_invalid(
		spawn_clipping_wall,
		"spawn collider clipping an immutable wall"
	)

	var actors_touching_floor: Dictionary = loaded["data"].duplicate(true)
	actors_touching_floor["objects"][2]["position"] = [150, 476]
	actors_touching_floor["objects"][3]["position"] = [360, 478]
	var touching_result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(
			actors_touching_floor
		)
	)
	_expect(
		bool(touching_result["ok"]),
		"Validator rejected actors resting exactly on a floor."
	)


func _test_runtime_snapshot_and_idle() -> void:
	var foreign_enemy := PATROL_SCENE.instantiate() as PatrolEnemy
	foreign_enemy.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(foreign_enemy)

	var arena := await _create_runtime()
	_expect(arena.level_loaded, "Runtime Arena 01 did not load.")
	_expect(
		arena.enemies_remaining == 1,
		"Runtime counted an enemy outside its own tree."
	)
	_expect(
		arena.find_children("*", "StaticBody2D", true, false).size()
		== 5,
		"Runtime Arena 01 does not contain five static bodies."
	)

	var left_floor := arena.call("get_level_object", "left_floor") as Node
	var right_floor := arena.call("get_level_object", "right_floor") as Node
	var player := (
		arena.call("get_level_object", "player_start") as Player
	)
	var enemy := (
		arena.call("get_level_object", "patrol_1") as PatrolEnemy
	)
	_expect(
		is_instance_valid(left_floor)
		and left_floor.position.is_equal_approx(Vector2(216, 518)),
		"Left floor snapshot differs from Arena 01."
	)
	_expect(
		is_instance_valid(right_floor)
		and right_floor.position.is_equal_approx(Vector2(744, 518)),
		"Right floor snapshot differs from Arena 01."
	)
	_expect(
		player.position.is_equal_approx(Vector2(150, 450)),
		"Player start differs from Arena 01."
	)
	_expect(
		enemy.position.is_equal_approx(Vector2(360, 450)),
		"Patrol start differs from Arena 01."
	)
	_expect(
		is_equal_approx(enemy.patrol_speed, 65.0)
		and is_equal_approx(enemy.patrol_direction, 1.0),
		"Patrol parameters differ from Arena 01."
	)
	var player_shape := (
		player.get_node("CollisionShape2D") as CollisionShape2D
	).shape as RectangleShape2D
	var enemy_shape := (
		enemy.get_node("CollisionShape2D") as CollisionShape2D
	).shape as RectangleShape2D
	_expect(
		(player_shape.size * 0.5).is_equal_approx(
			Vector2(
				LEVEL_DATA_VALIDATOR.ACTOR_HALF_EXTENTS["player_spawn"]
			)
		)
		and (enemy_shape.size * 0.5).is_equal_approx(
			Vector2(
				LEVEL_DATA_VALIDATOR.ACTOR_HALF_EXTENTS["patrol_enemy"]
			)
		),
		"Validator actor bounds drifted from the runtime colliders."
	)

	if is_instance_valid(left_floor) and is_instance_valid(right_floor):
		var left_shape := (
			left_floor.get_node("CollisionShape2D") as CollisionShape2D
		).shape as RectangleShape2D
		var right_shape := (
			right_floor.get_node("CollisionShape2D") as CollisionShape2D
		).shape as RectangleShape2D
		_expect(
			left_shape.size.is_equal_approx(Vector2(368, 44)),
			"Generated floor collision has the wrong size."
		)
		_expect(
			left_shape != right_shape,
			"Generated floors unexpectedly share one mutable shape."
		)

	for _frame in range(30):
		await physics_frame
	_expect(
		player.is_on_floor()
		and absf(player.global_position.y - 476.0) <= 1.0,
		"Player did not settle on generated floor."
	)
	_expect(
		enemy.is_on_floor()
		and absf(enemy.global_position.y - 478.0) <= 1.0,
		"Patrol did not settle on generated floor."
	)

	for _frame in range(300):
		await physics_frame
	_expect(
		arena.enemies_remaining == 1
		and arena.pending_outcome == Arena.Outcome.NONE,
		"Runtime Arena 01 changed outcome while idle."
	)

	foreign_enemy.queue_free()
	await process_frame
	await _cleanup_current_scene()


func _test_real_attack_clears_level() -> void:
	var arena := await _create_runtime()
	arena.clear_restart_delay = 10.0
	var player := (
		arena.call("get_level_object", "player_start") as Player
	)
	var enemy := (
		arena.call("get_level_object", "patrol_1") as PatrolEnemy
	)

	for _frame in range(30):
		await physics_frame
	enemy.patrol_speed = 0.0
	enemy.global_position = Vector2(370.0, 478.0)
	enemy.velocity = Vector2.ZERO
	player.global_position = Vector2(315.0, 476.0)
	player.velocity = Vector2.ZERO
	await physics_frame
	await _press_physical_key(KEY_X)

	for _frame in range(180):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame

	_expect(
		arena.enemies_remaining == 0,
		"A real player attack did not remove the patrol enemy."
	)
	_expect(
		arena.pending_outcome == Arena.Outcome.CLEAR,
		"Enemy elimination did not produce CLEAR."
	)
	await _cleanup_current_scene()


func _test_player_fall_reloads_level() -> void:
	var arena := await _create_runtime()
	arena.fall_restart_delay = 0.01
	var original_id := arena.get_instance_id()
	var player := (
		arena.call("get_level_object", "player_start") as Player
	)
	player.global_position = Vector2(480.0, 530.0)
	player.velocity = Vector2.ZERO

	for _frame in range(60):
		await process_frame
		await physics_frame
		if (
			is_instance_valid(current_scene)
			and current_scene.get_instance_id() != original_id
		):
			break

	_expect(
		is_instance_valid(current_scene)
		and current_scene.get_instance_id() != original_id
		and current_scene.scene_file_path
		== "res://scenes/data_arena_01.tscn",
		"Player fall did not reload the data-driven scene."
	)
	if (
		is_instance_valid(current_scene)
		and current_scene.get_script() == RUNTIME_SCRIPT
	):
		_expect(
			current_scene.level_loaded
			and current_scene.enemies_remaining == 1,
			"Reloaded data-driven scene did not rebuild initial state."
		)
	await _cleanup_current_scene()


func _test_manual_restart() -> void:
	var arena := await _create_runtime()
	var original_id := arena.get_instance_id()
	await _press_physical_key(KEY_R)

	for _frame in range(60):
		await process_frame
		if (
			is_instance_valid(current_scene)
			and current_scene.get_instance_id() != original_id
		):
			break

	_expect(
		is_instance_valid(current_scene)
		and current_scene.get_instance_id() != original_id
		and current_scene.scene_file_path
		== "res://scenes/data_arena_01.tscn",
		"Physical R did not reload the data-driven scene."
	)
	await _cleanup_current_scene()


func _create_runtime() -> Node:
	var arena := RUNTIME_SCENE.instantiate()
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


func _expect_invalid(data: Dictionary, label: String) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(not bool(result["ok"]), "Validator accepted %s." % label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

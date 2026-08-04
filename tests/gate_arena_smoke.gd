extends SceneTree

const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_gate_arena_solution()
	await _cleanup_current_scene()

	if failures.is_empty():
		print("GATE_ARENA_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_gate_arena_solution() -> void:
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(
		"arena_12_data"
	)
	_expect(
		bool(loaded.get("ok", false))
		and loaded.get("warnings", []).is_empty(),
		"Arena 12 did not pass built-in validation: %s / %s"
		% [loaded.get("errors", []), loaded.get("warnings", [])]
	)
	if not bool(loaded.get("ok", false)):
		return

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(loaded["data"])
	_expect(
		bool(encoded.get("ok", false)),
		"Arena 12 could not be encoded for runtime."
	)
	if not bool(encoded.get("ok", false)):
		return

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(str(encoded["text"]))
	arena.clear_restart_delay = 10.0
	root.add_child(arena)
	current_scene = arena
	await process_frame

	var gate := arena.get_level_object("gate") as TogglePlatform
	var entry_hinge := arena.get_level_object("entry_hinge") as Hinge
	var eject_hinge := arena.get_level_object("eject_hinge") as Hinge
	var player := arena.get_level_object("player_start") as Player
	var shooter := arena.get_level_object("shooter") as ShooterEnemy
	_expect(
		arena.level_loaded
		and arena.load_errors.is_empty()
		and arena.level_objects.size() == 8
		and is_instance_valid(gate)
		and is_instance_valid(entry_hinge)
		and is_instance_valid(eject_hinge)
		and is_instance_valid(player)
		and is_instance_valid(shooter),
		"Arena 12 runtime did not build its eight required objects."
	)
	if (
		not is_instance_valid(gate)
		or not is_instance_valid(entry_hinge)
		or not is_instance_valid(eject_hinge)
		or not is_instance_valid(player)
		or not is_instance_valid(shooter)
	):
		return

	_expect(
		gate.is_vertical_wall
		and gate.is_active
		and entry_hinge.target == gate
		and eject_hinge.target == gate
		and arena.enemies_remaining == 1,
		"Arena 12 gate links or initial state drifted."
	)

	for _frame in range(30):
		await physics_frame
		if player.is_on_floor() and shooter.is_on_floor():
			break

	player.global_position = Vector2(430, 380)
	player.velocity = Vector2.ZERO
	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	await physics_frame
	await process_frame
	await _press_physical_key(KEY_X)
	await _wait_for_gate_state(gate, false)
	_expect(
		not gate.is_active and gate.collision_shape.disabled,
		"A physical attack on the entry hinge did not open Arena 12."
	)
	for _frame in range(30):
		await physics_frame
		if is_zero_approx(player.attack_cooldown_remaining):
			break

	player.global_position = Vector2(646, 476)
	player.velocity = Vector2.ZERO
	player.facing_direction = -1.0
	player.visual.scale.x = -1.0
	player.attack_pivot.scale.x = -1.0
	shooter.global_position = Vector2(590, 478)
	shooter.velocity = Vector2.ZERO
	await physics_frame
	await process_frame

	var ejection_event := {"count": 0}
	var blocked_event := {"count": 0}
	var hit_ids := {}
	gate.bodies_ejected.connect(
		func(count: int) -> void:
			ejection_event["count"] = count
	)
	gate.toggle_blocked.connect(
		func() -> void:
			blocked_event["count"] += 1
	)
	player.attack_landed.connect(
		func(target: Node2D, _position: Vector2, _impulse: Vector2) -> void:
			hit_ids[target.get_instance_id()] = true
	)
	await _press_physical_key(KEY_X)
	await _wait_for_gate_state(gate, true)
	_expect(
		gate.is_active
		and not gate.collision_shape.disabled
		and int(ejection_event["count"]) == 1
		and int(blocked_event["count"]) == 0
		and hit_ids.has(eject_hinge.get_instance_id())
		and hit_ids.has(shooter.get_instance_id())
		and shooter.global_position.x < 540
		and shooter.velocity.x < 0,
		(
			(
				"Arena 12 attack did not close the gate and eject the "
				+ "shooter into the pit: active=%s ejected=%s "
				+ "blocked=%s hits=%s position=%s velocity=%s."
			)
			% [
				gate.is_active,
				ejection_event["count"],
				blocked_event["count"],
				hit_ids.keys(),
				shooter.global_position,
				shooter.velocity,
			]
		)
	)

	for _frame in range(240):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame
	_expect(
		arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR,
		"The gate-ejected shooter did not produce Arena 12 CLEAR."
	)


func _wait_for_gate_state(
	gate: TogglePlatform,
	expected_active: bool
) -> void:
	for _frame in range(90):
		await process_frame
		await physics_frame
		if (
			gate.is_active == expected_active
			and not gate.is_transitioning
		):
			return
	_expect(
		false,
		"Arena 12 gate did not reach active=%s." % expected_active
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
	var scene := current_scene
	current_scene = null
	if not is_instance_valid(scene):
		return
	scene.queue_free()
	await scene.tree_exited


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

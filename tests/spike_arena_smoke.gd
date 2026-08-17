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

const LEVEL_ID := "arena_14_data"
const LEVEL_TITLE := "GRAYBOX  /  DATA ARENA 14  /  ШИПЫ"
const SPIKE_RECT := Rect2(380.0, 476.0, 220.0, 20.0)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = _load_and_verify_level()
	if bool(loaded.get("ok", false)):
		var data := loaded.get("data", {}) as Dictionary
		await _test_player_dies_on_spikes(data)
		await _release_physical_key(KEY_D)
		await _cleanup_current_scene()
		await _test_intended_solution(data)
		await _release_physical_key(KEY_A)
		await _release_physical_key(KEY_D)
		await _cleanup_current_scene()

	if failures.is_empty():
		print("SPIKE_ARENA_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _load_and_verify_level() -> Dictionary:
	var catalog_entry := _catalog_entry(LEVEL_ID)
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(LEVEL_ID)
	_expect(
		catalog_entry.get("path") == "res://levels/arena_14.json"
		and catalog_entry.get("title") == "Arena 14 / Шипы"
		and bool(loaded.get("ok", false))
		and loaded.get("warnings", []).is_empty(),
		(
			"Arena 14 is missing from the campaign catalog or failed "
			+ "validation: %s / %s"
		)
		% [loaded.get("errors", []), loaded.get("warnings", [])]
	)
	if not bool(loaded.get("ok", false)):
		return loaded

	var data := loaded.get("data", {}) as Dictionary
	var left_floor := _object_by_id(data, "left_floor")
	var right_floor := _object_by_id(data, "right_floor")
	var spikes := _object_by_id(data, "center_spikes")
	var player_spawn := _object_by_id(data, "player_start")
	var pickup := _object_by_id(data, "double_jump_1")
	var patrol := _object_by_id(data, "patrol_1")
	_expect(
		data.get("level_id") == LEVEL_ID
		and data.get("title") == LEVEL_TITLE
		and data.get("objects", []).size() == 6
		and left_floor.get("rect") == [32, 496, 348, 44]
		and not bool(left_floor.get("one_way", true))
		and right_floor.get("rect") == [600, 496, 328, 44]
		and not bool(right_floor.get("one_way", true))
		and spikes.get("type") == "spike_trap"
		and spikes.get("rect") == [380, 476, 220, 20]
		and player_spawn.get("position") == [100, 450]
		and pickup.get("type") == "double_jump_pickup"
		and pickup.get("position") == [220, 450]
		and patrol.get("type") == "patrol_enemy"
		and patrol.get("position") == [660, 450]
		and patrol.get("direction") == 1
		and is_equal_approx(float(patrol.get("speed", -1.0)), 20.0),
		"Arena 14 composition or mandatory spike route drifted."
	)
	return loaded


func _test_player_dies_on_spikes(data: Dictionary) -> void:
	var arena := await _create_runtime(data)
	if not is_instance_valid(arena):
		return

	var player := arena.get_level_object("player_start") as Player
	var patrol := arena.get_level_object("patrol_1") as PatrolEnemy
	var spikes := arena.get_level_object("center_spikes") as Area2D
	_expect_runtime_composition(arena, player, patrol, spikes)
	if not is_instance_valid(player) or not is_instance_valid(spikes):
		return

	var settled := await _wait_until_grounded(player)
	_expect(settled, "Arena 14 player did not settle on the start floor.")
	if not settled:
		return

	# Start a genuine ordinary jump at the edge without granting the pickup.
	# Its natural range ends inside the 220 px spike bed.
	player.global_position = Vector2(356.0, 476.0)
	player.velocity = Vector2.ZERO
	await physics_frame
	_expect(
		not player.has_double_jump,
		"Arena 14 danger probe unexpectedly started with double jump."
	)

	await _set_physical_key(KEY_D, true)
	player.jump_requested = true
	await physics_frame
	var defeat_position := Vector2.ZERO
	for _frame in range(180):
		await physics_frame
		if player.is_defeated:
			defeat_position = player.global_position
			break
	await _release_physical_key(KEY_D)

	_expect(
		player.is_defeated
		and player.defeat_cause == Player.DefeatCause.HAZARD
		and arena.pending_outcome == Arena.Outcome.FALL
		and arena.enemies_remaining == 1
		and defeat_position.x >= SPIKE_RECT.position.x - 15.0
		and defeat_position.x <= SPIKE_RECT.end.x + 15.0
		and defeat_position.y >= SPIKE_RECT.position.y - 21.0
		and defeat_position.y <= SPIKE_RECT.end.y + 21.0,
		(
			"An ordinary jump did not cause a real spike defeat: "
			+ "position=%s defeated=%s cause=%s outcome=%s enemies=%s."
		)
		% [
			defeat_position,
			player.is_defeated,
			player.defeat_cause,
			arena.pending_outcome,
			arena.enemies_remaining,
		]
	)


func _test_intended_solution(data: Dictionary) -> void:
	var arena := await _create_runtime(data)
	if not is_instance_valid(arena):
		return

	var player := arena.get_level_object("player_start") as Player
	var patrol := arena.get_level_object("patrol_1") as PatrolEnemy
	var pickup := (
		arena.get_level_object("double_jump_1") as DoubleJumpPickup
	)
	var spikes := arena.get_level_object("center_spikes") as Area2D
	_expect_runtime_composition(arena, player, patrol, spikes)
	_expect(
		is_instance_valid(pickup),
		"Arena 14 runtime did not build its double-jump pickup."
	)
	if (
		not is_instance_valid(player)
		or not is_instance_valid(patrol)
		or not is_instance_valid(pickup)
		or not is_instance_valid(spikes)
	):
		return

	var settled := await _wait_until_grounded(player)
	_expect(settled, "Arena 14 solution player did not settle.")
	if not settled:
		return

	var pickup_ref: WeakRef = weakref(pickup)
	var reached_takeoff := await _walk_right_until(player, 340.0, 180)
	await process_frame
	_expect(
		reached_takeoff
		and player.has_double_jump
		and player.air_jump_available
		and not is_instance_valid(pickup_ref.get_ref()),
		"Arena 14 route did not collect and consume the pickup."
	)
	if not reached_takeoff or not player.has_double_jump:
		return

	await _set_physical_key(KEY_D, true)
	player.jump_requested = true
	await physics_frame
	var used_air_jump := false
	var cleared_spikes := false
	var released_right := false
	for _frame in range(180):
		await physics_frame
		if (
			not used_air_jump
			and not player.is_on_floor()
			and player.velocity.y >= -30.0
		):
			player.jump_requested = true
			await physics_frame
			used_air_jump = (
				is_equal_approx(player.velocity.y, player.jump_velocity)
				and not player.air_jump_available
			)
		if not released_right and player.global_position.x >= 620.0:
			await _release_physical_key(KEY_D)
			released_right = true
		if (
			used_air_jump
			and player.is_on_floor()
			and player.global_position.x >= 614.0
		):
			cleared_spikes = true
			break
		if player.is_defeated:
			break
	if not released_right:
		await _release_physical_key(KEY_D)
	_expect(
		used_air_jump and cleared_spikes and not player.is_defeated,
		(
			"Arena 14 double-jump crossing failed: air_jump=%s "
			+ "cleared=%s position=%s defeated=%s."
		)
		% [
			used_air_jump,
			cleared_spikes,
			player.global_position,
			player.is_defeated,
		]
	)
	if not cleared_spikes or player.is_defeated:
		return

	# Build ground speed before jumping over the live patrol. Its AI remains
	# enabled with the exact speed and direction declared by the level.
	await _set_physical_key(KEY_D, true)
	for _frame in range(45):
		await physics_frame
		if player.global_position.x >= 665.0:
			break
	player.jump_requested = true
	await physics_frame
	var passed_patrol := false
	for _frame in range(180):
		await physics_frame
		if player.global_position.x >= patrol.global_position.x + 55.0:
			passed_patrol = true
			break
		if player.is_defeated:
			break
	await _release_physical_key(KEY_D)
	_expect(
		passed_patrol and not player.is_defeated,
		(
			"Player did not pass the live Arena 14 patrol: "
			+ "player=%s patrol=%s defeated=%s."
		)
		% [
			player.global_position,
			patrol.global_position,
			player.is_defeated,
		]
	)
	if not passed_patrol or player.is_defeated:
		return

	var landed_behind := await _wait_until_grounded(player)
	_expect(landed_behind, "Player did not land behind the Arena 14 patrol.")
	if not landed_behind:
		return

	await _set_physical_key(KEY_A, true)
	for _frame in range(90):
		await physics_frame
		if (
			player.is_defeated
			or player.global_position.x
			<= patrol.global_position.x + 48.0
		):
			break
	await _release_physical_key(KEY_A)
	_expect(
		not player.is_defeated
		and player.facing_direction < 0.0
		and player.global_position.x > patrol.global_position.x,
		(
			"Player could not take a safe attack position behind patrol: "
			+ "player=%s patrol=%s facing=%s."
		)
		% [
			player.global_position,
			patrol.global_position,
			player.facing_direction,
		]
	)
	if player.is_defeated:
		return

	var hit_patrol := {"value": false}
	player.attack_landed.connect(
		func(target: Node2D, _position: Vector2, _impulse: Vector2) -> void:
			if target == patrol:
				hit_patrol["value"] = true
	)
	var patrol_ref: WeakRef = weakref(patrol)
	await _press_physical_key(KEY_X)
	for _frame in range(240):
		await physics_frame
		if arena.pending_outcome == Arena.Outcome.CLEAR:
			break
		if player.is_defeated:
			break
	await process_frame

	_expect(
		bool(hit_patrol["value"])
		and not is_instance_valid(patrol_ref.get_ref())
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and not player.is_defeated,
		(
			"Arena 14 real solution did not knock patrol onto spikes "
			+ "for CLEAR: hit=%s alive=%s enemies=%s outcome=%s "
			+ "player_defeated=%s."
		)
		% [
			hit_patrol["value"],
			is_instance_valid(patrol_ref.get_ref()),
			arena.enemies_remaining,
			arena.pending_outcome,
			player.is_defeated,
		]
	)


func _expect_runtime_composition(
	arena: LevelRuntimeArena,
	player: Player,
	patrol: PatrolEnemy,
	spikes: Area2D
) -> void:
	var collision: CollisionShape2D = null
	var shape: RectangleShape2D = null
	if is_instance_valid(spikes):
		collision = spikes.get_node_or_null(
			"CollisionShape2D"
		) as CollisionShape2D
	if is_instance_valid(collision):
		shape = collision.shape as RectangleShape2D
	_expect(
		arena.level_loaded
		and arena.load_errors.is_empty()
		and arena.level_objects.size() == 6
		and arena.enemies_remaining == 1
		and is_instance_valid(player)
		and is_instance_valid(patrol)
		and is_instance_valid(spikes)
		and spikes.position.is_equal_approx(SPIKE_RECT.get_center())
		and is_instance_valid(shape)
		and shape.size.is_equal_approx(SPIKE_RECT.size)
		and is_equal_approx(patrol.patrol_speed, 20.0),
		"Arena 14 runtime did not build its six-object live composition."
	)


func _create_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded.get("ok", false)),
		"Arena 14 could not be encoded for runtime: %s"
		% [encoded.get("errors", [])]
	)
	if not bool(encoded.get("ok", false)):
		return null

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(str(encoded.get("text", "")))
	arena.fall_restart_delay = 10.0
	arena.clear_restart_delay = 10.0
	root.add_child(arena)
	current_scene = arena
	await process_frame
	return arena


func _catalog_entry(level_id: String) -> Dictionary:
	for entry: Dictionary in LEVEL_STORAGE.list_builtin_levels():
		if entry.get("id", "") == level_id:
			return entry
	return {}


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _walk_right_until(
	player: Player,
	target_x: float,
	frames: int
) -> bool:
	await _set_physical_key(KEY_D, true)
	for _frame in frames:
		await physics_frame
		if not is_instance_valid(player) or player.is_defeated:
			await _release_physical_key(KEY_D)
			return false
		if player.global_position.x >= target_x:
			await _release_physical_key(KEY_D)
			for _settle_frame in range(8):
				await physics_frame
			return true
	await _release_physical_key(KEY_D)
	return false


func _wait_until_grounded(
	body: CharacterBody2D,
	frames := 180
) -> bool:
	for _frame in frames:
		if not is_instance_valid(body):
			return false
		if body.is_on_floor():
			return true
		await physics_frame
	return is_instance_valid(body) and body.is_on_floor()


func _press_physical_key(key: Key) -> void:
	await _set_physical_key(key, true)
	await process_frame
	await physics_frame
	await _release_physical_key(key)


func _set_physical_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func _release_physical_key(key: Key) -> void:
	await _set_physical_key(key, false)


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

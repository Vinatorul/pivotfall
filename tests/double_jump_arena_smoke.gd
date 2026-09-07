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

const LEVEL_ID := "arena_13_data"
const LEVEL_TITLE := (
	"GRAYBOX  /  DATA ARENA 13  /  ДВОЙНОЙ ПРЫЖОК"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_double_jump_arena_solution()
	await _release_physical_key(KEY_D)
	await _cleanup_current_scene()

	if failures.is_empty():
		print("DOUBLE_JUMP_ARENA_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_double_jump_arena_solution() -> void:
	var catalog_entry := _catalog_entry(LEVEL_ID)
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(LEVEL_ID)
	_expect(
		catalog_entry.get("path") == "res://levels/arena_13.json"
		and catalog_entry.get("title")
		== "Arena 06 / Двойной прыжок"
		and bool(loaded.get("ok", false))
		and loaded.get("warnings", []).is_empty(),
		"Arena 13 is missing from the campaign catalog or failed validation: %s / %s"
		% [loaded.get("errors", []), loaded.get("warnings", [])]
	)
	if not bool(loaded.get("ok", false)):
		return

	var data := loaded.get("data", {}) as Dictionary
	var left_floor := _object_by_id(data, "left_floor")
	var upper_platform := _object_by_id(data, "upper_platform")
	var player_spawn := _object_by_id(data, "player_start")
	var pickup_data := _object_by_id(data, "double_jump_1")
	var shooter_data := _object_by_id(data, "shooter_1")
	_expect(
		data.get("level_id") == LEVEL_ID
		and data.get("title") == LEVEL_TITLE
		and data.get("objects", []).size() == 5
		and left_floor.get("rect") == [32, 496, 328, 44]
		and not bool(left_floor.get("one_way", true))
		and upper_platform.get("rect") == [400, 300, 400, 20]
		and bool(upper_platform.get("one_way", false))
		and player_spawn.get("position") == [120, 450]
		and pickup_data.get("type") == "double_jump_pickup"
		and pickup_data.get("position") == [240, 450]
		and shooter_data.get("position") == [740, 260]
		and shooter_data.get("behavior_preset") == "standard",
		"Arena 13 metadata or mandatory double-jump route drifted."
	)

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded.get("ok", false)),
		"Arena 13 could not be encoded for runtime: %s"
		% [encoded.get("errors", [])]
	)
	if not bool(encoded.get("ok", false)):
		return

	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.configure_embedded_snapshot(str(encoded.get("text", "")))
	arena.clear_restart_delay = 10.0
	root.add_child(arena)
	current_scene = arena
	await process_frame

	var player := arena.get_level_object("player_start") as Player
	var pickup := (
		arena.get_level_object("double_jump_1") as DoubleJumpPickup
	)
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	_expect(
		arena.level_loaded
		and arena.load_errors.is_empty()
		and arena.level_objects.size() == 5
		and arena.enemies_remaining == 1
		and is_instance_valid(player)
		and is_instance_valid(pickup)
		and is_instance_valid(shooter),
		"Arena 13 runtime did not build all five required objects."
	)
	if (
		not is_instance_valid(player)
		or not is_instance_valid(pickup)
		or not is_instance_valid(shooter)
	):
		return

	var projectile_shots: Array[Dictionary] = []
	var projectile_impacts: Array[Dictionary] = []
	shooter.shot_fired.connect(
		func(projectile: ShooterProjectile) -> void:
			projectile_shots.append(
				{
					"direction": projectile.direction,
					"inside_arena": arena.is_ancestor_of(projectile),
				}
			)
			projectile.impacted.connect(
				func(collider: CollisionObject2D) -> void:
					projectile_impacts.append(
						{
							"id": str(
								collider.get_meta(
									"level_object_id",
									""
								)
							),
						}
					)
			)
	)

	var settled := await _wait_until_grounded(player)
	_expect(settled, "Arena 13 player did not settle on the start floor.")
	if not settled:
		return

	var baseline_start_y := player.global_position.y
	var baseline_min_y := baseline_start_y
	player.jump_requested = true
	await physics_frame
	for frame in range(120):
		await physics_frame
		baseline_min_y = minf(baseline_min_y, player.global_position.y)
		if frame > 2 and player.is_on_floor():
			break
	_expect(
		player.is_on_floor()
		and not player.has_double_jump
		and baseline_start_y - baseline_min_y < 130.0
		and baseline_min_y > 330.0,
		"A normal jump unexpectedly reached the Arena 13 upper route: start=%s apex=%s."
		% [baseline_start_y, baseline_min_y]
	)

	var pickup_ref: WeakRef = weakref(pickup)
	var reached_pickup := await _walk_right_until(player, 270.0, 120)
	await process_frame
	_expect(
		reached_pickup
		and player.has_double_jump
		and player.air_jump_available
		and not is_instance_valid(pickup_ref.get_ref()),
		"Walking through Arena 13 pickup did not unlock and consume it."
	)
	if not player.has_double_jump:
		return

	var reached_takeoff := await _walk_right_until(player, 315.0, 90)
	_expect(
		reached_takeoff and player.is_on_floor(),
		"Player did not reach the Arena 13 takeoff edge."
	)
	if not reached_takeoff or not player.is_on_floor():
		return

	# Start the exposed traversal immediately after a real authored shot has
	# struck the upper platform. This verifies the cover geometry and gives the
	# player a deterministic cooldown window without muting the shooter.
	var cover_impacts_before := _count_impacts_with_id(
		projectile_impacts,
		"upper_platform"
	)
	var saw_cover_shot := false
	for _frame in range(180):
		await physics_frame
		if not is_instance_valid(player) or player.is_defeated:
			break
		if (
			_count_impacts_with_id(
				projectile_impacts,
				"upper_platform"
			) > cover_impacts_before
		):
			saw_cover_shot = true
			break
	_expect(
		saw_cover_shot
		and not projectile_shots.is_empty()
		and bool(projectile_shots.back().get("inside_arena", false))
		and not player.is_defeated,
		(
			"Arena 13 shooter did not fire a real arena-owned projectile "
			+ "into the authored upper-platform cover: shots=%s impacts=%s."
		)
		% [projectile_shots, projectile_impacts]
	)
	if not saw_cover_shot or player.is_defeated:
		return

	await _set_physical_key(KEY_D, true)
	player.jump_requested = true
	await physics_frame
	var first_jump_apex_y := player.global_position.y
	var used_air_jump := false
	var landed_upper_route := false
	var released_right := false
	for _frame in range(180):
		await physics_frame
		if not used_air_jump:
			first_jump_apex_y = minf(
				first_jump_apex_y,
				player.global_position.y
			)
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
		if not released_right and player.global_position.x >= 560.0:
			await _release_physical_key(KEY_D)
			released_right = true
		if (
			used_air_jump
			and player.is_on_floor()
			and player.global_position.y < 330.0
		):
			landed_upper_route = true
			break
		if player.is_defeated:
			break
	if not released_right:
		await _release_physical_key(KEY_D)
	_expect(
		used_air_jump
		and landed_upper_route
		and not player.is_defeated
		and first_jump_apex_y > 330.0,
		(
			"Arena 13 double-jump route was not completed: "
			+ "air_jump=%s landed_upper=%s position=%s first_apex=%s."
		)
		% [
			used_air_jump,
			landed_upper_route,
			player.global_position,
			first_jump_apex_y,
		]
	)
	if not landed_upper_route:
		return

	var reached_enemy := await _walk_right_until(player, 690.0, 120)
	_expect(
		reached_enemy and not player.is_defeated,
		"Player did not reach the Arena 13 shooter after the double jump."
	)
	if not reached_enemy or player.is_defeated:
		return

	var hit_shooter := {"value": false}
	player.attack_landed.connect(
		func(target: Node2D, _position: Vector2, _impulse: Vector2) -> void:
			if target == shooter:
				hit_shooter["value"] = true
	)
	await _press_physical_key(KEY_X)
	for _frame in range(300):
		await physics_frame
		if arena.restart_scheduled:
			break
	await process_frame
	_expect(
		bool(hit_shooter["value"])
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR,
		(
			"Arena 13 shooter was not knocked from the upper route for "
			+ "CLEAR under live fire: shots=%s impacts=%s."
		)
		% [projectile_shots, projectile_impacts]
	)


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


func _count_impacts_with_id(
	impacts: Array[Dictionary],
	object_id: String
) -> int:
	var count := 0
	for impact: Dictionary in impacts:
		if impact.get("id", "") == object_id:
			count += 1
	return count


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


func _wait_until_grounded(player: Player, frames := 120) -> bool:
	for _frame in frames:
		if not is_instance_valid(player):
			return false
		if player.is_on_floor():
			return true
		await physics_frame
	return is_instance_valid(player) and player.is_on_floor()


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

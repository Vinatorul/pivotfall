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

const LEVEL_ID := "arena_16_data"
const OBJECTIVE := (
	"СТОЛКНИ ВРАГА НА ПЛИТУ  /  "
	+ "ПЕРЕЙДИ МОСТ  /  УБЕРИ ОПОРУ"
)

var failures: Array[String] = []
var arena: LevelRuntimeArena
var player: Player
var patrol: PatrolEnemy
var plate: PressurePlate
var bridge: TogglePlatform
var weight_floor: TogglePlatform
var release_hinge: Hinge
var patrol_ref: WeakRef
var patrol_instance_id := 0
var patrol_hit_count := 0
var hinge_hit_count := 0
var floor_off_count := 0
var enemy_death_zone_entries := 0
var plate_edges: Array[bool] = []
var bridge_states: Array[bool] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := _load_arena()
	if data.is_empty():
		_finish()
		return
	await _test_bypass_guards(data)
	arena = await _create_runtime(data)
	if not is_instance_valid(arena):
		await _cleanup_current_scene()
		_finish()
		return
	if not _bind_runtime_parts() or not _expect_runtime_contract():
		await _cleanup_current_scene()
		_finish()
		return
	_connect_observers()
	var settled := await _wait_for_grounded_start()
	_expect(settled, "Arena 16 actors did not settle on the upper runway.")
	if settled:
		await _exercise_solution()
	_expect_final_state()
	await _cleanup_current_scene()
	_finish()


func _load_arena() -> Dictionary:
	var catalog_entry := _catalog_entry(LEVEL_ID)
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(LEVEL_ID)
	_expect(
		catalog_entry.get("path") == "res://levels/arena_16.json"
		and catalog_entry.get("title") == "Arena 10 / Противовес"
		and bool(loaded.get("ok", false))
		and loaded.get("warnings", []).is_empty(),
		"Arena 16 catalog or schema validation failed: %s / %s"
		% [loaded.get("errors", []), loaded.get("warnings", [])]
	)
	if not bool(loaded.get("ok", false)):
		return {}
	var data := loaded.get("data", {}) as Dictionary
	_verify_authored_layout(data)
	_verify_authored_route(data)
	_verify_codec_round_trip(data)
	return data


func _verify_authored_layout(data: Dictionary) -> void:
	var runway := _object_by_id(data, "left_runway")
	var floor := _object_by_id(data, "weight_floor")
	var authored_plate := _object_by_id(data, "weight_plate")
	var landing := _object_by_id(data, "landing")
	var authored_bridge := _object_by_id(data, "crossing_bridge")
	var right := _object_by_id(data, "right_platform")
	_expect(
		data.get("level_id") == LEVEL_ID
		and data.get("objective") == OBJECTIVE
		and runway.get("rect") == [32, 416, 288, 20]
		and floor.get("rect") == [340, 496, 100, 20]
		and bool(floor.get("starts_active", false))
		and authored_plate.get("rect") == [340, 476, 100, 20]
		and authored_plate.get("target_id") == "crossing_bridge"
		and bool(authored_plate.get("active_while_pressed", false))
		and landing.get("rect") == [460, 416, 60, 20]
		and authored_bridge.get("rect") == [520, 416, 220, 20]
		and not bool(authored_bridge.get("starts_active", true))
		and right.get("rect") == [740, 416, 188, 20],
		"Arena 16 counterweight geometry drifted."
	)


func _verify_authored_route(data: Dictionary) -> void:
	var spawn := _object_by_id(data, "player_start")
	var enemy := _object_by_id(data, "patrol_weight")
	var hinge := _object_by_id(data, "release_hinge")
	_expect(
		data.get("objects", []).size() == 9
		and spawn.get("position") == [120, 370]
		and enemy.get("position") == [280, 370]
		and enemy.get("direction") == 1
		and enemy.get("speed") == 20
		and hinge.get("position") == [840, 388]
		and hinge.get("target_id") == "weight_floor",
		"Arena 16 actor route or release hinge drifted."
	)


func _verify_codec_round_trip(data: Dictionary) -> void:
	var encoded := LEVEL_DATA_CODEC.encode(data)
	var decoded := LEVEL_DATA_CODEC.decode_text(
		str(encoded.get("text", ""))
	)
	_expect(
		bool(encoded.get("ok", false))
		and bool(decoded.get("ok", false))
		and decoded.get("data", {}) == data,
		"Arena 16 failed its canonical import/export round trip."
	)


func _test_bypass_guards(data: Dictionary) -> void:
	await _test_direct_jump_guard(data)
	await _cleanup_current_scene()
	await _test_self_weight_guard(data)
	await _cleanup_current_scene()


func _test_direct_jump_guard(data: Dictionary) -> void:
	var guard_arena := await _create_runtime(data)
	if not is_instance_valid(guard_arena):
		return
	var guard_player := guard_arena.get_level_object("player_start") as Player
	var guard_patrol := guard_arena.get_level_object("patrol_weight") as PatrolEnemy
	var guard_bridge := guard_arena.get_level_object("crossing_bridge") as TogglePlatform
	var guard_hinge := guard_arena.get_level_object("release_hinge") as Hinge
	guard_patrol.patrol_speed = 0.0
	guard_player.global_position = Vector2(490, 390)
	guard_player.velocity = Vector2.ZERO
	await _wait_physics_frames(4)
	var max_x := await _attempt_right_jump(guard_player, 120)
	_expect(
		max_x < 740.0
		and not guard_bridge.is_active
		and guard_hinge.is_ready,
		"A normal jump bypassed the empty crossing or reached the hinge."
	)


func _test_self_weight_guard(data: Dictionary) -> void:
	var guard_arena := await _create_runtime(data)
	if not is_instance_valid(guard_arena):
		return
	var guard_player := guard_arena.get_level_object("player_start") as Player
	var guard_patrol := guard_arena.get_level_object("patrol_weight") as PatrolEnemy
	var guard_plate := guard_arena.get_level_object("weight_plate") as PressurePlate
	var guard_bridge := guard_arena.get_level_object("crossing_bridge") as TogglePlatform
	guard_patrol.patrol_speed = 0.0
	guard_player.global_position = Vector2(390, 450)
	guard_player.velocity = Vector2.ZERO
	var activated := await _wait_for_plate_state(guard_plate, guard_bridge, true)
	var escaped := await _escape_weight_pocket(guard_player)
	var max_x := await _attempt_right_jump(guard_player, 120) if escaped else 0.0
	_expect(
		activated
		and guard_plate.occupant_count() == 0
		and not guard_bridge.is_active
		and escaped
		and max_x < 740.0,
		"Player could not escape the pocket or bypassed it by self-weight."
	)


func _escape_weight_pocket(body: Player) -> bool:
	await _set_physical_key(KEY_D, true)
	await _press_physical_key(KEY_W)
	for _frame in range(90):
		await physics_frame
		if body.global_position.x >= 455.0 or body.is_defeated:
			break
	await _set_physical_key(KEY_D, false)
	for _frame in range(120):
		await physics_frame
		if (
			body.is_on_floor()
			and body.global_position.x >= 450.0
			and body.global_position.x <= 520.0
			and body.global_position.y < 410.0
		):
			return true
		if body.is_defeated:
			return false
	return false


func _attempt_right_jump(body: Player, frames: int) -> float:
	var max_x := body.global_position.x
	await _set_physical_key(KEY_D, true)
	await _press_physical_key(KEY_W)
	for _frame in range(frames):
		await physics_frame
		if not is_instance_valid(body):
			break
		max_x = maxf(max_x, body.global_position.x)
		if body.is_defeated:
			break
	await _set_physical_key(KEY_D, false)
	return max_x


func _create_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded := LEVEL_DATA_CODEC.encode(data)
	if not bool(encoded.get("ok", false)):
		_expect(false, "Arena 16 could not be encoded for runtime.")
		return null
	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded.get("text", "")))
	runtime.clear_restart_delay = 10.0
	root.add_child(runtime)
	current_scene = runtime
	await process_frame
	await physics_frame
	_expect(runtime.level_loaded, "Arena 16 runtime build failed.")
	if not runtime.level_loaded:
		return null
	return runtime


func _bind_runtime_parts() -> bool:
	player = arena.get_level_object("player_start") as Player
	patrol = arena.get_level_object("patrol_weight") as PatrolEnemy
	plate = arena.get_level_object("weight_plate") as PressurePlate
	bridge = arena.get_level_object("crossing_bridge") as TogglePlatform
	weight_floor = arena.get_level_object("weight_floor") as TogglePlatform
	release_hinge = arena.get_level_object("release_hinge") as Hinge
	return (
		is_instance_valid(player)
		and is_instance_valid(patrol)
		and is_instance_valid(plate)
		and is_instance_valid(bridge)
		and is_instance_valid(weight_floor)
		and is_instance_valid(release_hinge)
	)


func _expect_runtime_contract() -> bool:
	var valid := (
		plate.target == bridge
		and release_hinge.target == weight_floor
		and weight_floor.is_active
		and not bridge.is_active
		and not plate.is_pressed
		and plate.occupant_count() == 0
		and arena.enemies_remaining == 1
	)
	_expect(valid, "Arena 16 runtime links or initial states drifted.")
	if not valid:
		return false
	_expect_route_guards()
	return true


func _expect_route_guards() -> void:
	var full_jump_distance := (
		2.0 * absf(player.jump_velocity) / player.gravity * player.move_speed
	)
	var upper_gap := 460.0 - 320.0
	var empty_bridge_gap := 740.0 - 520.0
	var plate_to_bridge := 520.0 - 440.0
	var hinge_from_landing := 840.0 - 520.0
	_expect(
		upper_gap < full_jump_distance
		and empty_bridge_gap > full_jump_distance
		and plate_to_bridge / player.move_speed > bridge.transition_time
		and hinge_from_landing > full_jump_distance + 56.0,
		"Arena 16 movement guards no longer enforce the intended route."
	)


func _connect_observers() -> void:
	patrol_ref = weakref(patrol)
	patrol_instance_id = patrol.get_instance_id()
	player.attack_landed.connect(_on_attack_landed)
	plate.pressed_changed.connect(_on_plate_pressed_changed)
	bridge.toggled.connect(_on_bridge_toggled)
	weight_floor.toggled.connect(_on_weight_floor_toggled)
	arena.death_zone.body_entered.connect(_on_death_zone_body_entered)


func _wait_for_grounded_start() -> bool:
	for _frame in range(120):
		await physics_frame
		if (
			player.is_on_floor()
			and patrol.is_on_floor()
			and not plate.is_pressed
			and not bridge.is_active
		):
			return true
	return false


func _exercise_solution() -> void:
	var weighted := await _knock_patrol_into_pocket()
	_expect(weighted, "A real attack did not leave the patrol on the plate.")
	if not weighted or player.is_defeated:
		return
	var crossed := await _cross_to_right_platform()
	_expect(crossed, "Player did not fully cross the enemy-held bridge.")
	if not crossed or player.is_defeated:
		return
	var released := await _activate_release_hinge()
	_expect(released, "A real attack did not disable the weight floor.")
	if released:
		await _wait_for_counterweight_clear()


func _knock_patrol_into_pocket() -> bool:
	await _set_physical_key(KEY_D, true)
	for _frame in range(120):
		await physics_frame
		if player.is_defeated or patrol.global_position.x - player.global_position.x <= 68.0:
			break
	await _set_physical_key(KEY_D, false)
	if player.is_defeated:
		return false
	await _press_physical_key(KEY_X)
	for _frame in range(180):
		await physics_frame
		if _enemy_holds_active_bridge():
			return true
		if player.is_defeated or not is_instance_valid(patrol):
			return false
	return false


func _enemy_holds_active_bridge() -> bool:
	return (
		patrol_hit_count == 1
		and plate.is_pressed
		and plate.occupant_count() == 1
		and bridge.is_active
		and not bridge.is_transitioning
		and patrol.is_on_floor()
		and patrol.global_position.x >= 340.0
		and patrol.global_position.x <= 440.0
		and player.global_position.y < 440.0
	)


func _cross_to_right_platform() -> bool:
	await _set_physical_key(KEY_D, true)
	for _frame in range(90):
		await physics_frame
		if player.global_position.x >= 280.0 or player.is_defeated:
			break
	await _press_physical_key(KEY_W)
	var crossed := false
	for _frame in range(240):
		await physics_frame
		if player.global_position.x >= 770.0 and player.is_on_floor():
			crossed = true
			break
		if player.is_defeated or not bridge.is_active:
			break
	await _set_physical_key(KEY_D, false)
	return crossed and plate.occupant_count() == 1


func _activate_release_hinge() -> bool:
	if player.global_position.x < 775.0:
		await _set_physical_key(KEY_D, true)
		for _frame in range(45):
			await physics_frame
			if player.global_position.x >= 775.0:
				break
		await _set_physical_key(KEY_D, false)
	await _press_physical_key(KEY_X)
	for _frame in range(120):
		await physics_frame
		if not weight_floor.is_active and not weight_floor.is_transitioning:
			return hinge_hit_count == 1 and floor_off_count == 1
	return false


func _wait_for_counterweight_clear() -> void:
	for _frame in range(240):
		await physics_frame
		if (
			arena.pending_outcome == Arena.Outcome.CLEAR
			and not bridge.is_active
			and not bridge.is_transitioning
		):
			return


func _expect_final_state() -> void:
	_expect(
		patrol_hit_count == 1
		and hinge_hit_count == 1
		and floor_off_count == 1
		and enemy_death_zone_entries == 1
		and plate_edges == [true, false]
		and bridge_states == [true, false],
		"Arena 16 did not preserve its single-edge mechanism sequence."
	)
	_expect_final_runtime_state()


func _expect_final_runtime_state() -> void:
	_expect(
		not plate.is_pressed
		and plate.occupant_count() == 0
		and not bridge.is_active
		and not weight_floor.is_active
		and not is_instance_valid(patrol_ref.get_ref())
		and arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and arena.outcome_generation == 1
		and arena.status_label.text == arena.clear_message
		and is_instance_valid(player)
		and not player.is_defeated
		and player.global_position.x >= 740.0,
		"Arena 16 did not end with one CLEAR behind a living player."
	)


func _on_attack_landed(
	target: Node2D,
	_impact_position: Vector2,
	_impulse: Vector2
) -> void:
	if target.get_instance_id() == patrol_instance_id:
		patrol_hit_count += 1
	elif target == release_hinge:
		hinge_hit_count += 1


func _on_plate_pressed_changed(pressed: bool) -> void:
	plate_edges.append(pressed)


func _on_bridge_toggled(active: bool) -> void:
	bridge_states.append(active)


func _on_weight_floor_toggled(active: bool) -> void:
	if not active:
		floor_off_count += 1


func _on_death_zone_body_entered(body: Node2D) -> void:
	if body.get_instance_id() == patrol_instance_id:
		enemy_death_zone_entries += 1


func _wait_for_plate_state(
	guard_plate: PressurePlate,
	guard_bridge: TogglePlatform,
	desired: bool
) -> bool:
	for _frame in range(120):
		await physics_frame
		if (
			guard_plate.is_pressed == desired
			and guard_bridge.is_active == desired
			and not guard_bridge.is_transitioning
		):
			return true
	return false


func _wait_physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _press_physical_key(key: Key) -> void:
	await _set_physical_key(key, true)
	await physics_frame
	await _set_physical_key(key, false)


func _set_physical_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func _catalog_entry(level_id: String) -> Dictionary:
	for entry: Dictionary in LEVEL_STORAGE.list_builtin_levels():
		if entry.get("id") == level_id:
			return entry
	return {}


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for raw_object: Variant in data.get("objects", []):
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object := raw_object as Dictionary
		if object.get("id") == object_id:
			return object
	return {}


func _cleanup_current_scene() -> void:
	await _set_physical_key(KEY_D, false)
	await _set_physical_key(KEY_W, false)
	await _set_physical_key(KEY_X, false)
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("COUNTERWEIGHT_ARENA_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

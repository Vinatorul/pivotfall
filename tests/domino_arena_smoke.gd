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

const LEVEL_ID := "arena_15_data"
const EVENT_ORDER := [
	"hinge_activated",
	"patrol_impacted",
	"patrol_spikes",
	"shooter_pit",
]

var failures: Array[String] = []
var events: Array[String] = []
var shot_count := 0
var first_projectile_id := 0
var domino_projectile_id := 0
var domino_shot_count := 0
var first_impact_id := ""
var domino_impact_id := ""
var domino_impact_position := Vector2.ZERO
var player_impact_position := Vector2.ZERO
var accepting_domino_shot := false
var domino_passed_hinge := false
var platform_disabled := false
var hinge_activation_seen := false
var patrol_gap_turn_seen := false
var patrol_impact_velocity := Vector2.ZERO
var shooter_pit_velocity := Vector2.ZERO
var dodge_clearance := 0.0
var patrol_ref: WeakRef
var shooter_ref: WeakRef
var arena: LevelRuntimeArena
var player: Player
var patrol: PatrolEnemy
var shooter: ShooterEnemy
var hinge: Hinge
var shooter_platform: TogglePlatform
var spikes: SpikeTrap


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data := _load_arena()
	if data.is_empty():
		_finish()
		return
	arena = await _create_runtime(data)
	if not is_instance_valid(arena):
		_finish()
		return
	_bind_runtime_parts()
	if not _expect_runtime_contract():
		await _cleanup_current_scene()
		_finish()
		return
	_connect_observers()
	await _exercise_solution()
	_expect_projectile_chain()
	_expect_environmental_eliminations()
	_expect_single_clear()
	await _cleanup_current_scene()
	_finish()


func _load_arena() -> Dictionary:
	var catalog_entry := _catalog_entry(LEVEL_ID)
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(LEVEL_ID)
	_expect(
		catalog_entry.get("path") == "res://levels/arena_15.json"
		and catalog_entry.get("title") == "Arena 15 / Домино"
		and bool(loaded.get("ok", false))
		and loaded.get("warnings", []).is_empty(),
		"Arena 15 catalog entry or schema validation failed: %s / %s"
		% [loaded.get("errors", []), loaded.get("warnings", [])]
	)
	if not bool(loaded.get("ok", false)):
		return {}
	var data := loaded.get("data", {}) as Dictionary
	_verify_authored_lane(data)
	_verify_authored_barriers(data)
	_verify_authored_actors(data)
	_verify_codec_round_trip(data)
	return data


func _verify_authored_lane(data: Dictionary) -> void:
	var right_floor := _object_by_id(data, "right_floor")
	var bait_platform := _object_by_id(data, "bait_platform")
	var dodge_platform := _object_by_id(data, "dodge_platform")
	var patrol_floor := _object_by_id(data, "patrol_floor")
	var spike_base := _object_by_id(data, "spike_base")
	var platform := _object_by_id(data, "shooter_platform")
	var spike_data := _object_by_id(data, "patrol_spikes")
	_expect(
		data.get("level_id") == LEVEL_ID
		and data.get("objects", []).size() == 14
		and "ЗАМАНИ ВЫСТРЕЛ" in str(data.get("objective", ""))
		and "ОДНА ПУЛЯ — ДВЕ ЦЕЛИ" in str(data.get("objective", ""))
		and right_floor.get("rect") == [360, 496, 180, 44]
		and bait_platform.get("rect") == [540, 410, 80, 20]
		and bool(bait_platform.get("one_way", false))
		and dodge_platform.get("rect") == [540, 330, 80, 20]
		and bool(dodge_platform.get("one_way", false))
		and patrol_floor.get("rect") == [660, 458, 100, 20]
		and spike_base.get("rect") == [780, 478, 148, 18]
		and platform.get("rect") == [60, 260, 58, 20]
		and bool(platform.get("starts_active", false))
		and spike_data.get("rect") == [780, 458, 148, 20],
		"Arena 15 authored domino lane drifted."
	)


func _verify_authored_barriers(data: Dictionary) -> void:
	var blocker := _object_by_id(data, "start_sight_blocker")
	var upper_wall := _object_by_id(data, "lane_wall_upper")
	var lower_wall := _object_by_id(data, "lane_wall_lower")
	_expect(
		blocker.get("rect") == [320, 340, 20, 40]
		and upper_wall.get("rect") == [620, 0, 20, 392]
		and lower_wall.get("rect") == [620, 428, 20, 112],
		"Arena 15 cover or projectile-only lane drifted."
	)


func _verify_authored_actors(data: Dictionary) -> void:
	var spawn := _object_by_id(data, "player_start")
	var hinge_data := _object_by_id(data, "domino_hinge")
	var patrol_data := _object_by_id(data, "patrol_target")
	var shooter_data := _object_by_id(data, "shooter_source")
	_expect(
		spawn.get("position") == [500, 450]
		and hinge_data.get("position") == [260, 289]
		and hinge_data.get("target_id") == "shooter_platform"
		and patrol_data.get("position") == [690, 440]
		and patrol_data.get("direction") == 1
		and patrol_data.get("speed") == 20.0
		and shooter_data.get("position") == [100, 210]
		and shooter_data.get("behavior_preset") == "exam",
		"Arena 15 actor positions or hinge link drifted."
	)


func _verify_codec_round_trip(data: Dictionary) -> void:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		str(encoded.get("text", ""))
	)
	_expect(
		bool(encoded.get("ok", false))
		and bool(decoded.get("ok", false))
		and decoded.get("data", {}) == data,
		"Arena 15 failed its canonical import/export round trip."
	)


func _create_runtime(data: Dictionary) -> LevelRuntimeArena:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	if not bool(encoded.get("ok", false)):
		_expect(false, "Arena 15 could not be encoded for runtime.")
		return null
	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded.get("text", "")))
	runtime.clear_restart_delay = 10.0
	root.add_child(runtime)
	current_scene = runtime
	await process_frame
	return runtime


func _bind_runtime_parts() -> void:
	player = arena.get_level_object("player_start") as Player
	patrol = arena.get_level_object("patrol_target") as PatrolEnemy
	shooter = arena.get_level_object("shooter_source") as ShooterEnemy
	hinge = arena.get_level_object("domino_hinge") as Hinge
	shooter_platform = (
		arena.get_level_object("shooter_platform") as TogglePlatform
	)
	spikes = arena.get_level_object("patrol_spikes") as SpikeTrap
	patrol_ref = weakref(patrol)
	shooter_ref = weakref(shooter)


func _expect_runtime_contract() -> bool:
	var valid := (
		arena.level_loaded
		and arena.load_errors.is_empty()
		and arena.level_objects.size() == 14
		and arena.enemies_remaining == 2
		and is_instance_valid(player)
		and is_instance_valid(patrol)
		and is_instance_valid(shooter)
		and is_instance_valid(hinge)
		and is_instance_valid(shooter_platform)
		and is_instance_valid(spikes)
	)
	_expect(valid, "Arena 15 runtime did not build all domino objects.")
	if not valid:
		return false
	_expect(
		hinge.target == shooter_platform and shooter_platform.is_active,
		"Arena 15 hinge did not target the active shooter platform."
	)
	return true


func _connect_observers() -> void:
	shooter.shot_fired.connect(_on_shot_fired)
	spikes.body_entered.connect(_on_spike_body_entered)
	arena.death_zone.body_entered.connect(_on_death_zone_body_entered)
	shooter_platform.toggle_completed.connect(_on_platform_toggled)


func _on_shot_fired(projectile: ShooterProjectile) -> void:
	shot_count += 1
	projectile.impacted.connect(
		_on_projectile_impacted.bind(projectile)
	)
	if shot_count == 1:
		first_projectile_id = projectile.get_instance_id()
	if not accepting_domino_shot:
		return
	accepting_domino_shot = false
	domino_shot_count += 1
	domino_projectile_id = projectile.get_instance_id()
	dodge_clearance = absf(
		(player.global_position - projectile.global_position).cross(
			projectile.direction
		)
	)


func _on_projectile_impacted(
	collider: CollisionObject2D,
	projectile: ShooterProjectile
) -> void:
	var object_id := str(collider.get_meta("level_object_id", ""))
	if projectile.get_instance_id() == first_projectile_id:
		first_impact_id = object_id
		return
	if projectile.get_instance_id() != domino_projectile_id:
		return
	domino_impact_id = object_id
	domino_impact_position = projectile.global_position
	player_impact_position = player.global_position
	domino_passed_hinge = projectile.collision_exceptions.has(
		hinge.get_rid()
	)
	if collider != patrol:
		return
	patrol_impact_velocity = patrol.velocity
	_record_event("patrol_impacted")


func _on_spike_body_entered(body: Node2D) -> void:
	if body == patrol:
		_record_event("patrol_spikes")


func _on_death_zone_body_entered(body: Node2D) -> void:
	if body != shooter:
		return
	shooter_pit_velocity = shooter.velocity
	_record_event("shooter_pit")


func _on_platform_toggled(is_active: bool) -> void:
	if not is_active:
		platform_disabled = true


func _exercise_solution() -> void:
	var settled := await _wait_for_grounded_start()
	_expect(settled, "Arena 15 actors did not settle on authored supports.")
	if not settled:
		return
	_expect_player_access_barriers()
	await _expect_safe_start_shot()
	if player.is_defeated:
		return
	await _jump_to_bait()
	if player.is_defeated:
		return
	var locked := await _wait_for_aim_lock()
	_expect(locked, "Arena 15 shooter did not lock onto the bait position.")
	if not locked:
		return
	_expect_locked_domino_line()
	accepting_domino_shot = true
	await _dodge_from_locked_line()
	await _wait_for_domino()


func _wait_for_grounded_start() -> bool:
	for _frame in range(90):
		await physics_frame
		if (
			player.is_on_floor()
			and patrol.is_on_floor()
			and shooter.is_on_floor()
		):
			return true
	return false


func _expect_player_access_barriers() -> void:
	var jump_height := player.jump_velocity * player.jump_velocity / (
		2.0 * player.gravity
	)
	var full_jump_distance := (
		2.0 * absf(player.jump_velocity) / player.gravity * player.move_speed
	)
	var floor_attack_top := 476.0 - jump_height - 18.0
	var hinge_bottom := hinge.global_position.y + 18.0
	var closest_bait_center := 554.0
	var closest_attack_edge := closest_bait_center - full_jump_distance - 56.0
	var hinge_right := hinge.global_position.x + 18.0
	var bait_attack_right := 606.0 + 56.0
	var patrol_left_limit := 660.0 + 28.0 - 15.0
	_expect(
		jump_height < 156.0
		and floor_attack_top > hinge_bottom
		and closest_bait_center - 330.0 > full_jump_distance
		and closest_attack_edge > hinge_right
		and 428.0 - 392.0 < 40.0
		and bait_attack_right < patrol_left_limit,
		"Player movement or attack can bypass the inaccessible hinge lane."
	)


func _expect_safe_start_shot() -> void:
	for _frame in range(180):
		await physics_frame
		if not first_impact_id.is_empty() or player.is_defeated:
			break
	_expect(
		shot_count == 1
		and first_impact_id == "start_sight_blocker"
		and hinge.is_ready
		and shooter_platform.is_active
		and arena.enemies_remaining == 2
		and not player.is_defeated,
		"Arena 15 start shot bypassed cover or solved the domino: shots=%d impact=%s."
		% [shot_count, first_impact_id]
	)


func _jump_to_bait() -> void:
	await _set_physical_key(KEY_D, true)
	await _press_physical_key(KEY_W)
	for _frame in range(120):
		await physics_frame
		if player.global_position.x >= 570.0 or player.is_defeated:
			break
	await _set_physical_key(KEY_D, false)
	var grounded := await _wait_until_grounded(player, 120)
	_expect(
		grounded
		and player.global_position.x >= 550.0
		and player.global_position.x <= 606.0
		and player.global_position.y < 410.0
		and not player.is_defeated,
		"Player did not reach the generous Arena 15 bait platform: %s."
		% player.global_position
	)


func _wait_for_aim_lock() -> bool:
	for _frame in range(240):
		await physics_frame
		if player.is_defeated:
			return false
		if patrol.patrol_direction < 0.0:
			patrol_gap_turn_seen = true
		if shooter.aim_is_locked:
			return true
	return false


func _expect_locked_domino_line() -> void:
	var origin := shooter.muzzle.global_position
	var direction := shooter.aim_direction
	var hinge_progress := (hinge.global_position - origin).dot(direction)
	var player_progress := (player.global_position - origin).dot(direction)
	var patrol_progress := (patrol.global_position - origin).dot(direction)
	var hinge_distance := _distance_to_ray(
		hinge.global_position,
		origin,
		direction
	)
	var patrol_distance := _distance_to_ray(
		patrol.global_position,
		origin,
		direction
	)
	var player_distance := _distance_to_ray(player.global_position, origin, direction)
	_expect(
		direction.x > 0.85
		and hinge_progress < player_progress
		and player_progress < patrol_progress
		and player_distance <= 1.0
		and hinge_distance <= 10.0
		and patrol_distance <= 14.0,
		"Locked shot missed the domino lane: hinge=%s patrol=%s direction=%s."
		% [hinge_distance, patrol_distance, direction]
	)


func _dodge_from_locked_line() -> void:
	await _press_physical_key(KEY_W)
	var landed := await _wait_until_grounded(player, 120)
	_expect(
		landed
		and player.global_position.x >= 550.0
		and player.global_position.x <= 606.0
		and player.global_position.y < 350.0,
		"Player did not land on the generous dodge platform: %s."
		% player.global_position
	)


func _wait_for_domino() -> void:
	for _frame in range(300):
		await physics_frame
		if not hinge_activation_seen and not hinge.is_ready:
			hinge_activation_seen = true
			_record_event("hinge_activated")
		await process_frame
		if (
			arena.pending_outcome == Arena.Outcome.CLEAR
			and events.size() >= EVENT_ORDER.size()
		):
			return
	_expect(false, "Arena 15 domino chain timed out: %s." % [events])


func _expect_projectile_chain() -> void:
	var first_events := events.slice(0, mini(events.size(), 2))
	_expect(
		domino_shot_count == 1
		and shot_count == 2
		and patrol_gap_turn_seen
		and domino_passed_hinge
		and first_events == EVENT_ORDER.slice(0, 2)
		and patrol_impact_velocity.x > 400.0,
		"One projectile did not activate hinge then impact patrol: events=%s shots=%d impact=%s at=%s player=%s velocity=%s."
		% [events, shot_count, domino_impact_id, domino_impact_position, player_impact_position, patrol_impact_velocity]
	)


func _expect_environmental_eliminations() -> void:
	_expect(
		events == EVENT_ORDER
		and platform_disabled
		and not shooter_platform.is_active
		and shooter_pit_velocity.y > 0.0
		and not is_instance_valid(patrol_ref.get_ref())
		and not is_instance_valid(shooter_ref.get_ref()),
		"Enemies did not die from spikes then pit in order: %s."
		% [events]
	)


func _expect_single_clear() -> void:
	var hazard := arena.hazard_feedback as ArenaHazardFeedback
	var impact := arena.impact_feedback as ArenaImpactFeedback
	_expect(
		arena.enemies_remaining == 0
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and arena.outcome_generation == 1
		and hazard.elimination_count == 2
		and hazard.clear_count == 1
		and impact.elimination_count == 2
		and impact.clear_count == 1
		and dodge_clearance >= 40.0
		and not player.is_defeated
		and player.is_clear_celebrating,
		"Arena 15 did not leave one CLEAR and a living dodger: clearance=%s."
		% dodge_clearance
	)


func _distance_to_ray(
	point: Vector2,
	origin: Vector2,
	direction: Vector2
) -> float:
	return absf((point - origin).cross(direction.normalized()))


func _record_event(event_name: String) -> void:
	if not events.has(event_name):
		events.append(event_name)


func _wait_until_grounded(body: CharacterBody2D, frames: int) -> bool:
	for _frame in range(frames):
		await physics_frame
		if body.is_on_floor():
			return true
	return false


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
	for object: Dictionary in data.get("objects", []):
		if object.get("id") == object_id:
			return object
	return {}


func _cleanup_current_scene() -> void:
	await _set_physical_key(KEY_D, false)
	await _set_physical_key(KEY_W, false)
	var scene := current_scene
	current_scene = null
	if not is_instance_valid(scene):
		return
	scene.queue_free()
	await scene.tree_exited


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("DOMINO_ARENA_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

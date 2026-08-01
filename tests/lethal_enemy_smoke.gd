extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_SCENE := preload("res://scenes/patrol_enemy.tscn")
const SHOVE_SCENE := preload("res://scenes/shove_enemy.tscn")
const SHOOTER_SCENE := preload("res://scenes/shooter_enemy.tscn")
const PROJECTILE_SCENE := preload(
	"res://scenes/shooter_projectile.tscn"
)
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

const ENEMY_FIXTURES: Array[Dictionary] = [
	{
		"label": "patrol",
		"scene": PATROL_SCENE,
		"size": Vector2(30.0, 36.0),
	},
	{
		"label": "shove",
		"scene": SHOVE_SCENE,
		"size": Vector2(32.0, 38.0),
	},
	{
		"label": "shooter",
		"scene": SHOOTER_SCENE,
		"size": Vector2(34.0, 38.0),
	},
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_enemy_contact_hazards()
	await _test_shove_lunge_is_lethal_without_impulse()
	await _test_real_projectile_is_lethal_without_impulse()
	await _test_arena_combat_outcome_is_idempotent()

	if failures.is_empty():
		print("LETHAL_ENEMY_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_enemy_contact_hazards() -> void:
	for fixture: Dictionary in ENEMY_FIXTURES:
		var holder := Node2D.new()
		var player := PLAYER_SCENE.instantiate() as Player
		var enemy := (
			(fixture["scene"] as PackedScene).instantiate()
			as PatrolEnemy
		)
		var causes: Array[int] = []
		player.defeated.connect(
			func(_player: Node2D, cause: int) -> void:
				causes.append(cause)
		)
		player.position = Vector2(240.0, 220.0)
		enemy.position = player.position
		holder.add_child(player)
		holder.add_child(enemy)
		root.add_child(holder)
		player.set_physics_process(false)
		enemy.set_physics_process(false)
		var sentinel_velocity := Vector2(13.0, -7.0)
		player.velocity = sentinel_velocity

		for _frame in range(2):
			await physics_frame

		var contact_hazard := enemy.get_node(
			"ContactHazard"
		) as Area2D
		var body_shape := (
			(enemy.get_node("CollisionShape2D") as CollisionShape2D).shape
			as RectangleShape2D
		)
		var contact_shape := (
			(
				contact_hazard.get_node("CollisionShape2D")
				as CollisionShape2D
			).shape
			as RectangleShape2D
		)
		var label := str(fixture["label"])
		_expect(
			player.is_defeated
			and causes == [Player.DefeatCause.COMBAT]
			and player.velocity.is_equal_approx(sentinel_velocity)
			and is_zero_approx(player.knockback_time_remaining),
			"%s contact did not defeat the player exactly once." % label
		)
		_expect(
			contact_hazard.collision_layer == 0
			and contact_hazard.collision_mask == 2
			and contact_hazard.monitoring
			and not contact_hazard.monitorable
			and enemy.collision_layer == 4
			and enemy.collision_mask == 1
			and body_shape.size.is_equal_approx(fixture["size"])
			and contact_shape.size.is_equal_approx(body_shape.size),
			"%s contact hazard changed established collision geometry." % label
		)

		contact_hazard.body_entered.emit(player)
		_expect(
			causes.size() == 1,
			"%s contact emitted a duplicate defeat." % label
		)
		holder.queue_free()
		await process_frame


func _test_shove_lunge_is_lethal_without_impulse() -> void:
	var holder := Node2D.new()
	var player := PLAYER_SCENE.instantiate() as Player
	var enemy := SHOVE_SCENE.instantiate() as ShoveEnemy
	var causes: Array[int] = []
	player.defeated.connect(
		func(_player: Node2D, cause: int) -> void:
			causes.append(cause)
	)
	player.position = Vector2(180.0, 220.0)
	enemy.position = Vector2(520.0, 220.0)
	holder.add_child(player)
	holder.add_child(enemy)
	root.add_child(holder)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	await process_frame

	var sentinel_velocity := Vector2(37.0, -19.0)
	player.velocity = sentinel_velocity
	enemy.state = ShoveEnemy.State.LUNGE
	enemy.lunge_direction = -1.0
	enemy.call("_try_apply_shove", player)
	enemy.call("_try_apply_shove", player)
	_expect(
		player.is_defeated
		and causes == [Player.DefeatCause.COMBAT]
		and player.velocity.is_equal_approx(sentinel_velocity)
		and is_zero_approx(player.knockback_time_remaining),
		"Shove lunge did not produce one lethal hit without impulse."
	)

	holder.queue_free()
	await process_frame


func _test_real_projectile_is_lethal_without_impulse() -> void:
	var holder := Node2D.new()
	var player := PLAYER_SCENE.instantiate() as Player
	var shooter := SHOOTER_SCENE.instantiate() as ShooterEnemy
	var causes: Array[int] = []
	var impacts: Array[CollisionObject2D] = []
	player.defeated.connect(
		func(_player: Node2D, cause: int) -> void:
			causes.append(cause)
	)
	player.position = Vector2(320.0, 220.0)
	shooter.position = Vector2(100.0, 220.0)
	holder.add_child(player)
	holder.add_child(shooter)
	root.add_child(holder)
	player.set_physics_process(false)
	shooter.set_physics_process(false)
	await physics_frame

	var projectile := (
		PROJECTILE_SCENE.instantiate() as ShooterProjectile
	)
	projectile.impacted.connect(
		func(collider: CollisionObject2D) -> void:
			impacts.append(collider)
	)
	holder.add_child(projectile)
	var projectile_ref: WeakRef = weakref(projectile)
	var sentinel_velocity := Vector2(-23.0, 11.0)
	player.velocity = sentinel_velocity
	var defaults_are_intact := (
		is_equal_approx(projectile.speed, 760.0)
		and is_equal_approx(projectile.maximum_distance, 1000.0)
		and is_equal_approx(projectile.horizontal_impulse, 520.0)
		and is_equal_approx(projectile.vertical_impulse, -140.0)
		and is_equal_approx(projectile.collision_radius, 5.0)
		and projectile.collision_mask == 15
	)
	projectile.launch(
		Vector2(150.0, 220.0),
		Vector2.RIGHT,
		shooter
	)

	for _frame in range(60):
		await physics_frame
		if not impacts.is_empty():
			break
	await process_frame

	_expect(
		defaults_are_intact
		and impacts.size() == 1
		and impacts[0] == player
		and causes == [Player.DefeatCause.COMBAT]
		and player.is_defeated
		and player.velocity.is_equal_approx(sentinel_velocity)
		and is_zero_approx(player.knockback_time_remaining)
		and projectile_ref.get_ref() == null,
		(
			"A real shooter projectile did not kill once without impulse: "
			+ "defaults=%s impacts=%s causes=%s defeated=%s velocity=%s "
			+ "expected_velocity=%s lock=%s projectile_alive=%s"
		)
		% [
			defaults_are_intact,
			str(impacts),
			str(causes),
			player.is_defeated,
			player.velocity,
			sentinel_velocity,
			player.knockback_time_remaining,
			projectile_ref.get_ref() != null,
		]
	)

	holder.queue_free()
	await process_frame


func _test_arena_combat_outcome_is_idempotent() -> void:
	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	var hazard := arena.get_node(
		"HazardFeedback"
	) as ArenaHazardFeedback
	hazard.set_process(false)
	root.add_child(arena)
	await process_frame

	_expect(arena.level_loaded, "Combat outcome fixture did not load.")
	if not arena.level_loaded:
		arena.queue_free()
		await process_frame
		return

	var player := arena.get_level_object("player_start") as Player
	player.set_physics_process(false)
	var pit_band := arena.get_node("PitBand") as Polygon2D
	var pit_edge := arena.get_node("PitEdge") as Line2D
	var band_color := pit_band.color
	var edge_color := pit_edge.default_color
	var edge_width := pit_edge.width
	var generation_before := arena.outcome_generation

	var accepted_first := player.receive_lethal_hit(
		Player.DefeatCause.COMBAT
	)
	var accepted_second := player.receive_lethal_hit(
		Player.DefeatCause.COMBAT
	)
	arena.death_zone.body_entered.emit(player)
	arena.call(
		"_on_player_defeated",
		player,
		Player.DefeatCause.FALL
	)

	_expect(
		accepted_first
		and not accepted_second
		and player.is_defeated
		and player.is_falling_out
		and is_equal_approx(
			player.fall_out_duration,
			arena.fall_restart_delay
		)
		and is_equal_approx(arena.fall_restart_delay, 0.45)
		and arena.restart_scheduled
		and not arena.advance_after_delay
		and arena.pending_outcome == Arena.Outcome.FALL
		and arena.outcome_generation == generation_before + 1
		and arena.status_label.text
		== "ПОРАЖЕНИЕ  /  ПЕРЕЗАПУСК...",
		"Combat defeat did not schedule one idempotent FALL outcome."
	)
	_expect(
		not hazard.is_alerting
		and pit_band.color.is_equal_approx(band_color)
		and pit_edge.default_color.is_equal_approx(edge_color)
		and is_equal_approx(pit_edge.width, edge_width),
		"Combat defeat incorrectly played the pit-only warning."
	)

	arena.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

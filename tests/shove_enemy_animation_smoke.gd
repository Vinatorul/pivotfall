extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SHOVE_ENEMY_SCENE := preload("res://scenes/shove_enemy.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shove_pose_lifecycle()

	if failures.is_empty():
		print("SHOVE_ENEMY_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_shove_pose_lifecycle() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(220.0, 180.0)
	actors.add_child(player)
	player.set_physics_process(false)

	var enemy := SHOVE_ENEMY_SCENE.instantiate() as ShoveEnemy
	enemy.position = Vector2(120.0, 180.0)
	actors.add_child(enemy)
	enemy.set_physics_process(false)
	await process_frame
	player.set_physics_process(false)
	enemy.set_physics_process(false)

	enemy.player = player
	enemy.patrol_direction = 1.0
	enemy.call("_enter_patrol")

	var body_shape := (
		enemy.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var body_rectangle := body_shape.shape as RectangleShape2D
	var attack_shape := (
		enemy.attack_area.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var attack_rectangle := attack_shape.shape as RectangleShape2D
	var body_transform_before := enemy.transform
	var collision_layer_before := enemy.collision_layer
	var collision_mask_before := enemy.collision_mask
	var body_shape_transform_before := body_shape.transform
	var body_shape_size_before := body_rectangle.size
	var attack_pivot_transform_before := enemy.attack_pivot.transform
	var attack_area_transform_before := enemy.attack_area.transform
	var attack_shape_transform_before := attack_shape.transform
	var attack_shape_size_before := attack_rectangle.size
	var edge_target_before := enemy.edge_probe.target_position
	var telegraph_transform_before := enemy.telegraph_visual.transform
	var visual_position_before := enemy.visual.position
	var visual_rotation_before := enemy.visual.rotation
	var visual_scale_y_before := enemy.visual.scale.y
	var visual_modulate_before := enemy.visual.modulate
	var visual_foot_y_before := (
		visual_position_before.y
		+ ShoveEnemy.VISUAL_HALF_HEIGHT * visual_scale_y_before
	)
	var telegraph_time_before := enemy.telegraph_time
	var lunge_time_before := enemy.lunge_time
	var recovery_time_before := enemy.recovery_time
	var lunge_speed_before := enemy.lunge_speed
	var shove_impulse_before := Vector2(
		enemy.shove_horizontal_impulse,
		enemy.shove_vertical_impulse
	)

	enemy.velocity = Vector2(enemy.patrol_speed, 0.0)
	enemy.patrol_cycle = 0.0
	enemy.call(
		"_update_shove_animation",
		1.0 / (4.0 * enemy.patrol_cycle_frequency)
	)
	_expect(
		enemy.state == ShoveEnemy.State.PATROL
		and enemy.patrol_cycle > 0.0
		and enemy.visual.position.y < visual_position_before.y
		and enemy.visual.rotation > visual_rotation_before
		and absf(enemy.visual.scale.x) < 1.0
		and enemy.visual.scale.y > visual_scale_y_before,
		"Patrol pose did not bob, stretch, and step forward."
	)

	enemy.patrol_direction = -1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_shove_visual")
	_expect(
		enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x < 0.0
		and enemy.edge_probe.target_position.x < 0.0,
		"Patrol pose did not mirror with direction."
	)

	enemy.patrol_direction = 1.0
	enemy.call("_enter_patrol")
	enemy.call("_begin_telegraph")
	_expect(
		enemy.state == ShoveEnemy.State.TELEGRAPH
		and is_equal_approx(
			enemy.state_time_remaining,
			enemy.telegraph_time
		)
		and enemy.telegraph_visual.visible
		and not enemy.attack_visual.visible
		and not enemy.attack_area.monitoring,
		"Telegraph entry changed its gameplay contract."
	)

	enemy.state_time_remaining = enemy.telegraph_time * 0.1
	enemy.call("_apply_shove_visual")
	var telegraph_position := enemy.visual.position
	var telegraph_rotation := enemy.visual.rotation
	var telegraph_scale := enemy.visual.scale
	_expect(
		enemy.visual.position.x < visual_position_before.x
		and enemy.visual.position.y > visual_position_before.y
		and enemy.visual.rotation < visual_rotation_before
		and absf(enemy.visual.scale.x) > 1.0
		and enemy.visual.scale.y < visual_scale_y_before
		and enemy.telegraph_visual.scale.x
		> enemy.base_telegraph_scale.x
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Late telegraph did not compress away from the player."
	)
	enemy.patrol_direction = -1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_shove_visual")
	_expect(
		is_equal_approx(
			enemy.visual.position.x - visual_position_before.x,
			-(telegraph_position.x - visual_position_before.x)
		)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(telegraph_rotation - visual_rotation_before)
		)
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(telegraph_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, telegraph_scale.y),
		"Telegraph pose did not mirror around its base transform."
	)
	enemy.patrol_direction = 1.0
	enemy.lunge_direction = 1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_shove_visual")

	enemy.call("_begin_lunge")
	var lunge_position := enemy.visual.position
	var lunge_rotation := enemy.visual.rotation
	var lunge_scale := enemy.visual.scale
	_expect(
		enemy.state == ShoveEnemy.State.LUNGE
		and is_equal_approx(
			enemy.state_time_remaining,
			enemy.lunge_time
		)
		and not enemy.telegraph_visual.visible
		and enemy.attack_visual.visible
		and enemy.attack_area.monitoring
		and enemy.visual.position.x > visual_position_before.x
		and enemy.visual.rotation > visual_rotation_before
		and absf(enemy.visual.scale.x) > 1.0
		and enemy.visual.scale.y < visual_scale_y_before
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Lunge pose or attack lifecycle is missing."
	)
	enemy.patrol_direction = -1.0
	enemy.lunge_direction = -1.0
	enemy.call("_sync_direction")
	enemy.attack_pivot.scale.x = -1.0
	enemy.call("_apply_shove_visual")
	_expect(
		is_equal_approx(
			enemy.visual.position.x - visual_position_before.x,
			-(lunge_position.x - visual_position_before.x)
		)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(lunge_rotation - visual_rotation_before)
		)
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(lunge_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, lunge_scale.y)
		and enemy.attack_pivot.scale.x == -1.0,
		"Lunge pose and attack pivot did not mirror together."
	)
	enemy.patrol_direction = 1.0
	enemy.lunge_direction = 1.0
	enemy.call("_sync_direction")
	enemy.attack_pivot.scale.x = 1.0
	enemy.call("_apply_shove_visual")

	enemy.call("_begin_recovery")
	var recovery_scale_y := enemy.visual.scale.y
	var recovery_rotation := enemy.visual.rotation
	await process_frame
	enemy.set_physics_process(false)
	_expect(
		enemy.state == ShoveEnemy.State.RECOVERY
		and is_equal_approx(
			enemy.state_time_remaining,
			enemy.recovery_time
		)
		and not enemy.attack_visual.visible
		and not enemy.attack_area.monitoring
		and enemy.visual.position.y > visual_position_before.y
		and recovery_scale_y < visual_scale_y_before
		and recovery_rotation < visual_rotation_before
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Recovery did not disable the hitbox and slump backward."
	)

	enemy.state_time_remaining = enemy.recovery_time * 0.1
	enemy.call("_apply_shove_visual")
	_expect(
		enemy.visual.scale.y > recovery_scale_y
		and absf(enemy.visual.rotation) < absf(recovery_rotation),
		"Recovery pose did not ease back toward patrol."
	)
	enemy.call("_enter_patrol")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before
		)
		and enemy.telegraph_visual.transform.is_equal_approx(
			telegraph_transform_before
		),
		"Patrol entry did not restore the base visual pose."
	)

	enemy.call("_begin_lunge")
	var received_impulse := Vector2(390.0, -170.0)
	enemy.receive_impulse(received_impulse)
	_expect(
		enemy.state == ShoveEnemy.State.KNOCKBACK
		and enemy.velocity.is_equal_approx(received_impulse)
		and is_equal_approx(
			enemy.knockback_time_remaining,
			enemy.knockback_lock_time
		)
		and not enemy.telegraph_visual.visible
		and not enemy.attack_visual.visible
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and absf(enemy.visual.scale.x) > 1.0
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before * (1.0 - enemy.hit_squash_y)
		)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before)
		and not enemy.visual.modulate.is_equal_approx(
			visual_modulate_before
		),
		"Knockback did not replace the lunge pose with hit feedback."
	)
	await process_frame
	enemy.set_physics_process(false)
	_expect(
		not enemy.attack_area.monitoring,
		"Knockback left the shove hitbox active."
	)

	var frozen_state := enemy.state
	var frozen_state_timer := enemy.state_time_remaining
	var frozen_knockback_timer := enemy.knockback_time_remaining
	var frozen_hit_timer := enemy.hit_flash_time_remaining
	var frozen_cycle := enemy.patrol_cycle
	var frozen_position := enemy.position
	var frozen_velocity := enemy.velocity
	var frozen_visual_transform := enemy.visual.transform
	var frozen_modulate := enemy.visual.modulate
	enemy.begin_impact_freeze(3)
	for _frame in 3:
		enemy._physics_process(1.0 / 60.0)
	_expect(
		is_zero_approx(enemy.impact_freeze_frames_remaining)
		and enemy.state == frozen_state
		and is_equal_approx(
			enemy.state_time_remaining,
			frozen_state_timer
		)
		and is_equal_approx(
			enemy.knockback_time_remaining,
			frozen_knockback_timer
		)
		and is_equal_approx(enemy.hit_flash_time_remaining, frozen_hit_timer)
		and is_equal_approx(enemy.patrol_cycle, frozen_cycle)
		and enemy.position.is_equal_approx(frozen_position)
		and enemy.velocity.is_equal_approx(frozen_velocity)
		and enemy.visual.transform.is_equal_approx(
			frozen_visual_transform
		)
		and enemy.visual.modulate.is_equal_approx(frozen_modulate),
		"Hit-stop did not hold shove state, timers, physics, and pose."
	)

	enemy.call("_update_hit_flash", enemy.hit_flash_duration)
	enemy.call("_apply_shove_visual")
	_expect(
		is_zero_approx(enemy.hit_flash_time_remaining)
		and enemy.visual.modulate.is_equal_approx(visual_modulate_before)
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and absf(enemy.visual.scale.x) > 1.0
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before
		),
		"Hit feedback did not preserve the knockback pose."
	)
	enemy.knockback_time_remaining = 0.0
	enemy.call("_enter_patrol")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before
		),
		"Knockback recovery did not restore the patrol pose."
	)

	_expect(
		_enemy_geometry_is_unchanged(
			enemy,
			body_shape,
			attack_shape,
			body_transform_before,
			collision_layer_before,
			collision_mask_before,
			body_shape_transform_before,
			body_shape_size_before,
			attack_pivot_transform_before,
			attack_area_transform_before,
			attack_shape_transform_before,
			attack_shape_size_before,
			edge_target_before
		),
		"Shove animation changed body, probe, or attack geometry."
	)
	_expect(
		is_equal_approx(enemy.telegraph_time, telegraph_time_before)
		and is_equal_approx(enemy.lunge_time, lunge_time_before)
		and is_equal_approx(enemy.recovery_time, recovery_time_before)
		and is_equal_approx(enemy.lunge_speed, lunge_speed_before)
		and Vector2(
			enemy.shove_horizontal_impulse,
			enemy.shove_vertical_impulse
		).is_equal_approx(shove_impulse_before),
		"Shove animation changed AI timing, speed, or impulse."
	)

	actors.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _visual_foot_y(enemy: ShoveEnemy) -> float:
	return (
		enemy.visual.position.y
		+ ShoveEnemy.VISUAL_HALF_HEIGHT * enemy.visual.scale.y
	)


func _enemy_geometry_is_unchanged(
	enemy: ShoveEnemy,
	body_shape: CollisionShape2D,
	attack_shape: CollisionShape2D,
	body_transform: Transform2D,
	collision_layer: int,
	collision_mask: int,
	body_shape_transform: Transform2D,
	body_shape_size: Vector2,
	attack_pivot_transform: Transform2D,
	attack_area_transform: Transform2D,
	attack_shape_transform: Transform2D,
	attack_shape_size: Vector2,
	edge_target: Vector2
) -> bool:
	var body_rectangle := body_shape.shape as RectangleShape2D
	var attack_rectangle := attack_shape.shape as RectangleShape2D
	return (
		enemy.transform.is_equal_approx(body_transform)
		and enemy.collision_layer == collision_layer
		and enemy.collision_mask == collision_mask
		and body_shape.transform.is_equal_approx(body_shape_transform)
		and body_rectangle.size.is_equal_approx(body_shape_size)
		and enemy.attack_pivot.transform.is_equal_approx(
			attack_pivot_transform
		)
		and enemy.attack_area.transform.is_equal_approx(
			attack_area_transform
		)
		and attack_shape.transform.is_equal_approx(
			attack_shape_transform
		)
		and attack_rectangle.size.is_equal_approx(attack_shape_size)
		and enemy.edge_probe.target_position.is_equal_approx(edge_target)
	)

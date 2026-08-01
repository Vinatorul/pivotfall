extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SHOOTER_ENEMY_SCENE := preload("res://scenes/shooter_enemy.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shooter_pose_lifecycle()

	if failures.is_empty():
		print("SHOOTER_ENEMY_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_shooter_pose_lifecycle() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(260.0, 180.0)
	actors.add_child(player)
	player.set_physics_process(false)

	var enemy := SHOOTER_ENEMY_SCENE.instantiate() as ShooterEnemy
	enemy.position = Vector2(120.0, 180.0)
	actors.add_child(enemy)
	enemy.set_physics_process(false)
	await process_frame
	player.set_physics_process(false)
	enemy.set_physics_process(false)

	enemy.player = player
	enemy.facing_direction = 1.0
	enemy.call("_enter_ready")

	var body_shape := (
		enemy.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var body_rectangle := body_shape.shape as RectangleShape2D
	var body_transform_before := enemy.transform
	var collision_layer_before := enemy.collision_layer
	var collision_mask_before := enemy.collision_mask
	var body_shape_transform_before := body_shape.transform
	var body_shape_size_before := body_rectangle.size
	var visual_position_before := enemy.base_visual_position
	var visual_rotation_before := enemy.base_visual_rotation
	var visual_scale_x_before := enemy.base_visual_scale_x
	var visual_scale_y_before := enemy.base_visual_scale_y
	var visual_modulate_before := enemy.base_visual_modulate
	var visual_foot_y_before := (
		visual_position_before.y
		+ ShooterEnemy.VISUAL_HALF_HEIGHT * visual_scale_y_before
	)
	var aim_time_before := enemy.aim_time
	var aim_lock_time_before := enemy.aim_lock_time
	var cooldown_time_before := enemy.cooldown_time
	var muzzle_flash_time_before := enemy.muzzle_flash_time
	var line_length_before := enemy.line_length
	var projectile_scene_before := enemy.projectile_scene

	var ready_velocity := Vector2(18.0, -7.0)
	enemy.velocity = ready_velocity
	enemy.ready_cycle = 0.0
	enemy.call(
		"_update_shooter_animation",
		1.0 / (4.0 * enemy.ready_cycle_frequency)
	)
	var ready_position := enemy.visual.position
	var ready_rotation := enemy.visual.rotation
	var ready_scale := enemy.visual.scale
	_expect(
		enemy.state == ShooterEnemy.State.READY
		and is_zero_approx(enemy.state_time_remaining)
		and enemy.velocity.is_equal_approx(ready_velocity)
		and enemy.ready_cycle > 0.0
		and enemy.visual.position.y < visual_position_before.y
		and enemy.visual.rotation > visual_rotation_before
		and absf(enemy.visual.scale.x) < visual_scale_x_before
		and enemy.visual.scale.y > visual_scale_y_before,
		"Ready pose did not breathe without changing shooter state or velocity."
	)

	enemy.facing_direction = -1.0
	enemy.call("_apply_shooter_visual")
	_expect(
		enemy.visual.position.is_equal_approx(ready_position)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(ready_rotation - visual_rotation_before)
		)
		and enemy.visual.scale.x < 0.0
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(ready_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, ready_scale.y),
		"Ready pose did not mirror around its base transform."
	)

	enemy.facing_direction = 1.0
	enemy.call("_enter_ready")
	enemy.call("_begin_aim")
	_expect(
		enemy.state == ShooterEnemy.State.AIMING
		and is_equal_approx(enemy.state_time_remaining, enemy.aim_time)
		and enemy.aim_line.visible
		and enemy.aim_mark.visible
		and enemy.target_mark.visible
		and not enemy.aim_is_locked
		and enemy.velocity.x == 0.0,
		"Aim entry changed the existing tracking contract."
	)

	enemy.state_time_remaining = enemy.aim_time * 0.5
	enemy.call("_apply_shooter_visual")
	var tracking_position := enemy.visual.position
	var tracking_rotation := enemy.visual.rotation
	var tracking_scale := enemy.visual.scale
	_expect(
		enemy.visual.position.x > visual_position_before.x
		and enemy.visual.position.y > visual_position_before.y
		and enemy.visual.rotation > visual_rotation_before
		and absf(enemy.visual.scale.x) > visual_scale_x_before
		and enemy.visual.scale.y < visual_scale_y_before
		and enemy.aim_mark.scale.is_equal_approx(
			enemy.base_aim_mark_scale
		)
		and enemy.target_mark.scale.is_equal_approx(
			enemy.base_target_mark_scale
		)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Tracking pose did not brace toward the player."
	)

	enemy.facing_direction = -1.0
	enemy.call("_apply_shooter_visual")
	_expect(
		is_equal_approx(
			enemy.visual.position.x - visual_position_before.x,
			-(tracking_position.x - visual_position_before.x)
		)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(tracking_rotation - visual_rotation_before)
		)
		and enemy.visual.scale.x < 0.0
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(tracking_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, tracking_scale.y),
		"Tracking pose did not mirror with facing direction."
	)

	enemy.facing_direction = 1.0
	enemy.aim_is_locked = true
	enemy.state_time_remaining = enemy.aim_lock_time * 0.5
	enemy.call("_update_aim_style")
	enemy.call("_apply_shooter_visual")
	_expect(
		enemy.visual.position.x > tracking_position.x
		and enemy.visual.position.y > tracking_position.y
		and enemy.visual.rotation > tracking_rotation
		and absf(enemy.visual.scale.x) > absf(tracking_scale.x)
		and enemy.visual.scale.y < tracking_scale.y
		and enemy.aim_mark.scale.x > enemy.base_aim_mark_scale.x
		and enemy.target_mark.scale.x > enemy.base_target_mark_scale.x
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Aim lock did not strengthen the brace and target markers."
	)

	enemy.call("_begin_cooldown")
	enemy.facing_direction = 1.0
	enemy.fire_visual_direction = enemy.facing_direction
	enemy.flash_time_remaining = enemy.muzzle_flash_time
	enemy.muzzle_flash.visible = true
	enemy.state_time_remaining = enemy.cooldown_time
	enemy.call("_apply_shooter_visual")
	var fire_position := enemy.visual.position
	var fire_rotation := enemy.visual.rotation
	var fire_scale := enemy.visual.scale
	_expect(
		enemy.state == ShooterEnemy.State.COOLDOWN
		and is_equal_approx(
			enemy.state_time_remaining,
			enemy.cooldown_time
		)
		and not enemy.aim_line.visible
		and not enemy.aim_mark.visible
		and not enemy.target_mark.visible
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.position.y > visual_position_before.y
		and enemy.visual.rotation < visual_rotation_before
		and absf(enemy.visual.scale.x) > visual_scale_x_before
		and enemy.visual.scale.y < visual_scale_y_before
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Fire pose did not recoil backward into cooldown."
	)

	player.position = Vector2(10.0, 180.0)
	enemy.call("_track_player")
	enemy.call("_apply_shooter_visual")
	_expect(
		enemy.facing_direction < 0.0
		and enemy.fire_visual_direction > 0.0
		and is_equal_approx(enemy.visual.position.x, fire_position.x)
		and enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x < 0.0,
		"Fire recoil changed direction when the player crossed the shooter."
	)
	player.position = Vector2(260.0, 180.0)
	enemy.call("_track_player")
	enemy.call("_apply_shooter_visual")

	enemy.flash_time_remaining = 0.0
	enemy.muzzle_flash.visible = false
	enemy.state_time_remaining = enemy.cooldown_time * 0.5
	enemy.call("_apply_shooter_visual")
	_expect(
		absf(enemy.visual.position.x - visual_position_before.x)
		< absf(fire_position.x - visual_position_before.x)
		and absf(enemy.visual.rotation - visual_rotation_before)
		< absf(fire_rotation - visual_rotation_before)
		and absf(enemy.visual.scale.x) < absf(fire_scale.x)
		and enemy.visual.scale.y > fire_scale.y
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Fire recoil did not decay into the slower cooldown slump."
	)

	enemy.state_time_remaining = 0.0
	enemy.call("_apply_shooter_visual")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			visual_scale_x_before
		)
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before),
		"Cooldown pose did not recover to the neutral body transform."
	)

	enemy.call("_enter_ready")
	player.position = Vector2(10.0, 180.0)
	enemy.patrol_direction = 1.0
	enemy.call("_sync_direction")
	enemy.call("_track_player")
	enemy.call("_apply_shooter_visual")
	_expect(
		enemy.facing_direction < 0.0
		and enemy.patrol_direction > 0.0,
		"Test setup did not separate facing from impulse direction."
	)

	enemy.call("_begin_aim")
	var gun_transform_before := enemy.gun_pivot.transform
	var muzzle_transform_before := enemy.muzzle.transform
	var ray_transform_before := enemy.aim_ray.transform
	var ray_target_before := enemy.aim_ray.target_position
	var ray_enabled_before := enemy.aim_ray.enabled
	var ray_collision_mask_before := enemy.aim_ray.collision_mask
	var aim_mark_position_before := enemy.aim_mark.position
	var target_mark_position_before := enemy.target_mark.position
	var received_impulse := Vector2(390.0, -170.0)
	enemy.receive_impulse(received_impulse)
	_expect(
		enemy.state == ShooterEnemy.State.KNOCKBACK
		and enemy.velocity.is_equal_approx(received_impulse)
		and is_equal_approx(
			enemy.knockback_time_remaining,
			enemy.knockback_lock_time
		)
		and enemy.knockback_visual_direction > 0.0
		and enemy.facing_direction < 0.0
		and not enemy.aim_line.visible
		and not enemy.aim_mark.visible
		and not enemy.target_mark.visible
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x < -visual_scale_x_before
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before * (1.0 - enemy.hit_squash_y)
		)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before)
		and not enemy.visual.modulate.is_equal_approx(
			visual_modulate_before
		),
		"Knockback pose followed aim facing instead of the received impulse."
	)

	enemy.flash_time_remaining = enemy.muzzle_flash_time * 0.75
	enemy.muzzle_flash.visible = true
	var frozen_state := enemy.state
	var frozen_state_timer := enemy.state_time_remaining
	var frozen_knockback_timer := enemy.knockback_time_remaining
	var frozen_hit_timer := enemy.hit_flash_time_remaining
	var frozen_flash_timer := enemy.flash_time_remaining
	var frozen_cycle := enemy.ready_cycle
	var frozen_fire_direction := enemy.fire_visual_direction
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
		and is_equal_approx(enemy.flash_time_remaining, frozen_flash_timer)
		and is_equal_approx(enemy.ready_cycle, frozen_cycle)
		and is_equal_approx(
			enemy.fire_visual_direction,
			frozen_fire_direction
		)
		and enemy.position.is_equal_approx(frozen_position)
		and enemy.velocity.is_equal_approx(frozen_velocity)
		and enemy.visual.transform.is_equal_approx(
			frozen_visual_transform
		)
		and enemy.visual.modulate.is_equal_approx(frozen_modulate),
		"Hit-stop did not hold shooter state, timers, physics, and pose."
	)

	enemy.call("_update_hit_flash", enemy.hit_flash_duration)
	enemy.call("_apply_shooter_visual")
	_expect(
		is_zero_approx(enemy.hit_flash_time_remaining)
		and enemy.visual.modulate.is_equal_approx(visual_modulate_before)
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x < -visual_scale_x_before
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Hit feedback did not preserve the independent knockback pose."
	)

	enemy.flash_time_remaining = 0.0
	enemy.muzzle_flash.visible = false
	enemy.knockback_time_remaining = 0.0
	enemy.call("_apply_shooter_visual")
	var knockback_settle_transform := enemy.visual.transform
	enemy.call("_begin_cooldown")
	_expect(
		enemy.visual.transform.is_equal_approx(
			knockback_settle_transform
		)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Knockback end did not join the initial cooldown pose."
	)
	enemy.call("_enter_ready")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(
			enemy.visual.scale.x,
			-enemy.base_visual_scale_x
		)
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before)
		and enemy.aim_mark.scale.is_equal_approx(
			enemy.base_aim_mark_scale
		)
		and enemy.target_mark.scale.is_equal_approx(
			enemy.base_target_mark_scale
		),
		"Knockback recovery did not restore the ready pose."
	)

	_expect(
		_enemy_geometry_is_unchanged(
			enemy,
			body_shape,
			body_transform_before,
			collision_layer_before,
			collision_mask_before,
			body_shape_transform_before,
			body_shape_size_before,
			gun_transform_before,
			muzzle_transform_before,
			ray_transform_before,
			ray_target_before,
			ray_enabled_before,
			ray_collision_mask_before,
			aim_mark_position_before,
			target_mark_position_before
		),
		"Shooter animation changed body, gun, muzzle, ray, or marker geometry."
	)
	_expect(
		is_equal_approx(enemy.aim_time, aim_time_before)
		and is_equal_approx(enemy.aim_lock_time, aim_lock_time_before)
		and is_equal_approx(enemy.cooldown_time, cooldown_time_before)
		and is_equal_approx(
			enemy.muzzle_flash_time,
			muzzle_flash_time_before
		)
		and is_equal_approx(enemy.line_length, line_length_before)
		and enemy.projectile_scene == projectile_scene_before,
		"Shooter animation changed AI timing, range, or projectile data."
	)

	actors.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _visual_foot_y(enemy: ShooterEnemy) -> float:
	return (
		enemy.visual.position.y
		+ ShooterEnemy.VISUAL_HALF_HEIGHT * enemy.visual.scale.y
	)


func _enemy_geometry_is_unchanged(
	enemy: ShooterEnemy,
	body_shape: CollisionShape2D,
	body_transform: Transform2D,
	collision_layer: int,
	collision_mask: int,
	body_shape_transform: Transform2D,
	body_shape_size: Vector2,
	gun_transform: Transform2D,
	muzzle_transform: Transform2D,
	ray_transform: Transform2D,
	ray_target: Vector2,
	ray_enabled: bool,
	ray_collision_mask: int,
	aim_mark_position: Vector2,
	target_mark_position: Vector2
) -> bool:
	var body_rectangle := body_shape.shape as RectangleShape2D
	return (
		enemy.transform.is_equal_approx(body_transform)
		and enemy.collision_layer == collision_layer
		and enemy.collision_mask == collision_mask
		and body_shape.transform.is_equal_approx(body_shape_transform)
		and body_rectangle.size.is_equal_approx(body_shape_size)
		and enemy.gun_pivot.transform.is_equal_approx(gun_transform)
		and enemy.muzzle.transform.is_equal_approx(muzzle_transform)
		and enemy.aim_ray.transform.is_equal_approx(ray_transform)
		and enemy.aim_ray.target_position.is_equal_approx(ray_target)
		and enemy.aim_ray.enabled == ray_enabled
		and enemy.aim_ray.collision_mask == ray_collision_mask
		and enemy.aim_mark.position.is_equal_approx(aim_mark_position)
		and enemy.target_mark.position.is_equal_approx(
			target_mark_position
		)
	)

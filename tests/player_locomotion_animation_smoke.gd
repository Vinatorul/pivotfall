extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_locomotion_pose_lifecycle()
	await _test_real_landing_detection()

	if failures.is_empty():
		print("PLAYER_LOCOMOTION_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_locomotion_pose_lifecycle() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(120.0, 180.0)
	actors.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.set_physics_process(false)

	var body_shape := (
		player.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var body_rectangle := body_shape.shape as RectangleShape2D
	var attack_shape := (
		player.attack_area.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var attack_rectangle := attack_shape.shape as RectangleShape2D
	var body_transform_before := player.transform
	var body_collision_layer_before := player.collision_layer
	var body_collision_mask_before := player.collision_mask
	var body_shape_transform_before := body_shape.transform
	var body_shape_size_before := body_rectangle.size
	var attack_pivot_transform_before := player.attack_pivot.transform
	var attack_area_transform_before := player.attack_area.transform
	var attack_monitoring_before := player.attack_area.monitoring
	var attack_shape_transform_before := attack_shape.transform
	var attack_shape_size_before := attack_rectangle.size
	var visual_position_before := player.visual.position
	var visual_rotation_before := player.visual.rotation
	var visual_scale_y_before := player.visual.scale.y

	player.velocity = Vector2.ZERO
	player.call(
		"_update_locomotion_animation",
		1.0 / (4.0 * player.idle_bob_frequency),
		true,
		true,
		0.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.IDLE
		and player.visual.position.y < visual_position_before.y
		and player.visual.scale.y > visual_scale_y_before,
		"Idle pose did not produce a subtle breathing motion."
	)

	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	player.velocity = Vector2(player.move_speed, 0.0)
	player.run_cycle = 0.0
	player.call(
		"_update_locomotion_animation",
		1.0 / (4.0 * player.run_cycle_frequency),
		true,
		true,
		0.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.RUN
		and player.run_cycle > 0.0
		and player.visual.position.y < visual_position_before.y
		and player.visual.rotation > visual_rotation_before
		and player.visual.scale.y > visual_scale_y_before,
		"Run pose did not bob, stretch, and lean forward."
	)

	player.facing_direction = -1.0
	player.visual.scale.x = -1.0
	player.attack_pivot.scale.x = -1.0
	player.velocity.x = -player.move_speed
	player.call(
		"_update_locomotion_animation",
		0.0,
		true,
		true,
		0.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.RUN
		and player.visual.rotation < visual_rotation_before
		and player.visual.scale.x == -1.0
		and player.attack_pivot.scale.x == -1.0,
		"Run lean did not mirror with the facing direction."
	)

	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	player.velocity = Vector2(player.move_speed * 0.5, player.jump_velocity)
	player.call(
		"_update_locomotion_animation",
		0.0,
		true,
		false,
		0.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.RISE
		and player.visual.position.y < visual_position_before.y
		and player.visual.scale.y > visual_scale_y_before,
		"Rising pose did not stretch the player vertically."
	)

	player.velocity = Vector2(0.0, player.maximum_fall_speed * 0.75)
	player.call(
		"_update_locomotion_animation",
		0.0,
		false,
		false,
		player.velocity.y,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.FALL
		and player.visual.position.y < visual_position_before.y
		and player.visual.scale.y > visual_scale_y_before,
		"Falling pose did not preserve the airborne stretch."
	)

	player.velocity = Vector2.ZERO
	player.call(
		"_update_locomotion_animation",
		0.0,
		false,
		true,
		player.maximum_fall_speed * 0.8,
		false
	)
	var full_landing_scale := player.visual.scale.y
	_expect(
		player.locomotion_pose == Player.LocomotionPose.LAND
		and is_equal_approx(
			player.landing_time_remaining,
			player.landing_duration
		)
		and player.visual.position.y > visual_position_before.y
		and full_landing_scale < visual_scale_y_before,
		"Landing did not start with a grounded squash."
	)

	player.call(
		"_update_locomotion_animation",
		player.landing_duration * 0.5,
		true,
		true,
		0.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.LAND
		and player.visual.scale.y > full_landing_scale
		and player.visual.scale.y < visual_scale_y_before,
		"Landing squash did not recover toward the base pose."
	)

	player.call(
		"_update_locomotion_animation",
		player.landing_duration * 0.5,
		true,
		true,
		0.0,
		false
	)
	player.call(
		"_update_locomotion_animation",
		0.0,
		true,
		true,
		0.0,
		false
	)
	_expect(
		is_zero_approx(player.landing_time_remaining)
		and player.locomotion_pose == Player.LocomotionPose.IDLE,
		"Landing pose did not return control to idle."
	)

	player.landing_time_remaining = 0.0
	player.velocity = Vector2.ZERO
	player.call(
		"_update_locomotion_animation",
		0.0,
		false,
		true,
		player.landing_min_speed - 1.0,
		false
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.IDLE
		and is_zero_approx(player.landing_time_remaining),
		"A low-speed floor seam triggered a false landing."
	)

	player.velocity = Vector2(player.move_speed, 0.0)
	player.call(
		"_update_locomotion_animation",
		0.0,
		true,
		true,
		0.0,
		true
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.IDLE,
		"Ground knockback incorrectly used the run pose."
	)

	player.velocity = Vector2(player.move_speed * 0.5, 420.0)
	player.call(
		"_update_locomotion_animation",
		0.0,
		false,
		false,
		player.velocity.y,
		true
	)
	player.call("_start_attack")
	var attack_position := player.visual.position
	var attack_rotation := player.visual.rotation
	var attack_scale_y := player.visual.scale.y
	player.velocity = Vector2(-80.0, 640.0)
	player.call(
		"_update_locomotion_animation",
		0.05,
		false,
		false,
		player.velocity.y,
		true
	)
	_expect(
		player.locomotion_pose == Player.LocomotionPose.FALL
		and player.visual.position.is_equal_approx(attack_position)
		and is_equal_approx(player.visual.rotation, attack_rotation)
		and is_equal_approx(player.visual.scale.y, attack_scale_y),
		"Locomotion overwrote the active attack pose."
	)
	player.call("_finish_attack")
	_expect(
		not player.attack_visual.visible
		and player.locomotion_pose == Player.LocomotionPose.FALL
		and player.visual.position.y < visual_position_before.y
		and player.visual.scale.y > visual_scale_y_before,
		"Attack did not return to the current airborne pose."
	)

	player.velocity = Vector2(player.move_speed, 0.0)
	player.call(
		"_update_locomotion_animation",
		0.05,
		true,
		true,
		0.0,
		false
	)
	var frozen_time := player.locomotion_time
	var frozen_cycle := player.run_cycle
	var frozen_position := player.position
	var frozen_velocity := player.velocity
	var frozen_visual_transform := player.visual.transform
	player.begin_impact_freeze(player.attack_hit_stop_frames)
	for _frame in player.attack_hit_stop_frames:
		player._physics_process(1.0 / 60.0)
	_expect(
		is_zero_approx(player.impact_freeze_frames_remaining)
		and is_equal_approx(player.locomotion_time, frozen_time)
		and is_equal_approx(player.run_cycle, frozen_cycle)
		and player.position.is_equal_approx(frozen_position)
		and player.velocity.is_equal_approx(frozen_velocity)
		and player.visual.transform.is_equal_approx(
			frozen_visual_transform
		),
		"Impact freeze did not hold locomotion and physics state."
	)

	_expect(
		_player_geometry_is_unchanged(
			player,
			body_shape,
			attack_shape,
			body_transform_before,
			body_collision_layer_before,
			body_collision_mask_before,
			body_shape_transform_before,
			body_shape_size_before,
			attack_pivot_transform_before,
			attack_area_transform_before,
			attack_monitoring_before,
			attack_shape_transform_before,
			attack_shape_size_before
		),
		"Locomotion animation changed body or attack geometry."
	)

	actors.queue_free()
	await process_frame


func _test_real_landing_detection() -> void:
	var world := Node2D.new()
	world.name = "LandingWorld"
	root.add_child(world)

	var floor := StaticBody2D.new()
	floor.position = Vector2(240.0, 260.0)
	var floor_shape := CollisionShape2D.new()
	var floor_rectangle := RectangleShape2D.new()
	floor_rectangle.size = Vector2(360.0, 40.0)
	floor_shape.shape = floor_rectangle
	floor.add_child(floor_shape)
	world.add_child(floor)

	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(240.0, 100.0)
	world.add_child(player)

	var landing_detected := false
	for _frame in 120:
		await physics_frame
		if player.locomotion_pose == Player.LocomotionPose.LAND:
			landing_detected = true
			break

	_expect(
		landing_detected
		and player.is_on_floor()
		and player.landing_strength >= 0.35
		and player.visual.scale.y < player.base_visual_scale_y,
		"Real fall did not enter the landing pose after move_and_slide."
	)

	world.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _player_geometry_is_unchanged(
	player: Player,
	body_shape: CollisionShape2D,
	attack_shape: CollisionShape2D,
	body_transform: Transform2D,
	body_collision_layer: int,
	body_collision_mask: int,
	body_shape_transform: Transform2D,
	body_shape_size: Vector2,
	attack_pivot_transform: Transform2D,
	attack_area_transform: Transform2D,
	attack_monitoring: bool,
	attack_shape_transform: Transform2D,
	attack_shape_size: Vector2
) -> bool:
	var body_rectangle := body_shape.shape as RectangleShape2D
	var attack_rectangle := attack_shape.shape as RectangleShape2D
	return (
		player.transform.is_equal_approx(body_transform)
		and player.collision_layer == body_collision_layer
		and player.collision_mask == body_collision_mask
		and body_shape.transform.is_equal_approx(body_shape_transform)
		and body_rectangle.size.is_equal_approx(body_shape_size)
		and player.attack_pivot.transform.is_equal_approx(
			attack_pivot_transform
		)
		and player.attack_area.transform.is_equal_approx(
			attack_area_transform
		)
		and player.attack_area.monitoring == attack_monitoring
		and attack_shape.transform.is_equal_approx(
			attack_shape_transform
		)
		and attack_rectangle.size.is_equal_approx(attack_shape_size)
	)

extends SceneTree

const PATROL_ENEMY_SCENE := preload("res://scenes/patrol_enemy.tscn")
const SHOVE_ENEMY_SCENE := preload("res://scenes/shove_enemy.tscn")
const SHOOTER_ENEMY_SCENE := preload("res://scenes/shooter_enemy.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_patrol_pose_lifecycle()
	await _test_natural_wall_turn()
	await _test_child_compositor_guards()

	if failures.is_empty():
		print("PATROL_ENEMY_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_patrol_pose_lifecycle() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var enemy := PATROL_ENEMY_SCENE.instantiate() as PatrolEnemy
	enemy.position = Vector2(120.0, 180.0)
	enemy.set_physics_process(false)
	actors.add_child(enemy)
	await process_frame
	enemy.set_physics_process(false)

	enemy.patrol_direction = 1.0
	enemy.velocity = Vector2.ZERO
	enemy.patrol_animation_cycle = 0.0
	enemy.patrol_turn_visual_time_remaining = 0.0
	enemy.knockback_time_remaining = 0.0
	enemy.hit_flash_time_remaining = 0.0
	enemy.call("_sync_direction")
	enemy.call("_apply_hit_visual")
	enemy.call("_apply_patrol_visual")

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
	var edge_transform_before := enemy.edge_probe.transform
	var edge_target_before := enemy.edge_probe.target_position
	var edge_enabled_before := enemy.edge_probe.enabled
	var edge_collision_mask_before := enemy.edge_probe.collision_mask
	var visual_position_before := enemy.patrol_base_visual_position
	var visual_rotation_before := enemy.patrol_base_visual_rotation
	var visual_scale_x_before := enemy.patrol_base_visual_scale_x
	var visual_scale_y_before := enemy.base_visual_scale_y
	var visual_modulate_before := enemy.base_visual_modulate
	var visual_foot_y_before := _visual_foot_y(enemy)
	var patrol_speed_before := enemy.patrol_speed
	var knockback_lock_time_before := enemy.knockback_lock_time
	var knockback_drag_before := enemy.knockback_drag
	var maximum_fall_speed_before := enemy.maximum_fall_speed
	var gravity_before := enemy.gravity
	var hit_flash_duration_before := enemy.hit_flash_duration
	var hit_squash_y_before := enemy.hit_squash_y

	enemy.velocity = Vector2(enemy.patrol_speed, 0.0)
	enemy.patrol_animation_cycle = 0.0
	enemy.call(
		"_update_patrol_animation",
		1.0 / (4.0 * enemy.patrol_walk_cycle_frequency)
	)
	var walk_position := enemy.visual.position
	var walk_rotation := enemy.visual.rotation
	var walk_scale := enemy.visual.scale
	_expect(
		enemy.velocity.is_equal_approx(
			Vector2(enemy.patrol_speed, 0.0)
		)
		and enemy.patrol_animation_cycle > 0.0
		and enemy.visual.position.y < visual_position_before.y
		and enemy.visual.rotation > visual_rotation_before
		and absf(enemy.visual.scale.x) < visual_scale_x_before
		and enemy.visual.scale.y > visual_scale_y_before
		and is_equal_approx(
			_visual_foot_y(enemy),
			visual_foot_y_before - enemy.patrol_walk_bob_height
		),
		"Patrol walk did not bob, stretch, and lean without changing velocity."
	)

	enemy.patrol_direction = -1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_patrol_visual")
	_expect(
		enemy.visual.position.is_equal_approx(walk_position)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(walk_rotation - visual_rotation_before)
		)
		and enemy.visual.scale.x < 0.0
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(walk_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, walk_scale.y)
		and enemy.edge_probe.target_position.x < 0.0,
		"Patrol walk did not mirror with movement direction."
	)

	enemy.patrol_direction = 1.0
	enemy.call("_sync_direction")
	enemy.patrol_animation_cycle = 0.0
	var turn_velocity := Vector2(enemy.patrol_speed, -6.0)
	enemy.velocity = turn_velocity
	enemy.call("_turn_around")
	enemy.call("_start_patrol_turn_visual")
	var turn_position := enemy.visual.position
	var turn_rotation := enemy.visual.rotation
	var turn_scale := enemy.visual.scale
	_expect(
		enemy.patrol_direction < 0.0
		and enemy.velocity.is_equal_approx(turn_velocity)
		and is_equal_approx(
			enemy.patrol_turn_visual_time_remaining,
			enemy.patrol_turn_visual_time
		)
		and is_zero_approx(enemy.patrol_animation_cycle)
		and enemy.visual.position.x > visual_position_before.x
		and enemy.visual.position.y > visual_position_before.y
		and enemy.visual.rotation > visual_rotation_before
		and enemy.visual.scale.x < -visual_scale_x_before
		and enemy.visual.scale.y < visual_scale_y_before
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Patrol turn did not compress behind its new direction."
	)

	enemy.patrol_direction = 1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_patrol_visual")
	_expect(
		is_equal_approx(
			enemy.visual.position.x - visual_position_before.x,
			-(turn_position.x - visual_position_before.x)
		)
		and is_equal_approx(
			enemy.visual.rotation - visual_rotation_before,
			-(turn_rotation - visual_rotation_before)
		)
		and enemy.visual.scale.x > visual_scale_x_before
		and is_equal_approx(
			absf(enemy.visual.scale.x),
			absf(turn_scale.x)
		)
		and is_equal_approx(enemy.visual.scale.y, turn_scale.y),
		"Patrol turn pose did not mirror around its base transform."
	)

	enemy.call(
		"_update_patrol_animation",
		enemy.patrol_turn_visual_time * 0.5
	)
	_expect(
		is_equal_approx(
			enemy.patrol_turn_visual_time_remaining,
			enemy.patrol_turn_visual_time * 0.5
		)
		and absf(enemy.visual.position.x - visual_position_before.x)
		< absf(turn_position.x - visual_position_before.x)
		and absf(enemy.visual.rotation - visual_rotation_before)
		< absf(turn_rotation - visual_rotation_before)
		and enemy.visual.scale.y > turn_scale.y
		and enemy.velocity.is_equal_approx(turn_velocity),
		"Patrol turn pose did not recover without delaying movement."
	)

	enemy.patrol_turn_visual_time_remaining = 0.0
	enemy.patrol_animation_cycle = 0.0
	enemy.velocity = Vector2.ZERO
	enemy.call("_apply_patrol_visual")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(enemy.visual.scale.x, visual_scale_x_before)
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before),
		"Patrol turn recovery did not restore the neutral pose."
	)

	enemy.patrol_animation_cycle = PI * 0.5
	var received_impulse := Vector2(390.0, -170.0)
	enemy.receive_impulse(received_impulse)
	_expect(
		enemy.velocity.is_equal_approx(received_impulse)
		and is_equal_approx(
			enemy.knockback_time_remaining,
			enemy.knockback_lock_time
		)
		and enemy.patrol_knockback_visual_direction > 0.0
		and enemy.patrol_direction > 0.0
		and is_zero_approx(enemy.patrol_animation_cycle)
		and is_zero_approx(enemy.patrol_turn_visual_time_remaining)
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x > visual_scale_x_before
		and is_equal_approx(
			enemy.visual.scale.y,
			visual_scale_y_before * (1.0 - enemy.hit_squash_y)
		)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before)
		and not enemy.visual.modulate.is_equal_approx(
			visual_modulate_before
		),
		"Patrol knockback did not compose recoil with immediate hit feedback."
	)

	var frozen_knockback_timer := enemy.knockback_time_remaining
	var frozen_hit_timer := enemy.hit_flash_time_remaining
	var frozen_turn_timer := enemy.patrol_turn_visual_time_remaining
	var frozen_cycle := enemy.patrol_animation_cycle
	var frozen_position := enemy.position
	var frozen_velocity := enemy.velocity
	var frozen_visual_transform := enemy.visual.transform
	var frozen_modulate := enemy.visual.modulate
	enemy.begin_impact_freeze(3)
	for _frame in 3:
		enemy._physics_process(1.0 / 60.0)
	_expect(
		is_zero_approx(enemy.impact_freeze_frames_remaining)
		and is_equal_approx(
			enemy.knockback_time_remaining,
			frozen_knockback_timer
		)
		and is_equal_approx(enemy.hit_flash_time_remaining, frozen_hit_timer)
		and is_equal_approx(
			enemy.patrol_turn_visual_time_remaining,
			frozen_turn_timer
		)
		and is_equal_approx(enemy.patrol_animation_cycle, frozen_cycle)
		and enemy.position.is_equal_approx(frozen_position)
		and enemy.velocity.is_equal_approx(frozen_velocity)
		and enemy.visual.transform.is_equal_approx(
			frozen_visual_transform
		)
		and enemy.visual.modulate.is_equal_approx(frozen_modulate),
		"Hit-stop did not hold patrol timers, physics, and composed pose."
	)

	enemy.call("_update_hit_flash", enemy.hit_flash_duration)
	enemy.call("_apply_patrol_visual")
	_expect(
		is_zero_approx(enemy.hit_flash_time_remaining)
		and enemy.visual.modulate.is_equal_approx(visual_modulate_before)
		and enemy.visual.position.x < visual_position_before.x
		and enemy.visual.rotation < visual_rotation_before
		and enemy.visual.scale.x > visual_scale_x_before
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before)
		and is_equal_approx(_visual_foot_y(enemy), visual_foot_y_before),
		"Hit feedback did not preserve the patrol knockback pose."
	)

	enemy.knockback_time_remaining = 1.0 / 120.0
	enemy.velocity = Vector2(200.0, 0.0)
	enemy._physics_process(1.0 / 60.0)
	_expect(
		is_zero_approx(enemy.knockback_time_remaining)
		and is_zero_approx(enemy.patrol_animation_cycle)
		and is_zero_approx(enemy.patrol_turn_visual_time_remaining)
		and enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(enemy.visual.scale.x, visual_scale_x_before)
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before)
		and not enemy.transform.is_equal_approx(body_transform_before),
		"Natural knockback end reused an old walk or delayed turn pose."
	)

	enemy.transform = body_transform_before
	enemy.velocity = Vector2.ZERO
	enemy.patrol_animation_cycle = 0.0
	enemy.call("_apply_patrol_visual")
	_expect(
		enemy.visual.position.is_equal_approx(visual_position_before)
		and is_equal_approx(
			enemy.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(enemy.visual.scale.x, visual_scale_x_before)
		and is_equal_approx(enemy.visual.scale.y, visual_scale_y_before),
		"Patrol knockback recovery did not restore the neutral pose."
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
			edge_transform_before,
			edge_target_before,
			edge_enabled_before,
			edge_collision_mask_before
		),
		"Patrol animation changed body, collider, or edge-probe geometry."
	)
	_expect(
		is_equal_approx(enemy.patrol_speed, patrol_speed_before)
		and is_equal_approx(
			enemy.knockback_lock_time,
			knockback_lock_time_before
		)
		and is_equal_approx(enemy.knockback_drag, knockback_drag_before)
		and is_equal_approx(
			enemy.maximum_fall_speed,
			maximum_fall_speed_before
		)
		and is_equal_approx(enemy.gravity, gravity_before)
		and is_equal_approx(
			enemy.hit_flash_duration,
			hit_flash_duration_before
		)
		and is_equal_approx(enemy.hit_squash_y, hit_squash_y_before),
		"Patrol animation changed AI speed, knockback, or gravity values."
	)

	actors.queue_free()
	await process_frame


func _test_natural_wall_turn() -> void:
	var stage := Node2D.new()
	stage.name = "WallTurnStage"
	root.add_child(stage)
	_add_static_rectangle(
		stage,
		"Floor",
		Vector2(160.0, 210.0),
		Vector2(320.0, 20.0)
	)
	_add_static_rectangle(
		stage,
		"Wall",
		Vector2(220.0, 150.0),
		Vector2(20.0, 120.0)
	)

	var enemy := PATROL_ENEMY_SCENE.instantiate() as PatrolEnemy
	enemy.position = Vector2(190.0, 180.0)
	stage.add_child(enemy)
	enemy.patrol_direction = 1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_patrol_visual")

	var saw_floor := false
	var saw_turn := false
	for _frame in 20:
		await physics_frame
		saw_floor = saw_floor or enemy.is_on_floor()
		if (
			enemy.patrol_direction < 0.0
			and enemy.patrol_turn_visual_time_remaining > 0.0
		):
			saw_turn = true
			break

	if saw_turn:
		await physics_frame
	enemy.set_physics_process(false)
	_expect(
		saw_floor
		and saw_turn
		and enemy.patrol_direction < 0.0
		and enemy.velocity.x < 0.0
		and enemy.patrol_turn_visual_time_remaining > 0.0
		and enemy.visual.position.x
		> enemy.patrol_base_visual_position.x
		and enemy.visual.scale.x < 0.0,
		"Natural wall contact did not start a visual turn without AI delay."
	)

	enemy.position = Vector2(190.0, 180.0)
	enemy.velocity = Vector2.ZERO
	enemy.knockback_time_remaining = 0.0
	enemy.hit_flash_time_remaining = 0.0
	enemy.patrol_turn_visual_time_remaining = 0.0
	enemy.patrol_animation_cycle = 0.0
	enemy.patrol_direction = 1.0
	enemy.call("_sync_direction")
	enemy.call("_apply_hit_visual")
	enemy.call("_apply_patrol_visual")
	enemy.receive_impulse(Vector2(390.0, 0.0))
	enemy.set_physics_process(true)

	var hit_wall_during_knockback := false
	for _frame in 12:
		await physics_frame
		if enemy.is_on_wall():
			hit_wall_during_knockback = true
			break
	enemy.set_physics_process(false)
	_expect(
		hit_wall_during_knockback
		and enemy.knockback_time_remaining > 0.0
		and is_zero_approx(enemy.patrol_turn_visual_time_remaining),
		"Wall contact during knockback left a delayed turn pose."
	)

	stage.queue_free()
	await process_frame


func _test_child_compositor_guards() -> void:
	var actors := Node2D.new()
	actors.name = "ChildActors"
	root.add_child(actors)

	var scenes: Array[PackedScene] = [
		SHOVE_ENEMY_SCENE,
		SHOOTER_ENEMY_SCENE,
	]
	var children: Array[PatrolEnemy] = []
	for child_scene: PackedScene in scenes:
		var child := child_scene.instantiate() as PatrolEnemy
		child.set_physics_process(false)
		actors.add_child(child)
		children.append(child)
	await process_frame

	for child: PatrolEnemy in children:
		child.set_physics_process(false)
		child.visual.position += Vector2(7.0, -5.0)
		child.visual.rotation += 0.123
		child.visual.scale *= Vector2(1.07, 0.94)
		var sentinel_transform := child.visual.transform
		child.patrol_animation_cycle = PI * 0.5
		child.patrol_turn_visual_time_remaining = (
			child.patrol_turn_visual_time
		)
		child.call("_apply_patrol_visual")
		_expect(
			not bool(child.call("_uses_base_patrol_animation"))
			and child.visual.transform.is_equal_approx(
				sentinel_transform
			),
			"Base patrol compositor overwrote a child enemy pose."
		)

	actors.queue_free()
	await process_frame


func _add_static_rectangle(
	parent: Node2D,
	node_name: String,
	position: Vector2,
	size: Vector2
) -> void:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = position
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _visual_foot_y(enemy: PatrolEnemy) -> float:
	var lowest_y := -INF
	for foot_path: NodePath in [
		NodePath("Visual/FootLeft"),
		NodePath("Visual/FootRight"),
	]:
		var foot := enemy.get_node(foot_path) as Polygon2D
		for vertex: Vector2 in foot.polygon:
			var transformed := (
				enemy.visual.transform
				* (foot.transform * vertex)
			)
			lowest_y = maxf(lowest_y, transformed.y)
	return lowest_y


func _enemy_geometry_is_unchanged(
	enemy: PatrolEnemy,
	body_shape: CollisionShape2D,
	body_transform: Transform2D,
	collision_layer: int,
	collision_mask: int,
	body_shape_transform: Transform2D,
	body_shape_size: Vector2,
	edge_transform: Transform2D,
	edge_target: Vector2,
	edge_enabled: bool,
	edge_collision_mask: int
) -> bool:
	var body_rectangle := body_shape.shape as RectangleShape2D
	return (
		enemy.transform.is_equal_approx(body_transform)
		and enemy.collision_layer == collision_layer
		and enemy.collision_mask == collision_mask
		and body_shape.transform.is_equal_approx(body_shape_transform)
		and body_rectangle.size.is_equal_approx(body_shape_size)
		and enemy.edge_probe.transform.is_equal_approx(edge_transform)
		and enemy.edge_probe.target_position.is_equal_approx(edge_target)
		and enemy.edge_probe.enabled == edge_enabled
		and enemy.edge_probe.collision_mask == edge_collision_mask
	)

extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_ENEMY_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_attack_pose_lifecycle()

	if failures.is_empty():
		print("PLAYER_ATTACK_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_attack_pose_lifecycle() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var player := PLAYER_SCENE.instantiate() as Player
	var enemy := PATROL_ENEMY_SCENE.instantiate() as PatrolEnemy
	player.position = Vector2(120.0, 180.0)
	enemy.position = Vector2(220.0, 180.0)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	actors.add_child(player)
	actors.add_child(enemy)
	await process_frame
	player.set_physics_process(false)
	enemy.set_physics_process(false)

	var attack_shape := (
		player.attack_area.get_node("CollisionShape2D")
		as CollisionShape2D
	)
	var rectangle := attack_shape.shape as RectangleShape2D
	var area_transform_before := player.attack_area.transform
	var shape_transform_before := attack_shape.transform
	var area_position_before := player.attack_area.position
	var shape_size_before := rectangle.size
	var visual_position_before := player.visual.position
	var visual_rotation_before := player.visual.rotation
	var visual_scale_y_before := player.visual.scale.y
	var strike_scale_before := player.attack_visual.scale
	var strike_color_before := player.attack_visual.color

	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	player.call("_start_attack")
	_expect(
		is_equal_approx(
			player.attack_time_remaining,
			player.attack_active_time
		)
		and is_equal_approx(
			player.attack_cooldown_remaining,
			player.attack_cooldown
		)
		and player.attack_area.monitoring
		and player.attack_visual.visible,
		"Attack animation changed the attack start contract."
	)
	_expect(
		_attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Attack animation changed hitbox geometry."
	)

	player.call(
		"_update_attack_timers",
		player.attack_active_time * player.attack_anticipation_ratio
	)
	_expect(
		player.attack_pose_progress > 0.0
		and player.attack_pose_progress
		<= player.attack_anticipation_ratio + 0.001
		and player.visual.position.x < visual_position_before.x
		and player.visual.rotation < visual_rotation_before
		and player.visual.scale.y < visual_scale_y_before
		and player.attack_visual.scale.x < strike_scale_before.x
		and player.visual.scale.x == 1.0
		and player.attack_pivot.scale.x == 1.0,
		"Right-facing anticipation pose is missing or flipped."
	)

	player.call("_try_apply_impulse", enemy)
	_expect(
		player.attack_pose_progress
		>= player.attack_contact_ratio
		and player.visual.position.x > visual_position_before.x
		and player.visual.rotation > visual_rotation_before
		and player.visual.scale.y > visual_scale_y_before
		and player.attack_visual.scale.x > strike_scale_before.x
		and player.attack_visual.color.a
		== strike_color_before.a
		and _attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Successful hit did not snap to the contact pose."
	)

	var frozen_timer := player.attack_time_remaining
	var frozen_cooldown := player.attack_cooldown_remaining
	var frozen_visual_position := player.visual.position
	var frozen_visual_rotation := player.visual.rotation
	var frozen_strike_scale := player.attack_visual.scale
	for _frame in player.attack_hit_stop_frames:
		player._physics_process(1.0 / 60.0)
	_expect(
		is_equal_approx(player.attack_time_remaining, frozen_timer)
		and is_equal_approx(
			player.attack_cooldown_remaining,
			frozen_cooldown
		)
		and player.visual.position.is_equal_approx(
			frozen_visual_position
		)
		and is_equal_approx(
			player.visual.rotation,
			frozen_visual_rotation
		)
		and player.attack_visual.scale.is_equal_approx(
			frozen_strike_scale
		)
		and _attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Impact freeze changed attack timers, pose, or geometry."
	)

	var contact_progress := float(
		player.call("_attack_contact_point")
	)
	var recovery_progress := lerpf(contact_progress, 1.0, 0.5)
	var timer_progress := 1.0 - (
		player.attack_time_remaining / player.attack_active_time
	)
	player.call(
		"_update_attack_timers",
		(recovery_progress - timer_progress)
		* player.attack_active_time
	)
	_expect(
		player.attack_time_remaining > 0.0
		and player.attack_pose_progress > contact_progress
		and player.attack_pose_progress < 1.0
		and player.visual.position.x > visual_position_before.x
		and player.visual.position.x < frozen_visual_position.x
		and player.visual.rotation > visual_rotation_before
		and player.visual.rotation < frozen_visual_rotation
		and player.attack_visual.color.a > 0.0
		and player.attack_visual.color.a < strike_color_before.a
		and _attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Attack recovery did not ease back from the contact pose."
	)

	player.call(
		"_update_attack_timers",
		player.attack_time_remaining
	)
	_expect(
		is_zero_approx(player.attack_time_remaining)
		and is_zero_approx(player.attack_pose_progress)
		and not player.attack_area.monitoring
		and not player.attack_visual.visible
		and player.visual.position.is_equal_approx(
			visual_position_before
		)
		and is_equal_approx(
			player.visual.rotation,
			visual_rotation_before
		)
		and is_equal_approx(
			player.visual.scale.y,
			visual_scale_y_before
		)
		and player.attack_visual.scale.is_equal_approx(
			strike_scale_before
		)
		and player.attack_visual.color.is_equal_approx(
			strike_color_before
		)
		and _attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Attack recovery did not restore the base pose."
	)

	player.call("_start_attack")
	var late_hit_progress := lerpf(contact_progress, 1.0, 0.75)
	player.call(
		"_update_attack_timers",
		late_hit_progress * player.attack_active_time
	)
	var late_recovery_position := player.visual.position
	var late_recovery_rotation := player.visual.rotation
	_expect(
		player.attack_pose_progress > contact_progress,
		"Late-hit setup did not reach attack recovery."
	)
	player.call("_try_apply_impulse", enemy)
	_expect(
		is_equal_approx(
			player.attack_pose_progress,
			contact_progress
		)
		and player.visual.position.x > late_recovery_position.x
		and player.visual.rotation > late_recovery_rotation
		and player.attack_visual.color.a
		== strike_color_before.a
		and _attack_geometry_is_unchanged(
			player,
			attack_shape,
			area_transform_before,
			shape_transform_before,
			area_position_before,
			shape_size_before
		),
		"Late hit did not return to the full contact pose."
	)
	for _frame in player.attack_hit_stop_frames:
		player._physics_process(0.0)
	player.call("_finish_attack")

	player.facing_direction = 1.0
	player.visual.scale.x = 1.0
	player.attack_pivot.scale.x = 1.0
	player.call("_start_attack")
	player.call(
		"_update_attack_timers",
		player.attack_active_time * player.attack_anticipation_ratio
	)
	Input.action_press("ui_left")
	player._physics_process(0.0)
	Input.action_release("ui_left")
	_expect(
		player.facing_direction == -1.0
		and player.visual.position.x > visual_position_before.x
		and player.visual.rotation > visual_rotation_before
		and player.visual.scale.x == -1.0
		and player.attack_pivot.scale.x == -1.0,
		"Left-facing attack pose lost or doubled its facing sign."
	)
	player.call("_finish_attack")
	_expect(
		player.visual.scale.x == -1.0
		and player.attack_pivot.scale.x == -1.0
		and player.visual.position.is_equal_approx(
			visual_position_before
		),
		"Pose reset overwrote the player's facing direction."
	)

	actors.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _attack_geometry_is_unchanged(
	player: Player,
	attack_shape: CollisionShape2D,
	area_transform: Transform2D,
	shape_transform: Transform2D,
	area_position: Vector2,
	shape_size: Vector2
) -> bool:
	var rectangle := attack_shape.shape as RectangleShape2D
	return (
		player.attack_area.transform.is_equal_approx(area_transform)
		and attack_shape.transform.is_equal_approx(shape_transform)
		and player.attack_area.position.is_equal_approx(area_position)
		and rectangle.size.is_equal_approx(shape_size)
	)

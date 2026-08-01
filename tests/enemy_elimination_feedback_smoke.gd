extends SceneTree

const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_enemy_elimination_feedback()

	if failures.is_empty():
		print("ENEMY_ELIMINATION_FEEDBACK_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_enemy_elimination_feedback() -> void:
	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.level_path = "res://levels/arena_08.json"
	arena.clear_restart_delay = 0.2
	root.add_child(arena)
	await process_frame

	_expect(arena.level_loaded, "Arena 08 elimination fixture did not load.")
	if not arena.level_loaded:
		arena.queue_free()
		await process_frame
		return

	var feedback := arena.impact_feedback
	var hazard := arena.hazard_feedback as ArenaHazardFeedback
	var patrol := arena.get_level_object("patrol_1") as PatrolEnemy
	var shove := arena.get_level_object("shove_1") as ShoveEnemy
	var shooter := arena.get_level_object("shooter_1") as ShooterEnemy
	var player := arena.get_level_object("player_start") as Player
	var background := arena.get_node("Background") as Polygon2D
	var title := arena.get_node("UI/Title") as Label
	var pit_band := arena.get_node("PitBand") as Polygon2D
	var pit_edge := arena.get_node("PitEdge") as Line2D
	var death_shape_node := arena.get_node(
		"DeathZone/CollisionShape2D"
	) as CollisionShape2D
	var death_shape := death_shape_node.shape as RectangleShape2D

	feedback.play_audio_in_headless = true
	var time_scale_before := Engine.time_scale
	var background_transform := background.transform
	var title_position := title.global_position
	var death_zone_transform := arena.death_zone.transform
	var death_shape_transform := death_shape_node.transform
	var death_shape_size := death_shape.size
	var death_layer := arena.death_zone.collision_layer
	var death_mask := arena.death_zone.collision_mask
	var pit_band_transform := pit_band.transform
	var pit_band_polygon := pit_band.polygon
	var pit_edge_transform := pit_edge.transform
	var pit_edge_points := pit_edge.points
	var initial_status := arena.status_label.text
	var initial_generation := arena.outcome_generation
	var player_defeats: Array[int] = []
	var embedded_restart_requests: Array[bool] = []
	arena.embedded_restart_requested.connect(
		func() -> void:
			embedded_restart_requests.append(true)
	)
	player.defeated.connect(
		func(
			_player: Node2D,
			cause: int,
			_impact_direction: Vector2
		) -> void:
			player_defeats.append(cause)
	)
	player.set_physics_process(false)

	patrol.velocity = Vector2(150.0, 300.0)
	var patrol_position := patrol.global_position
	var patrol_direction := patrol.velocity.normalized()
	var patrol_color := (
		patrol.get_node("Visual/Body") as Polygon2D
	).color
	arena.death_zone.body_entered.emit(patrol)
	var first_bursts := _elimination_bursts(arena)
	var first_burst := (
		first_bursts[0]
		if not first_bursts.is_empty()
		else null
	) as EnemyEliminationBurst
	_expect(
		arena.enemies_remaining == 2
		and not patrol.is_in_group("enemies")
		and patrol.is_queued_for_deletion()
		and not player.is_clear_celebrating
		and not player.is_defeated
		and arena.pending_outcome == Arena.Outcome.NONE
		and arena.outcome_generation == initial_generation
		and arena.status_label.text == initial_status
		and feedback.elimination_count == 1
		and feedback.clear_count == 0
		and feedback.sound_play_count == 1
		and feedback.impact_count == 0
		and feedback.defeat_count == 0
		and feedback.last_elimination_position.is_equal_approx(
			patrol_position
		)
		and feedback.last_elimination_direction.is_equal_approx(
			patrol_direction
		)
		and not feedback.last_elimination_was_clear
		and feedback.camera.offset.is_equal_approx(
			-patrol_direction * feedback.elimination_shake_strength
		)
		and is_equal_approx(
			feedback.audio_player.volume_db,
			feedback.elimination_volume_db
		)
		and is_equal_approx(
			feedback.audio_player.pitch_scale,
			feedback.elimination_pitch_scale
		)
		and feedback.audio_player.playing
		and hazard.elimination_count == 1
		and hazard.clear_count == 0
		and hazard.alert_kind == ArenaHazardFeedback.AlertKind.ELIMINATION
		and first_bursts.size() == 1
		and is_instance_valid(first_burst)
		and first_burst.is_configured
		and not first_burst.clears_arena
		and first_burst.source_world_position.is_equal_approx(patrol_position)
		and first_burst.global_position.is_equal_approx(
			patrol_position + Vector2.UP * first_burst.visual_lift
		)
		and first_burst.fall_direction.is_equal_approx(patrol_direction)
		and first_burst.source_color.is_equal_approx(patrol_color),
		"First enemy elimination missed its single normal feedback preset."
	)

	arena.death_zone.body_entered.emit(patrol)
	_expect(
		arena.enemies_remaining == 2
		and arena.outcome_generation == initial_generation
		and feedback.elimination_count == 1
		and feedback.sound_play_count == 1
		and hazard.elimination_count == 1
		and _elimination_bursts(arena).size() == 1,
		"Duplicate DeathZone callback counted one enemy twice."
	)

	var burst_elapsed_before_pause := first_burst.elapsed
	paused = true
	await process_frame
	_expect(
		is_equal_approx(first_burst.elapsed, burst_elapsed_before_pause)
		and feedback.audio_player.stream_paused,
		"Pause advanced the world burst or failed to pause its sound."
	)
	for _frame in 12:
		await process_frame
	paused = false
	_expect(
		is_equal_approx(first_burst.elapsed, burst_elapsed_before_pause)
		and not feedback.is_shaking()
		and feedback.camera.offset.is_zero_approx(),
		"Camera did not settle independently while the world burst was paused."
	)

	player.locomotion_pose = Player.LocomotionPose.RUN
	player.run_cycle = PI * 0.5
	player.landing_time_remaining = player.landing_duration
	player.landing_strength = 1.0
	player.velocity = Vector2(player.move_speed, 0.0)
	player.call("_apply_locomotion_pose")
	player.call("_start_attack")
	shove.velocity = Vector2.ZERO
	var shove_position := shove.global_position
	arena.death_zone.body_entered.emit(shove)
	_expect(
		arena.enemies_remaining == 1
		and not player.is_clear_celebrating
		and not player.is_defeated
		and arena.pending_outcome == Arena.Outcome.NONE
		and arena.outcome_generation == initial_generation
		and feedback.elimination_count == 2
		and feedback.clear_count == 0
		and feedback.sound_play_count == 2
		and feedback.last_elimination_position.is_equal_approx(
			shove_position
		)
		and feedback.last_elimination_direction.is_equal_approx(
			Vector2.DOWN
		)
		and not feedback.last_elimination_was_clear
		and hazard.elimination_count == 2
		and hazard.clear_count == 0
		and player.attack_time_remaining > 0.0
		and player.attack_area.monitoring
		and player.attack_visual.visible
		and player.locomotion_pose == Player.LocomotionPose.RUN,
		"Zero-velocity elimination missed DOWN fallback or cleared too early."
	)

	player.jump_requested = true
	player.attack_requested = true
	player.velocity = Vector2(71.0, -23.0)
	player.knockback_time_remaining = 0.2
	player.impact_freeze_frames_remaining = 3
	var player_root_transform := player.transform
	var player_collision := player.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	var player_collision_transform := player_collision.transform
	var player_collision_size := (
		player_collision.shape as RectangleShape2D
	).size
	var player_collision_layer := player.collision_layer
	var player_collision_mask := player.collision_mask
	var attack_pivot_transform := player.attack_pivot.transform
	var attack_area_transform := player.attack_area.transform
	var attack_collision := player.get_node(
		"AttackPivot/AttackArea/CollisionShape2D"
	) as CollisionShape2D
	var attack_collision_transform := attack_collision.transform
	var attack_collision_size := (
		attack_collision.shape as RectangleShape2D
	).size
	var clear_origin_position := player.fall_visual_pivot.position
	var clear_origin_rotation := player.fall_visual_pivot.rotation
	var clear_origin_scale := player.fall_visual_pivot.scale
	var clear_origin_modulate := player.fall_visual_pivot.modulate
	var clear_duration_expected := minf(
		player.clear_celebration_time,
		arena.clear_restart_delay
	)
	shooter.velocity = Vector2(-120.0, 280.0)
	var shooter_position := shooter.global_position
	var shooter_direction := shooter.velocity.normalized()
	arena.death_zone.body_entered.emit(shooter)
	var all_bursts := _elimination_bursts(arena)
	var clear_burst: EnemyEliminationBurst
	for burst: EnemyEliminationBurst in all_bursts:
		if burst.clears_arena:
			clear_burst = burst
			break
	_expect(
		arena.enemies_remaining == 0
		and arena.restart_scheduled
		and not arena.advance_after_delay
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and arena.outcome_generation == initial_generation + 1
		and arena.status_label.text == arena.clear_message
		and player.is_clear_celebrating
		and not player.is_defeated
		and not player.is_falling_out
		and not player.is_combat_defeat_active
		and is_equal_approx(
			player.clear_celebration_duration,
			clear_duration_expected
		)
		and is_zero_approx(player.clear_celebration_elapsed)
		and not player.jump_requested
		and not player.attack_requested
		and is_zero_approx(player.attack_time_remaining)
		and not player.attack_area.monitoring
		and not player.attack_visual.visible
		and player.velocity.is_zero_approx()
		and is_zero_approx(player.knockback_time_remaining)
		and player.impact_freeze_frames_remaining == 0
		and player.locomotion_pose == Player.LocomotionPose.IDLE
		and is_zero_approx(player.locomotion_time)
		and is_zero_approx(player.run_cycle)
		and is_zero_approx(player.landing_time_remaining)
		and is_zero_approx(player.landing_strength)
		and player.visual.position.is_equal_approx(
			player.base_visual_position
		)
		and is_equal_approx(
			player.visual.rotation,
			player.base_visual_rotation
		)
		and is_equal_approx(
			player.visual.scale.y,
			player.base_visual_scale_y
		)
		and player.transform.is_equal_approx(player_root_transform)
		and not player.fall_visual_pivot.is_set_as_top_level()
		and player.clear_celebration_origin_position.is_equal_approx(
			clear_origin_position
		)
		and is_equal_approx(
			player.clear_celebration_origin_rotation,
			clear_origin_rotation
		)
		and player.clear_celebration_origin_scale.is_equal_approx(
			clear_origin_scale
		)
		and player.clear_celebration_origin_modulate.is_equal_approx(
			clear_origin_modulate
		)
		and player.fall_visual_pivot.position.is_equal_approx(
			clear_origin_position
			+ Vector2.DOWN
			* Player.VISUAL_HALF_HEIGHT
			* player.clear_celebration_entry_squash
		)
		and player.fall_visual_pivot.scale.x > clear_origin_scale.x
		and player.fall_visual_pivot.scale.y < clear_origin_scale.y
		and not player.fall_visual_pivot.modulate.is_equal_approx(
			clear_origin_modulate
		)
		and feedback.elimination_count == 3
		and feedback.clear_count == 1
		and feedback.sound_play_count == 3
		and feedback.last_elimination_position.is_equal_approx(
			shooter_position
		)
		and feedback.last_elimination_direction.is_equal_approx(
			shooter_direction
		)
		and feedback.last_elimination_was_clear
		and feedback.camera.offset.is_equal_approx(
			-shooter_direction * feedback.clear_shake_strength
		)
		and is_equal_approx(
			feedback.audio_player.volume_db,
			feedback.clear_volume_db
		)
		and is_equal_approx(
			feedback.audio_player.pitch_scale,
			feedback.clear_pitch_scale
		)
		and hazard.elimination_count == 3
		and hazard.clear_count == 1
		and hazard.alert_kind == ArenaHazardFeedback.AlertKind.CLEAR
		and is_instance_valid(clear_burst)
		and clear_burst.source_world_position.is_equal_approx(shooter_position)
		and clear_burst.global_position.is_equal_approx(
			shooter_position + Vector2.UP * clear_burst.visual_lift
		)
		and clear_burst.fall_direction.is_equal_approx(shooter_direction),
		"Last enemy did not produce one distinct clear preset and outcome."
	)

	var clear_generation := arena.outcome_generation
	var clear_status := arena.status_label.text
	var clear_duration := player.clear_celebration_duration
	arena.death_zone.body_entered.emit(shooter)
	_expect(
		arena.enemies_remaining == 0
		and arena.outcome_generation == clear_generation
		and feedback.elimination_count == 3
		and feedback.clear_count == 1
		and feedback.sound_play_count == 3
		and hazard.elimination_count == 3
		and hazard.clear_count == 1
		and _elimination_bursts(arena).size() == all_bursts.size(),
		"Repeated final callback restarted clear feedback or its timer."
	)
	var fall_count_before_race := hazard.fall_count
	var defeat_count_before_race := feedback.defeat_count
	var sound_count_before_race := feedback.sound_play_count
	var jump_event := InputEventKey.new()
	jump_event.pressed = true
	jump_event.physical_keycode = KEY_W
	player._input(jump_event)
	var attack_event := InputEventKey.new()
	attack_event.pressed = true
	attack_event.physical_keycode = KEY_X
	player._input(attack_event)
	player.call("_start_attack")
	player.begin_impact_freeze(6)
	player.receive_impulse(Vector2(900.0, -900.0))
	var accepted_combat_hit := player.receive_lethal_hit(
		Player.DefeatCause.COMBAT,
		Vector2.LEFT
	)
	var accepted_fall_hit := player.receive_lethal_hit(
		Player.DefeatCause.FALL,
		Vector2.DOWN
	)
	arena.death_zone.body_entered.emit(player)
	var late_projectile := ShooterProjectile.new()
	late_projectile.direction = Vector2.RIGHT
	late_projectile.call("_apply_impulse", player)
	late_projectile.free()
	arena.call(
		"_on_player_defeated",
		player,
		Player.DefeatCause.FALL,
		Vector2.DOWN
	)
	_expect(
		not accepted_combat_hit
		and not accepted_fall_hit
		and player_defeats.is_empty()
		and player.is_clear_celebrating
		and not player.is_defeated
		and not player.jump_requested
		and not player.attack_requested
		and is_zero_approx(player.attack_time_remaining)
		and not player.attack_area.monitoring
		and not player.attack_visual.visible
		and player.velocity.is_zero_approx()
		and is_zero_approx(player.knockback_time_remaining)
		and player.impact_freeze_frames_remaining == 0
		and player.transform.is_equal_approx(player_root_transform)
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and arena.outcome_generation == clear_generation
		and arena.status_label.text == clear_status
		and hazard.fall_count == fall_count_before_race
		and hazard.alert_kind == ArenaHazardFeedback.AlertKind.CLEAR
		and feedback.defeat_count == defeat_count_before_race
		and feedback.sound_play_count == sound_count_before_race,
		"Late input, impulse, pit, projectile, or defeat overrode CLEAR."
	)

	var immediate_pose := player.fall_visual_pivot.transform
	Input.action_press("ui_right")
	player._physics_process(clear_duration * 0.5)
	Input.action_release("ui_right")
	var midpoint_pose := player.fall_visual_pivot.transform
	_expect(
		is_equal_approx(
			player.clear_celebration_elapsed,
			clear_duration * 0.5
		)
		and not midpoint_pose.is_equal_approx(immediate_pose)
		and player.fall_visual_pivot.position.y < clear_origin_position.y
		and player.fall_visual_pivot.scale.x < clear_origin_scale.x
		and player.fall_visual_pivot.scale.y > clear_origin_scale.y
		and player.transform.is_equal_approx(player_root_transform)
		and player_collision.transform.is_equal_approx(
			player_collision_transform
		)
		and (
			player_collision.shape as RectangleShape2D
		).size.is_equal_approx(player_collision_size)
		and player.collision_layer == player_collision_layer
		and player.collision_mask == player_collision_mask
		and player.attack_pivot.transform.is_equal_approx(
			attack_pivot_transform
		)
		and player.attack_area.transform.is_equal_approx(
			attack_area_transform
		)
		and attack_collision.transform.is_equal_approx(
			attack_collision_transform
		)
		and (
			attack_collision.shape as RectangleShape2D
		).size.is_equal_approx(attack_collision_size),
		"Clear celebration failed to animate without moving gameplay geometry."
	)

	var celebration_elapsed_before_pause := player.clear_celebration_elapsed
	var celebration_pose_before_pause := player.fall_visual_pivot.transform
	var celebration_modulate_before_pause := player.fall_visual_pivot.modulate
	arena.embedded_mode = true
	player.set_physics_process(true)
	paused = true
	for _frame in 16:
		await process_frame
	_expect(
		is_equal_approx(
			player.clear_celebration_elapsed,
			celebration_elapsed_before_pause
		)
		and player.fall_visual_pivot.transform.is_equal_approx(
			celebration_pose_before_pause
		)
		and player.fall_visual_pivot.modulate.is_equal_approx(
			celebration_modulate_before_pause
		)
		and arena.outcome_generation == clear_generation
		and arena.pending_outcome == Arena.Outcome.CLEAR
		and embedded_restart_requests.is_empty(),
		"Pause advanced the clear celebration or its outcome timer."
	)
	paused = false
	player.set_physics_process(false)

	var duplicate_clear := player.begin_clear_celebration(
		arena.clear_restart_delay * 2.0
	)
	_expect(
		not duplicate_clear
		and is_equal_approx(
			player.clear_celebration_elapsed,
			celebration_elapsed_before_pause
		)
		and is_equal_approx(
			player.clear_celebration_duration,
			clear_duration
		)
		and player.fall_visual_pivot.transform.is_equal_approx(
			celebration_pose_before_pause
		),
		"Duplicate clear celebration reset its active pose or duration."
	)

	player._physics_process(clear_duration)
	var terminal_pose := player.fall_visual_pivot.transform
	var terminal_modulate := player.fall_visual_pivot.modulate
	_expect(
		player.is_clear_celebrating
		and is_equal_approx(
			player.clear_celebration_elapsed,
			clear_duration
		)
		and player.fall_visual_pivot.position.is_equal_approx(
			clear_origin_position
			+ Vector2.UP * player.clear_celebration_hold_lift
		)
		and is_equal_approx(
			player.fall_visual_pivot.rotation,
			clear_origin_rotation
		)
		and player.fall_visual_pivot.scale.is_equal_approx(
			clear_origin_scale * player.clear_celebration_end_scale
		)
		and not terminal_modulate.is_equal_approx(clear_origin_modulate)
		and player.transform.is_equal_approx(player_root_transform),
		"Clear celebration did not settle into its guarded terminal pose."
	)
	player._physics_process(clear_duration)
	_expect(
		is_equal_approx(
			player.clear_celebration_elapsed,
			clear_duration
		)
		and player.fall_visual_pivot.transform.is_equal_approx(terminal_pose)
		and player.fall_visual_pivot.modulate.is_equal_approx(
			terminal_modulate
		),
		"Clear celebration failed to hold its final protected pose."
	)

	_expect(
		is_equal_approx(Engine.time_scale, time_scale_before)
		and background.transform.is_equal_approx(background_transform)
		and title.global_position.is_equal_approx(title_position)
		and arena.death_zone.transform.is_equal_approx(death_zone_transform)
		and death_shape_node.transform.is_equal_approx(death_shape_transform)
		and death_shape.size.is_equal_approx(death_shape_size)
		and arena.death_zone.collision_layer == death_layer
		and arena.death_zone.collision_mask == death_mask
		and pit_band.transform.is_equal_approx(pit_band_transform)
		and pit_band.polygon == pit_band_polygon
		and pit_edge.transform.is_equal_approx(pit_edge_transform)
		and pit_edge.points == pit_edge_points,
		"Elimination feedback changed world, UI, or hazard geometry."
	)

	var player_ref: WeakRef = weakref(player)
	feedback.cancel_feedback()
	paused = true
	await _wait_real_milliseconds(80)
	arena.free()
	paused = false
	for _frame in 3:
		await process_frame
	_expect(
		player_ref.get_ref() == null
		and not is_instance_valid(clear_burst)
		and not is_instance_valid(feedback),
		"Runtime cleanup leaked elimination feedback nodes."
	)


func _elimination_bursts(
	arena: LevelRuntimeArena
) -> Array[EnemyEliminationBurst]:
	var bursts: Array[EnemyEliminationBurst] = []
	for child: Node in arena.get_node("Actors").get_children():
		if child is EnemyEliminationBurst:
			bursts.append(child as EnemyEliminationBurst)
	return bursts


func _wait_real_milliseconds(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

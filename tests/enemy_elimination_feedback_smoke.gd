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
	arena.clear_restart_delay = 10.0
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

	shove.velocity = Vector2.ZERO
	var shove_position := shove.global_position
	arena.death_zone.body_entered.emit(shove)
	_expect(
		arena.enemies_remaining == 1
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
		and hazard.clear_count == 0,
		"Zero-velocity elimination missed DOWN fallback or cleared too early."
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

	feedback.cancel_feedback()
	paused = true
	await _wait_real_milliseconds(80)
	arena.free()
	paused = false
	for _frame in 3:
		await process_frame
	_expect(
		not is_instance_valid(clear_burst)
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

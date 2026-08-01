extends SceneTree

const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_hazard_feedback_lifecycle()

	if failures.is_empty():
		print("HAZARD_FEEDBACK_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_hazard_feedback_lifecycle() -> void:
	var arena := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	arena.fall_restart_delay = 10.0
	var hazard := arena.get_node(
		"HazardFeedback"
	) as ArenaHazardFeedback
	hazard.set_process(false)
	root.add_child(arena)
	await process_frame

	_expect(arena.level_loaded, "Hazard fixture did not load.")
	if not arena.level_loaded:
		arena.queue_free()
		await process_frame
		return

	var player := arena.get_level_object("player_start") as Player
	player.set_physics_process(false)
	var pit_band := arena.get_node("PitBand") as Polygon2D
	var pit_edge := arena.get_node("PitEdge") as Line2D
	var death_shape_node := arena.death_zone.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	var death_shape := death_shape_node.shape as RectangleShape2D
	var player_shape_node := player.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	var player_shape := player_shape_node.shape as RectangleShape2D

	var pit_band_transform := pit_band.transform
	var pit_band_polygon := pit_band.polygon.duplicate()
	var pit_edge_transform := pit_edge.transform
	var pit_edge_points := pit_edge.points.duplicate()
	var death_zone_transform := arena.death_zone.transform
	var death_shape_transform := death_shape_node.transform
	var death_shape_size := death_shape.size
	var death_layer := arena.death_zone.collision_layer
	var death_mask := arena.death_zone.collision_mask
	var death_monitoring := arena.death_zone.monitoring
	var player_transform := player.transform
	var player_shape_transform := player_shape_node.transform
	var player_shape_size := player_shape.size
	var player_layer := player.collision_layer
	var player_mask := player.collision_mask
	var attack_pivot_transform := player.attack_pivot.transform
	var visual_transform := player.visual.transform
	var fall_delay := arena.fall_restart_delay
	var clear_delay := arena.clear_restart_delay
	var move_speed := player.move_speed
	var maximum_fall_speed := player.maximum_fall_speed
	var attack_active_time := player.attack_active_time
	var fall_spin := player.fall_spin_radians
	var fall_drop := player.fall_drop_distance
	var fall_end_scale := player.fall_end_scale
	var fall_end_alpha := player.fall_end_alpha
	var fall_entry_squash := player.fall_entry_squash

	var idle_width_before := pit_edge.width
	var idle_color_before := pit_edge.default_color
	hazard._process(1.0 / (4.0 * hazard.idle_frequency))
	_expect(
		pit_edge.width > idle_width_before
		and not pit_edge.default_color.is_equal_approx(
			idle_color_before
		)
		and pit_band.color.is_equal_approx(hazard.base_band_color)
		and pit_band.transform.is_equal_approx(pit_band_transform)
		and pit_band.polygon == pit_band_polygon
		and pit_edge.transform.is_equal_approx(pit_edge_transform)
		and pit_edge.points == pit_edge_points
		and arena.pending_outcome == Arena.Outcome.NONE
		and not player.is_falling_out,
		"Idle pit pulse changed geometry or gameplay state."
	)

	player.velocity = Vector2(-180.0, 360.0)
	var player_velocity := player.velocity
	var fall_global_before := player.fall_visual_pivot.global_transform
	var fall_modulate_before := player.fall_visual_pivot.modulate
	var generation_before := arena.outcome_generation
	arena.death_zone.body_entered.emit(player)
	_expect(
		arena.restart_scheduled
		and not arena.advance_after_delay
		and arena.pending_outcome == Arena.Outcome.FALL
		and arena.outcome_generation == generation_before + 1
		and arena.status_label.text == "ПАДЕНИЕ  /  ПЕРЕЗАПУСК..."
		and player.is_falling_out
		and is_equal_approx(player.fall_out_duration, fall_delay)
		and is_zero_approx(player.fall_out_elapsed)
		and player.fall_out_direction < 0.0
		and player.fall_visual_pivot.is_set_as_top_level()
		and player.fall_visual_pivot.global_position.is_equal_approx(
			fall_global_before.origin
		)
		and player.fall_visual_pivot.scale.x
		> fall_global_before.get_scale().x
		and player.fall_visual_pivot.scale.y
		< fall_global_before.get_scale().y
		and player.fall_visual_pivot.modulate.is_equal_approx(
			fall_modulate_before
		)
		and hazard.is_alerting
		and is_zero_approx(hazard.alert_elapsed)
		and pit_edge.width
		> hazard.base_edge_width + hazard.alert_width_boost
		and not pit_band.color.is_equal_approx(hazard.base_band_color),
		"First DeathZone entry did not start fall feedback immediately."
	)

	player.call("_update_fall_out_animation", fall_delay * 0.5)
	hazard._process(hazard.alert_duration * 0.5)
	var generation_mid := arena.outcome_generation
	var fall_elapsed_mid := player.fall_out_elapsed
	var fall_transform_mid := player.fall_visual_pivot.transform
	var alert_elapsed_mid := hazard.alert_elapsed
	var alert_width_mid := pit_edge.width
	var alert_band_mid := pit_band.color
	arena.death_zone.body_entered.emit(player)
	_expect(
		arena.outcome_generation == generation_mid
		and is_equal_approx(player.fall_out_elapsed, fall_elapsed_mid)
		and player.fall_visual_pivot.transform.is_equal_approx(
			fall_transform_mid
		)
		and is_equal_approx(hazard.alert_elapsed, alert_elapsed_mid)
		and is_equal_approx(pit_edge.width, alert_width_mid)
		and pit_band.color.is_equal_approx(alert_band_mid),
		"Repeated DeathZone entry restarted visual or outcome state."
	)

	var origin_scale := fall_global_before.get_scale()
	_expect(
		player.fall_visual_pivot.position.y
		> fall_global_before.origin.y
		and player.fall_visual_pivot.rotation
		< fall_global_before.get_rotation()
		and player.fall_visual_pivot.scale.x < origin_scale.x
		and player.fall_visual_pivot.scale.y < origin_scale.y
		and player.fall_visual_pivot.modulate.a
		<= fall_modulate_before.a
		and player.transform.is_equal_approx(player_transform)
		and player.velocity.is_equal_approx(player_velocity)
		and player.attack_pivot.transform.is_equal_approx(
			attack_pivot_transform
		)
		and player.visual.transform.is_equal_approx(visual_transform)
		and pit_edge.width > hazard.base_edge_width
		and not pit_band.color.is_equal_approx(hazard.base_band_color),
		"Fall midpoint changed physics or missed its visual pose."
	)

	hazard._process(hazard.alert_duration * 0.5)
	_expect(
		not hazard.is_alerting
		and is_equal_approx(
			hazard.alert_elapsed,
			hazard.alert_duration
		)
		and pit_band.color.is_equal_approx(hazard.base_band_color)
		and pit_edge.width
		<= hazard.base_edge_width + hazard.idle_width_boost,
		"Pit alert did not return to its idle visual after 180 ms."
	)

	player.call("_update_fall_out_animation", fall_delay * 0.5)
	_expect(
		is_equal_approx(player.fall_out_elapsed, fall_delay)
		and is_equal_approx(
			player.fall_visual_pivot.position.y,
			fall_global_before.origin.y + player.fall_drop_distance
		)
		and is_equal_approx(
			player.fall_visual_pivot.rotation,
			fall_global_before.get_rotation() - player.fall_spin_radians
		)
		and player.fall_visual_pivot.scale.is_equal_approx(
			origin_scale * player.fall_end_scale
		)
		and is_equal_approx(
			player.fall_visual_pivot.modulate.a,
			fall_modulate_before.a * player.fall_end_alpha
		),
		"Fall visual did not reach and hold its terminal pose."
	)

	_expect(
		arena.death_zone.transform.is_equal_approx(death_zone_transform)
		and death_shape_node.transform.is_equal_approx(
			death_shape_transform
		)
		and death_shape.size.is_equal_approx(death_shape_size)
		and arena.death_zone.collision_layer == death_layer
		and arena.death_zone.collision_mask == death_mask
		and arena.death_zone.monitoring == death_monitoring
		and player.transform.is_equal_approx(player_transform)
		and player_shape_node.transform.is_equal_approx(
			player_shape_transform
		)
		and player_shape.size.is_equal_approx(player_shape_size)
		and player.collision_layer == player_layer
		and player.collision_mask == player_mask
		and is_equal_approx(arena.fall_restart_delay, fall_delay)
		and is_equal_approx(arena.clear_restart_delay, clear_delay)
		and is_equal_approx(player.move_speed, move_speed)
		and is_equal_approx(
			player.maximum_fall_speed,
			maximum_fall_speed
		)
		and is_equal_approx(
			player.attack_active_time,
			attack_active_time
		)
		and is_equal_approx(player.fall_spin_radians, fall_spin)
		and is_equal_approx(player.fall_drop_distance, fall_drop)
		and is_equal_approx(player.fall_end_scale, fall_end_scale)
		and is_equal_approx(player.fall_end_alpha, fall_end_alpha)
		and is_equal_approx(
			player.fall_entry_squash,
			fall_entry_squash
		),
		"Hazard feedback changed collision, timing, or gameplay tuning."
	)

	var arena_ref: WeakRef = weakref(arena)
	var player_ref: WeakRef = weakref(player)
	arena.queue_free()
	await process_frame
	_expect(
		arena_ref.get_ref() == null and player_ref.get_ref() == null,
		"Hazard feedback did not clean up before its restart timer."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

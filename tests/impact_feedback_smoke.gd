extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_ENEMY_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)
const HINGE_SCENE := preload("res://scenes/hinge.tscn")
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)

var failures: Array[String] = []
var landed_target_ids: Array[int] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_enemy_hit_feedback()
	await _test_runtime_camera_and_sound()
	for _frame in 3:
		await process_frame

	if failures.is_empty():
		print("IMPACT_FEEDBACK_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_enemy_hit_feedback() -> void:
	var actors := Node2D.new()
	actors.name = "Actors"
	root.add_child(actors)

	var player := PLAYER_SCENE.instantiate() as Player
	var enemy := PATROL_ENEMY_SCENE.instantiate() as PatrolEnemy
	player.position = Vector2(100.0, 180.0)
	enemy.position = Vector2(220.0, 180.0)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	actors.add_child(player)
	actors.add_child(enemy)
	await process_frame

	player.attack_landed.connect(_on_attack_landed)
	player.facing_direction = 1.0
	player.attack_time_remaining = player.attack_active_time

	var enemy_position_before := enemy.global_position
	var player_position_before := player.global_position
	var base_modulate := enemy.base_visual_modulate
	var base_scale_y := enemy.base_visual_scale_y
	player.call("_try_apply_impulse", enemy)

	var expected_impulse := Vector2(
		player.attack_horizontal_impulse,
		player.attack_vertical_impulse
	)
	var bursts: Array[Node] = get_nodes_in_group("impact_feedback")
	var burst := (
		bursts[0] as ImpactBurst
		if bursts.size() == 1
		else null
	)
	_expect(
		landed_target_ids == [enemy.get_instance_id()],
		"Player hit did not emit exactly one attack_landed signal."
	)
	_expect(
		enemy.velocity.is_equal_approx(expected_impulse),
		"Enemy did not receive the configured player impulse."
	)
	_expect(
		player.is_impact_frozen()
		and enemy.is_impact_frozen()
		and player.impact_freeze_frames_remaining
		== player.attack_hit_stop_frames
		and enemy.impact_freeze_frames_remaining
		== player.attack_hit_stop_frames,
		"Player and enemy did not enter the same local impact freeze."
	)
	_expect(
		enemy.hit_flash_time_remaining > 0.0
		and not enemy.visual.modulate.is_equal_approx(base_modulate)
		and enemy.visual.scale.y < base_scale_y,
		"Enemy did not flash and squash immediately on impact."
	)
	_expect(
		is_instance_valid(burst)
		and burst.impact_direction.dot(
			expected_impulse.normalized()
		) > 0.999
		and burst.global_position.is_equal_approx(
			enemy_position_before
			- expected_impulse.normalized() * 12.0
		),
		"Directional impact burst is missing or misplaced."
	)

	player.call("_try_apply_impulse", enemy)
	_expect(
		landed_target_ids.size() == 1
		and get_nodes_in_group("impact_feedback").size() == 1,
		"One attack produced duplicate feedback for the same target."
	)

	for _frame in player.attack_hit_stop_frames:
		player._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		_expect(
			player.global_position.is_equal_approx(
				player_position_before
			)
			and enemy.global_position.is_equal_approx(
				enemy_position_before
			),
			"An impacted actor moved during the local freeze."
		)

	_expect(
		not player.is_impact_frozen()
		and not enemy.is_impact_frozen(),
		"Local impact freeze did not end after its frame budget."
	)

	enemy._physics_process(1.0 / 60.0)
	_expect(
		not enemy.global_position.is_equal_approx(
			enemy_position_before
		),
		"Enemy did not resume knockback after the local freeze."
	)

	for _frame in 12:
		enemy._physics_process(1.0 / 60.0)
	_expect(
		enemy.visual.modulate.is_equal_approx(base_modulate)
		and is_equal_approx(enemy.visual.scale.y, base_scale_y),
		"Enemy impact flash or squash did not restore its base visual."
	)

	if is_instance_valid(burst):
		burst._process(burst.duration)
	await process_frame
	_expect(
		get_nodes_in_group("impact_feedback").is_empty(),
		"Impact burst did not clean itself up."
	)

	var hinge := HINGE_SCENE.instantiate() as Hinge
	hinge.position = Vector2(320.0, 180.0)
	actors.add_child(hinge)
	player.call("_start_attack")
	player.call("_try_apply_impulse", hinge)
	_expect(
		landed_target_ids == [
			enemy.get_instance_id(),
			hinge.get_instance_id(),
		]
		and get_nodes_in_group("impact_feedback").size() == 1
		and not player.is_impact_frozen(),
		"Mechanism hit should show feedback without freezing actors."
	)

	actors.queue_free()
	await process_frame


func _test_runtime_camera_and_sound() -> void:
	var loaded: Dictionary = (
		LEVEL_STORAGE.load_builtin_level("arena_01_data")
	)
	_expect(
		bool(loaded.get("ok", false)),
		"Could not load the Arena 01 feedback fixture."
	)
	if not bool(loaded.get("ok", false)):
		return

	var level_data: Dictionary = loaded["data"].duplicate(true)
	for object: Dictionary in level_data.get("objects", []):
		if object.get("type", "") == "player_spawn":
			object["id"] = "custom_player"
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(level_data)
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode the custom-player feedback fixture."
	)
	if not bool(encoded.get("ok", false)):
		return

	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.process_mode = Node.PROCESS_MODE_DISABLED
	runtime.configure_embedded_snapshot(str(encoded["text"]))
	root.add_child(runtime)
	await process_frame
	_expect(runtime.level_loaded, "Feedback runtime did not load.")
	if not runtime.level_loaded:
		runtime.queue_free()
		await process_frame
		return

	var player := runtime.get_level_object("custom_player") as Player
	var enemy := runtime.get_level_object("patrol_1") as PatrolEnemy
	var feedback := runtime.impact_feedback
	_expect(
		is_instance_valid(player)
		and is_instance_valid(enemy)
		and is_instance_valid(feedback),
		"Runtime did not expose actors or impact feedback."
	)
	if (
		not is_instance_valid(player)
		or not is_instance_valid(enemy)
		or not is_instance_valid(feedback)
	):
		runtime.queue_free()
		await process_frame
		return

	player.set_physics_process(false)
	enemy.set_physics_process(false)
	feedback.play_audio_in_headless = true
	var world_anchor := runtime.get_node("Geometry/LeftWall") as Node2D
	var title := runtime.get_node("UI/Title") as Label
	var background := runtime.get_node("Background") as Polygon2D
	var pit_band := runtime.get_node("PitBand") as Polygon2D
	var world_position_before := world_anchor.global_position
	var title_position_before := title.global_position
	var player_position_before := player.global_position
	var enemy_position_before := enemy.global_position
	var expected_impulse := Vector2(
		player.attack_horizontal_impulse,
		player.attack_vertical_impulse
	)
	player.facing_direction = 1.0
	player.attack_time_remaining = player.attack_active_time
	player.call("_try_apply_impulse", enemy)

	var stream := feedback.audio_player.stream as AudioStreamWAV
	var expected_sample_count := roundi(
		feedback.sound_duration * float(feedback.sound_mix_rate)
	)
	_expect(
		feedback.impact_count == 1
		and feedback.sound_play_count == 1
		and feedback.last_impact_was_enemy
		and feedback.last_impact_direction.dot(
			expected_impulse.normalized()
		) > 0.999,
		"Runtime did not receive the directional enemy impact."
	)
	_expect(
		feedback.is_shaking()
		and root.get_camera_2d() == feedback.camera
		and feedback.camera.position.is_equal_approx(
			Vector2(480.0, 270.0)
		)
		and feedback.camera.offset.is_equal_approx(
			-expected_impulse.normalized()
			* feedback.enemy_shake_strength
		),
		"Enemy hit did not start the expected camera kick."
	)
	_expect(
		background.polygon[0].is_equal_approx(Vector2(-8.0, -8.0))
		and background.polygon[2].is_equal_approx(
			Vector2(968.0, 548.0)
		)
		and is_equal_approx(pit_band.polygon[2].y, 548.0),
		"Arena visuals do not cover the camera shake overscan."
	)
	_expect(
		is_instance_valid(stream)
		and stream.format == AudioStreamWAV.FORMAT_16_BITS
		and stream.mix_rate == feedback.sound_mix_rate
		and not stream.stereo
		and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED
		and stream.data.size() == expected_sample_count * 2
		and _has_non_zero_byte(stream.data)
		and feedback.audio_player.playing
		and is_equal_approx(
			feedback.audio_player.volume_db,
			feedback.enemy_volume_db
		)
		and is_equal_approx(
			feedback.audio_player.pitch_scale,
			feedback.enemy_pitch_scale
		),
		"Procedural enemy impact sound is missing or malformed."
	)
	_expect(
		world_anchor.global_position.is_equal_approx(
			world_position_before
		)
		and title.global_position.is_equal_approx(
			title_position_before
		)
		and player.global_position.is_equal_approx(
			player_position_before
		)
		and enemy.global_position.is_equal_approx(
			enemy_position_before
		),
		"Camera feedback changed world, UI, or actor transforms."
	)

	player.call("_try_apply_impulse", enemy)
	_expect(
		feedback.impact_count == 1
		and feedback.sound_play_count == 1,
		"One swing triggered duplicate camera or sound feedback."
	)

	var shake_time_before_pause := feedback.shake_time_remaining
	paused = true
	await process_frame
	_expect(
		feedback.shake_time_remaining < shake_time_before_pause
		and feedback.audio_player.stream_paused,
		"Pause did not settle the camera while pausing impact audio."
	)
	for _frame in 12:
		await process_frame
	paused = false
	_expect(
		not feedback.is_shaking()
		and feedback.camera.offset.is_zero_approx(),
		"Camera shake did not restore its zero offset during pause."
	)

	feedback.cancel_feedback()
	await _wait_real_milliseconds(80)
	player.impact_freeze_frames_remaining = 0
	var hinge := HINGE_SCENE.instantiate() as Hinge
	hinge.position = Vector2(400.0, 300.0)
	runtime.get_node("Actors").add_child(hinge)
	player.call("_start_attack")
	player.call("_try_apply_impulse", hinge)
	_expect(
		feedback.impact_count == 2
		and feedback.sound_play_count == 2
		and not feedback.last_impact_was_enemy
		and not player.is_impact_frozen()
		and is_equal_approx(
			feedback.camera.offset.length(),
			feedback.mechanism_shake_strength
		)
		and is_equal_approx(
			feedback.audio_player.volume_db,
			feedback.mechanism_volume_db
		)
		and is_equal_approx(
			feedback.audio_player.pitch_scale,
			feedback.mechanism_pitch_scale
		),
		"Mechanism hit did not use its lighter feedback preset."
	)

	await _wait_for_audio_stop(feedback.audio_player, 500)
	_expect(
		not feedback.audio_player.playing,
		"Procedural impact sound did not finish within its budget."
	)
	feedback.cancel_feedback()
	await _wait_real_milliseconds(80)
	player.call("_finish_attack")
	runtime.fall_restart_delay = 10.0
	var combat_direction := Vector2.LEFT
	var combat_root_position := player.global_position
	var combat_velocity := Vector2(63.0, -21.0)
	player.velocity = combat_velocity
	var combat_visual_transform := player.fall_visual_pivot.global_transform
	var combat_visual_modulate := player.fall_visual_pivot.modulate
	var generation_before_defeat := runtime.outcome_generation
	var time_scale_before_defeat := Engine.time_scale
	var accepted_defeat := player.receive_lethal_hit(
		Player.DefeatCause.COMBAT,
		combat_direction
	)
	var hazard_feedback := (
		runtime.hazard_feedback as ArenaHazardFeedback
	)
	_expect(
		accepted_defeat
		and feedback.impact_count == 2
		and feedback.defeat_count == 1
		and feedback.sound_play_count == 3
		and feedback.last_defeat_direction.is_equal_approx(
			combat_direction
		)
		and feedback.camera.offset.is_equal_approx(
			-combat_direction * feedback.defeat_shake_strength
		)
		and is_equal_approx(
			feedback.audio_player.volume_db,
			feedback.defeat_volume_db
		)
		and is_equal_approx(
			feedback.audio_player.pitch_scale,
			feedback.defeat_pitch_scale
		)
		and feedback.audio_player.playing
		and runtime.pending_outcome == Arena.Outcome.FALL
		and runtime.outcome_generation == generation_before_defeat + 1
		and runtime.status_label.text
		== "ПОРАЖЕНИЕ  /  ПЕРЕЗАПУСК..."
		and player.is_combat_defeat_active
		and not player.is_falling_out
		and player.fall_visual_pivot.is_set_as_top_level()
		and player.fall_visual_pivot.global_position.is_equal_approx(
			combat_visual_transform.origin
		)
		and player.fall_visual_pivot.scale.x
		> combat_visual_transform.get_scale().x
		and player.fall_visual_pivot.scale.y
		< combat_visual_transform.get_scale().y
		and not player.fall_visual_pivot.modulate.is_equal_approx(
			combat_visual_modulate
		)
		and not hazard_feedback.is_alerting
		and is_equal_approx(Engine.time_scale, time_scale_before_defeat),
		"Combat defeat did not start its distinct camera, audio, and pose."
	)

	var held_combat_transform := player.fall_visual_pivot.transform
	for _frame in player.combat_defeat_hit_stop_frames:
		player._physics_process(1.0 / 60.0)
		_expect(
			player.fall_visual_pivot.transform.is_equal_approx(
				held_combat_transform
			)
			and is_zero_approx(player.combat_defeat_elapsed),
			"Combat defeat pose advanced during its local hit-stop."
		)
	player._physics_process(player.combat_defeat_duration * 0.5)
	_expect(
		player.global_position.is_equal_approx(combat_root_position)
		and player.velocity.is_equal_approx(combat_velocity)
		and player.fall_visual_pivot.position.x
		< player.combat_defeat_origin_position.x
		and player.fall_visual_pivot.position.y
		< player.combat_defeat_origin_position.y
		and player.fall_visual_pivot.rotation
		< player.combat_defeat_origin_rotation
		and player.fall_visual_pivot.scale.x
		< player.combat_defeat_origin_scale.x
		and player.fall_visual_pivot.modulate.a
		< player.combat_defeat_origin_modulate.a,
		"Combat defeat midpoint missed its directional visual arc."
	)

	var duplicate_defeat := player.receive_lethal_hit(
		Player.DefeatCause.COMBAT,
		Vector2.DOWN
	)
	runtime.call(
		"_on_player_defeated",
		player,
		Player.DefeatCause.COMBAT,
		Vector2.DOWN
	)
	_expect(
		not duplicate_defeat
		and feedback.defeat_count == 1
		and feedback.sound_play_count == 3
		and runtime.outcome_generation == generation_before_defeat + 1
		and feedback.last_defeat_direction.is_equal_approx(
			combat_direction
		),
		"Repeated combat defeat restarted feedback or the outcome timer."
	)
	feedback._process(feedback.shake_duration)
	await _wait_for_audio_stop(feedback.audio_player, 500)
	_expect(
		not feedback.is_shaking()
		and feedback.camera.offset.is_zero_approx()
		and not feedback.audio_player.playing,
		"Combat defeat feedback did not settle before cleanup."
	)
	feedback.cancel_feedback()
	await _wait_real_milliseconds(80)
	stream = null
	runtime.free()
	for _frame in 3:
		await process_frame
	_expect(
		root.get_camera_2d() == null,
		"Runtime camera remained active after feedback cleanup."
	)


func _on_attack_landed(
	target: Node2D,
	_impact_position: Vector2,
	_impulse: Vector2
) -> void:
	landed_target_ids.append(target.get_instance_id())


func _has_non_zero_byte(data: PackedByteArray) -> bool:
	for byte: int in data:
		if byte != 0:
			return true
	return false


func _wait_for_audio_stop(
	player: AudioStreamPlayer,
	timeout_msec: int
) -> void:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while player.playing and Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_real_milliseconds(duration_msec: int) -> void:
	var deadline := Time.get_ticks_msec() + duration_msec
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

extends SceneTree

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PATROL_ENEMY_SCENE := preload(
	"res://scenes/patrol_enemy.tscn"
)
const HINGE_SCENE := preload("res://scenes/hinge.tscn")

var failures: Array[String] = []
var landed_target_ids: Array[int] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_enemy_hit_feedback()

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


func _on_attack_landed(
	target: Node2D,
	_impact_position: Vector2
) -> void:
	landed_target_ids.append(target.get_instance_id())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

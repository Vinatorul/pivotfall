extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_schema_and_round_trip()
	await _test_builder_collision_and_hinge()
	await _test_editor_vertical_slice()

	if failures.is_empty():
		print("TOGGLE_WALL_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_schema_and_round_trip() -> void:
	var source := _make_level()
	var wall := _object_by_id(source, "gate")
	wall.erase("starts_active")
	var validation: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(source)
	)
	_expect(
		bool(validation.get("ok", false)),
		"Validator rejected a valid toggle_wall with a forward hinge link: %s"
		% [validation.get("errors", [])]
	)
	if not bool(validation.get("ok", false)):
		return

	var canonical_wall := _object_by_id(validation["data"], "gate")
	_expect(
		canonical_wall.get("type") == "toggle_wall"
		and canonical_wall.get("rect") == [460, 300, 20, 160]
		and canonical_wall.get("starts_active") == true,
		"toggle_wall did not normalize rect and omitted starts_active."
	)
	var canonical_keys: Array = canonical_wall.keys()
	canonical_keys.sort()
	_expect(
		canonical_keys == ["id", "rect", "starts_active", "type"],
		"toggle_wall canonical keys drifted: %s" % [canonical_keys]
	)

	var encoded_once: Dictionary = LEVEL_DATA_CODEC.encode(
		validation["data"]
	)
	var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
		str(encoded_once.get("text", ""))
	)
	var encoded_twice: Dictionary = LEVEL_DATA_CODEC.encode(
		decoded.get("data", {})
	)
	_expect(
		bool(encoded_once.get("ok", false))
		and bool(decoded.get("ok", false))
		and bool(encoded_twice.get("ok", false))
		and encoded_once.get("text") == encoded_twice.get("text"),
		"toggle_wall JSON did not survive a deterministic import/export round trip."
	)

	var wrong_width := _make_level()
	_object_by_id(wrong_width, "gate")["rect"] = [460, 300, 40, 160]
	_expect_invalid_with(
		wrong_width,
		"width must be exactly 20",
		"toggle_wall with non-canonical width"
	)

	var short_wall := _make_level()
	_object_by_id(short_wall, "gate")["rect"] = [460, 300, 20, 19]
	_expect_invalid_with(
		short_wall,
		"height must be at least 20",
		"toggle_wall shorter than its minimum height"
	)

	var invalid_state := _make_level()
	_object_by_id(invalid_state, "gate")["starts_active"] = "yes"
	_expect_invalid_with(
		invalid_state,
		"starts_active must be a boolean",
		"toggle_wall with a non-boolean start state"
	)

	var unknown_property := _make_level()
	_object_by_id(unknown_property, "gate")["rotation"] = 90
	_expect_invalid_with(
		unknown_property,
		"unknown key 'rotation'",
		"toggle_wall with an open-ended property"
	)

	var outside_playfield := _make_level()
	_object_by_id(outside_playfield, "gate")["rect"] = [20, 300, 20, 160]
	_expect_invalid_with(
		outside_playfield,
		"runtime playfield",
		"toggle_wall outside the runtime playfield"
	)

	var overlapping_actor := _make_level()
	_object_by_id(overlapping_actor, "player_start")["position"] = [470, 340]
	_expect_invalid_with(
		overlapping_actor,
		"overlap toggle_wall 'gate'",
		"actor spawn inside an active toggle_wall"
	)


func _test_builder_collision_and_hinge() -> void:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(_make_level())
	_expect(
		bool(encoded.get("ok", false)),
		"Could not encode the toggle_wall runtime fixture: %s"
		% [encoded.get("errors", [])]
	)
	if not bool(encoded.get("ok", false)):
		return

	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded["text"]))
	root.add_child(runtime)
	await process_frame
	await physics_frame

	var wall := runtime.get_level_object("gate") as TogglePlatform
	var hinge := runtime.get_level_object("gate_hinge") as Hinge
	var collision_shape := (
		wall.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if is_instance_valid(wall)
		else null
	)
	var rectangle := (
		collision_shape.shape as RectangleShape2D
		if is_instance_valid(collision_shape)
		else null
	)
	_expect(
		runtime.level_loaded
		and runtime.load_errors.is_empty()
		and is_instance_valid(wall)
		and wall.is_vertical_wall
		and wall.position.is_equal_approx(Vector2(470, 380))
		and is_instance_valid(rectangle)
		and rectangle.size.is_equal_approx(Vector2(20, 160))
		and not collision_shape.one_way_collision,
		"Builder did not create a full-collision 20x160 vertical wall."
	)
	_expect(
		is_instance_valid(hinge)
		and hinge.target == wall
		and is_instance_valid(
			runtime.get_node_or_null(
				"Geometry/LevelObjects/Link_gate_hinge"
			)
		),
		"Builder did not resolve the forward hinge -> toggle_wall link."
	)

	if is_instance_valid(wall):
		var probe := _make_probe()
		runtime.add_child(probe)
		await physics_frame
		_expect(
			_probe_hits(probe, Vector2(440, 380), Vector2(60, 0))
			and _probe_hits(probe, Vector2(500, 380), Vector2(-60, 0))
			and _probe_hits(probe, Vector2(470, 280), Vector2(0, 60))
			and _probe_hits(probe, Vector2(470, 480), Vector2(0, -60)),
			"Active toggle_wall did not block a body from all four sides."
		)

		wall.transition_time = 0.01
		if is_instance_valid(hinge):
			hinge.cooldown = 0.01
			hinge.receive_impulse(Vector2.RIGHT)
		for _frame in range(20):
			await process_frame
			await physics_frame
			if not wall.is_transitioning:
				break
		_expect(
			not wall.is_active
			and collision_shape.disabled
			and not _probe_hits(
				probe,
				Vector2(440, 380),
				Vector2(60, 0)
			),
			"Hinge did not open the wall and remove its side collision."
		)
		probe.queue_free()
		await probe.tree_exited

		await _test_wall_ejection(runtime, wall, hinge, collision_shape)
		await _test_blocked_wall(runtime, wall, hinge, collision_shape)

	runtime.queue_free()
	await runtime.tree_exited


func _test_wall_ejection(
	runtime: LevelRuntimeArena,
	wall: TogglePlatform,
	hinge: Hinge,
	collision_shape: CollisionShape2D
) -> void:
	var player := runtime.get_level_object("player_start") as Player
	var enemy := runtime.get_level_object("patrol_1") as PatrolEnemy
	var center_probe := _make_probe()
	center_probe.name = "CenterVelocityProbe"
	center_probe.velocity = Vector2.LEFT
	runtime.add_child(center_probe)
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	player.global_position = Vector2(466, 340)
	enemy.global_position = Vector2(474, 420)
	center_probe.global_position = Vector2(470, 380)
	await physics_frame
	await process_frame

	var ejection_event := {"count": 0}
	wall.bodies_ejected.connect(
		func(count: int) -> void:
			ejection_event["count"] = count
	)
	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame

	_expect(
		wall.is_active
		and not collision_shape.disabled
		and int(ejection_event["count"]) == 3,
		(
			"Closing wall did not eject every overlapping character "
			+ "body: active=%s disabled=%s count=%s."
			% [
				wall.is_active,
				collision_shape.disabled,
				ejection_event["count"],
			]
		)
	)
	_expect(
		player.global_position.x < 450
		and player.velocity.x < 0
		and enemy.global_position.x > 490
		and enemy.velocity.x > 0,
		"Wall did not eject player and enemy toward their nearest sides."
	)
	_expect(
		center_probe.global_position.x < 455
		and center_probe.velocity.x < 0,
		(
			"Centered body did not use its velocity as the ejection "
			+ "tie-break: position=%s velocity=%s."
			% [center_probe.global_position, center_probe.velocity]
		)
	)

	center_probe.queue_free()
	await center_probe.tree_exited
	player.set_physics_process(true)
	enemy.set_physics_process(true)


func _test_blocked_wall(
	runtime: LevelRuntimeArena,
	wall: TogglePlatform,
	hinge: Hinge,
	collision_shape: CollisionShape2D
) -> void:
	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame
	_expect(
		not wall.is_active and collision_shape.disabled,
		"Wall did not reopen before the blocked-close scenario."
	)

	wall.blocked_feedback_time = 0.01
	var fallback_probe := _make_probe()
	fallback_probe.name = "FallbackProbe"
	fallback_probe.global_position = Vector2(466, 340)
	var fallback_blocker := _make_blocker(Vector2(449, 340))
	runtime.add_child(fallback_probe)
	runtime.add_child(fallback_blocker)
	await physics_frame
	await process_frame
	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame
	_expect(
		wall.is_active
		and not collision_shape.disabled
		and fallback_probe.global_position.x > 485
		and fallback_probe.velocity.x > 0,
		(
			"Wall did not use the opposite side when the preferred "
			+ "exit was blocked: active=%s position=%s velocity=%s."
			% [
				wall.is_active,
				fallback_probe.global_position,
				fallback_probe.velocity,
			]
		)
	)
	fallback_probe.queue_free()
	fallback_blocker.queue_free()
	await fallback_probe.tree_exited
	await fallback_blocker.tree_exited

	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame
	_expect(
		not wall.is_active and collision_shape.disabled,
		"Wall did not reopen before the atomic-cancel scenario."
	)

	var blocked_event := {"count": 0}
	wall.toggle_blocked.connect(
		func() -> void:
			blocked_event["count"] = int(blocked_event["count"]) + 1
	)
	var trapped_probe := _make_probe()
	trapped_probe.name = "TrappedProbe"
	trapped_probe.global_position = Vector2(466, 340)
	var free_probe := _make_probe()
	free_probe.name = "AtomicFreeProbe"
	free_probe.global_position = Vector2(474, 420)
	var left_blocker := _make_blocker(Vector2(449, 340))
	var right_blocker := _make_blocker(Vector2(491, 340))
	runtime.add_child(trapped_probe)
	runtime.add_child(free_probe)
	runtime.add_child(left_blocker)
	runtime.add_child(right_blocker)
	await physics_frame
	await process_frame
	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame

	_expect(
		not wall.is_active
		and collision_shape.disabled
		and int(blocked_event["count"]) == 1
		and trapped_probe.global_position.is_equal_approx(
			Vector2(466, 340)
		)
		and free_probe.global_position.is_equal_approx(
			Vector2(474, 420)
		),
		(
			"Wall partially closed or moved a body blocked on both "
			+ "sides: active=%s disabled=%s blocked=%s position=%s."
			% [
				wall.is_active,
				collision_shape.disabled,
				blocked_event["count"],
				trapped_probe.global_position,
			]
		)
	)
	await _wait_for_hinge_ready(hinge)
	_expect(
		hinge.is_ready,
		"Blocked close left its hinge permanently locked."
	)

	trapped_probe.queue_free()
	free_probe.queue_free()
	left_blocker.queue_free()
	right_blocker.queue_free()
	await trapped_probe.tree_exited
	await free_probe.tree_exited
	await left_blocker.tree_exited
	await right_blocker.tree_exited
	await physics_frame
	hinge.receive_impulse(Vector2.RIGHT)
	await _wait_for_wall_transition(wall)
	await physics_frame
	_expect(
		wall.is_active and not collision_shape.disabled,
		"Hinge could not retry after a blocked wall close."
	)


func _wait_for_wall_transition(wall: TogglePlatform) -> void:
	for _frame in range(60):
		await process_frame
		await physics_frame
		if not wall.is_transitioning:
			return
	_expect(false, "toggle_wall transition did not finish.")


func _wait_for_hinge_ready(hinge: Hinge) -> void:
	for _frame in range(60):
		await process_frame
		await physics_frame
		if hinge.is_ready:
			return
	_expect(false, "toggle_wall hinge did not unlock.")


func _test_editor_vertical_slice() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		is_instance_valid(editor.wall_button)
		and editor.wall_button.text == "0  ВОРОТА",
		"Editor did not expose the toggle_wall palette button."
	)
	await _press_physical_key(KEY_0)
	_expect(
		editor.active_tool == "toggle_wall"
		and editor.wall_button.button_pressed,
		"Physical 0 did not select the toggle_wall tool."
	)

	var drag_rect: Array = editor.canvas.call(
		"_toggle_wall_rect_from_drag",
		Vector2(460, 420),
		Vector2(700, 220)
	)
	var default_rect: Array = editor.canvas.call(
		"_default_rect",
		Vector2(950, 500),
		"toggle_wall"
	)
	_expect(
		drag_rect == [460, 220, 20, 200]
		and default_rect == [940, 380, 20, 160],
		"Editor toggle_wall drag/default helpers lost vertical geometry: %s / %s"
		% [drag_rect, default_rect]
	)

	editor.call("_place_object", "toggle_wall", [460, 300, 20, 160])
	var wall_id := editor.selected_id
	var placed := editor.draft.find_object(wall_id)
	_expect(
		placed.get("type") == "toggle_wall"
		and placed.get("rect") == [460, 300, 20, 160]
		and placed.get("starts_active") == true,
		"Editor did not create a canonical toggle_wall draft object."
	)

	editor.call("_place_object", "hinge", [420, 450])
	var hinge_id := editor.selected_id
	editor.call("_on_link_target_requested", wall_id)
	var linked_hinge := editor.draft.find_object(hinge_id)
	_expect(
		linked_hinge.get("type") == "hinge"
		and linked_hinge.get("target_id") == wall_id
		and bool(editor.validation_result.get("ok", false)),
		"Editor did not link a hinge to the placed toggle_wall."
	)

	editor.call("_start_playtest")
	await process_frame
	await physics_frame
	var playtest := editor.playtest_runtime as LevelRuntimeArena
	var playtest_wall := (
		playtest.get_level_object(wall_id) as TogglePlatform
		if is_instance_valid(playtest)
		else null
	)
	_expect(
		is_instance_valid(playtest)
		and playtest.level_loaded
		and is_instance_valid(playtest_wall)
		and playtest_wall.is_vertical_wall
		and not (
			playtest_wall.get_node("CollisionShape2D") as CollisionShape2D
		).one_way_collision,
		"Editor playtest did not preserve the toggle_wall runtime contract."
	)
	if is_instance_valid(playtest):
		editor.call("_stop_playtest")
		await process_frame

	current_scene = null
	editor.queue_free()
	await editor.tree_exited


func _make_level() -> Dictionary:
	return {
		"schema_version": 1,
		"level_id": "toggle_wall_smoke",
		"title": "TOGGLE WALL SMOKE",
		"objective": "OPEN THE GATE",
		"clear_message": "CLEAR",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "left_floor",
				"type": "solid_rect",
				"rect": [32, 496, 368, 44],
			},
			{
				"id": "right_floor",
				"type": "solid_rect",
				"rect": [560, 496, 368, 44],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [150, 450],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [320, 450],
				"speed": 0,
				"direction": 1,
			},
			{
				"id": "gate_hinge",
				"type": "hinge",
				"position": [420, 450],
				"target_id": "gate",
			},
			{
				"id": "gate",
				"type": "toggle_wall",
				"rect": [460, 300, 20, 160],
				"starts_active": true,
			},
		],
	}


func _make_probe() -> CharacterBody2D:
	var probe := CharacterBody2D.new()
	probe.name = "WallCollisionProbe"
	probe.collision_layer = 2
	probe.collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 8)
	collision.shape = shape
	probe.add_child(collision)
	return probe


func _make_blocker(
	position: Vector2,
	size := Vector2(12, 40)
) -> StaticBody2D:
	var blocker := StaticBody2D.new()
	blocker.position = position
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	blocker.add_child(collision)
	return blocker


func _probe_hits(
	probe: CharacterBody2D,
	from: Vector2,
	motion: Vector2
) -> bool:
	probe.global_position = from
	return probe.move_and_collide(motion, true) != null


func _object_by_id(data: Dictionary, object_id: String) -> Dictionary:
	for object: Dictionary in data.get("objects", []):
		if object.get("id", "") == object_id:
			return object
	return {}


func _expect_invalid_with(
	data: Dictionary,
	expected_text: String,
	label: String
) -> void:
	var result: Dictionary = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	)
	_expect(
		not bool(result.get("ok", false))
		and _contains_text(result.get("errors", []), expected_text),
		"Validator accepted %s or returned the wrong error: %s"
		% [label, result.get("errors", [])]
	)


func _contains_text(messages: Array, expected_text: String) -> bool:
	for message: Variant in messages:
		if expected_text in str(message):
			return true
	return false


func _press_physical_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	await physics_frame

	var release := InputEventKey.new()
	release.physical_keycode = key
	release.keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

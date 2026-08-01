extends SceneTree

const HINGE_SCENE := preload("res://scenes/hinge.tscn")
const TOGGLE_SCENE := preload("res://scenes/toggle_platform.tscn")
const ROTATING_SCENE := preload("res://scenes/rotating_platform.tscn")
const VERTICAL_SCENE := preload("res://scenes/vertical_platform.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_hinge_and_toggle_feedback()
	await _test_rotating_warning_pulse()
	await _test_vertical_warning_pulse()

	if failures.is_empty():
		print("MECHANISM_ANIMATION_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_hinge_and_toggle_feedback() -> void:
	var toggle := TOGGLE_SCENE.instantiate() as TogglePlatform
	toggle.transition_time = 10.0
	toggle.configure(Rect2(220.0, 180.0, 160.0, 20.0), true)

	var accepted := HINGE_SCENE.instantiate() as Hinge
	accepted.cooldown = 10.0
	accepted.configure_target(toggle)
	var rejected := HINGE_SCENE.instantiate() as Hinge
	rejected.configure_target(toggle)
	var unlinked := HINGE_SCENE.instantiate() as Hinge

	root.add_child(toggle)
	root.add_child(accepted)
	root.add_child(rejected)
	root.add_child(unlinked)
	for node: Node in [toggle, accepted, rejected, unlinked]:
		node.set_process(false)
	await process_frame
	for node: Node in [toggle, accepted, rejected, unlinked]:
		node.set_process(false)

	var hinge_shape_node := (
		accepted.get_node("CollisionShape2D") as CollisionShape2D
	)
	var hinge_shape := hinge_shape_node.shape as CircleShape2D
	var hinge_root_before := accepted.transform
	var hinge_layer_before := accepted.collision_layer
	var hinge_mask_before := accepted.collision_mask
	var hinge_shape_transform_before := hinge_shape_node.transform
	var hinge_radius_before := hinge_shape.radius
	var outer_before := accepted.outer_visual.transform
	var inner_before := accepted.inner_visual.transform
	var toggle_root_before := toggle.transform
	var toggle_shape_node := toggle.collision_shape
	var toggle_shape := toggle_shape_node.shape as RectangleShape2D
	var toggle_shape_transform_before := toggle_shape_node.transform
	var toggle_shape_size_before := toggle_shape.size
	var toggle_body_transform_before := toggle.body_visual.transform
	var toggle_edge_transform_before := toggle.edge_visual.transform
	var toggle_outline_transform_before := toggle.outline.transform
	var toggle_base_width := toggle.outline.width
	var toggles: Array[bool] = []
	toggle.toggled.connect(func(active: bool) -> void: toggles.append(active))

	accepted.receive_impulse(Vector2(390.0, -170.0))
	_expect(
		not accepted.is_ready
		and not accepted.cooldown_finished
		and not accepted.target_finished
		and is_equal_approx(
			accepted.press_visual_time_remaining,
			accepted.press_visual_time
		)
		and accepted.press_visual_direction == 1.0
		and accepted.outer_visual.position.x
		> accepted.outer_base_position.x
		and accepted.outer_visual.rotation
		> accepted.outer_base_rotation
		and accepted.outer_visual.scale.x
		> accepted.outer_base_scale.x
		and accepted.outer_visual.scale.y
		< accepted.outer_base_scale.y
		and accepted.inner_visual.rotation
		< accepted.inner_base_rotation
		and accepted.outer_visual.color
		== Hinge.ACCEPTED_OUTER_COLOR
		and accepted.inner_visual.color
		== Hinge.ACCEPTED_INNER_COLOR,
		"Accepted hinge hit did not start its immediate press pose."
	)
	_expect(
		toggle.is_transitioning
		and toggle.warning_pulse.active
		and is_zero_approx(toggle.warning_pulse.elapsed)
		and is_equal_approx(
			toggle.warning_pulse.duration,
			toggle.transition_time
		)
		and toggle.outline.width > toggle_base_width
		and toggle.body_visual.color == TogglePlatform.WARNING_COLOR
		and toggle.edge_visual.color == TogglePlatform.WARNING_COLOR
		and toggles.is_empty(),
		"Accepted hinge hit did not start the toggle warning pulse."
	)

	accepted._process(accepted.press_visual_time * 0.5)
	_expect(
		is_equal_approx(
			accepted.press_visual_time_remaining,
			accepted.press_visual_time * 0.5
		)
		and accepted.locked_visual_cycle > 0.0
		and accepted.outer_visual.position.x
		< accepted.outer_base_position.x + 2.5
		and accepted.outer_visual.position.x
		> accepted.outer_base_position.x,
		"Hinge press pose did not decay while its locked pulse advanced."
	)
	var busy_timer := accepted.press_visual_time_remaining
	var busy_cycle := accepted.locked_visual_cycle
	var busy_outer := accepted.outer_visual.transform
	var busy_inner := accepted.inner_visual.transform
	accepted.receive_impulse(Vector2(-390.0, -170.0))
	_expect(
		is_equal_approx(
			accepted.press_visual_time_remaining,
			busy_timer
		)
		and is_equal_approx(accepted.locked_visual_cycle, busy_cycle)
		and accepted.outer_visual.transform.is_equal_approx(busy_outer)
		and accepted.inner_visual.transform.is_equal_approx(busy_inner)
		and accepted.press_visual_direction == 1.0,
		"Busy hinge hit restarted or replaced the accepted press."
	)

	var pulse_elapsed := toggle.warning_pulse.elapsed
	var pulse_width := toggle.outline.width
	var rejected_outer_before := rejected.outer_visual.transform
	var unlinked_outer_before := unlinked.outer_visual.transform
	rejected.receive_impulse(Vector2(-390.0, -170.0))
	unlinked.receive_impulse(Vector2(390.0, -170.0))
	_expect(
		rejected.is_ready
		and unlinked.is_ready
		and is_zero_approx(rejected.press_visual_time_remaining)
		and is_zero_approx(unlinked.press_visual_time_remaining)
		and rejected.outer_visual.transform.is_equal_approx(
			rejected_outer_before
		)
		and unlinked.outer_visual.transform.is_equal_approx(
			unlinked_outer_before
		)
		and rejected.outer_visual.color == Hinge.READY_OUTER_COLOR
		and unlinked.outer_visual.color == Hinge.READY_OUTER_COLOR
		and is_equal_approx(toggle.warning_pulse.elapsed, pulse_elapsed)
		and is_equal_approx(toggle.outline.width, pulse_width),
		"Rejected-target or unlinked hinge hit produced visual feedback."
	)

	var toggle_body_color := toggle.body_visual.color
	var toggle_edge_color := toggle.edge_visual.color
	var toggle_outline_color := toggle.outline.default_color
	var toggle_state_before := toggle.is_active
	var toggle_pending_before := toggle.pending_active
	toggle._process(toggle.transition_time * 0.25)
	_expect(
		is_equal_approx(
			toggle.warning_pulse.elapsed,
			toggle.transition_time * 0.25
		)
		and toggle.outline.width > toggle_base_width
		and not is_equal_approx(toggle.outline.width, pulse_width)
		and toggle.body_visual.color == toggle_body_color
		and toggle.edge_visual.color == toggle_edge_color
		and toggle.outline.default_color == toggle_outline_color
		and toggle.body_visual.transform.is_equal_approx(
			toggle_body_transform_before
		)
		and toggle.edge_visual.transform.is_equal_approx(
			toggle_edge_transform_before
		)
		and toggle.outline.transform.is_equal_approx(
			toggle_outline_transform_before
		)
		and toggle.transform.is_equal_approx(toggle_root_before)
		and toggle_shape_node.transform.is_equal_approx(
			toggle_shape_transform_before
		)
		and toggle_shape.size.is_equal_approx(toggle_shape_size_before)
		and toggle.is_active == toggle_state_before
		and toggle.pending_active == toggle_pending_before
		and not toggle_shape_node.disabled
		and toggles.is_empty(),
		"Toggle pulse changed more than outline width and elapsed time."
	)

	_expect(
		accepted.transform.is_equal_approx(hinge_root_before)
		and accepted.collision_layer == hinge_layer_before
		and accepted.collision_mask == hinge_mask_before
		and hinge_shape_node.transform.is_equal_approx(
			hinge_shape_transform_before
		)
		and is_equal_approx(hinge_shape.radius, hinge_radius_before),
		"Hinge feedback changed root or collision geometry."
	)

	toggle.call("_finish_toggle")
	_expect(
		accepted.target_finished
		and not accepted.is_ready
		and not accepted.cooldown_finished,
		"Target completion bypassed the hinge cooldown lock."
	)
	accepted.call("_on_cooldown_finished")
	await process_frame
	accepted.set_process(false)
	_expect(
		accepted.is_ready
		and accepted.cooldown_finished
		and accepted.target_finished
		and is_zero_approx(accepted.press_visual_time_remaining)
		and is_zero_approx(accepted.locked_visual_cycle)
		and accepted.outer_visual.transform.is_equal_approx(outer_before)
		and accepted.inner_visual.transform.is_equal_approx(inner_before)
		and accepted.outer_visual.color == Hinge.READY_OUTER_COLOR
		and accepted.inner_visual.color == Hinge.READY_INNER_COLOR
		and not toggle.warning_pulse.active
		and is_zero_approx(toggle.warning_pulse.elapsed)
		and is_equal_approx(toggle.outline.width, toggle_base_width)
		and not toggle.is_active
		and toggle_shape_node.disabled
		and toggles == [false],
		"Toggle finish or hinge unlock did not restore feedback state."
	)

	accepted.receive_impulse(Vector2.ZERO)
	var toggle_ref: WeakRef = weakref(toggle)
	var accepted_ref: WeakRef = weakref(accepted)
	var rejected_ref: WeakRef = weakref(rejected)
	var unlinked_ref: WeakRef = weakref(unlinked)
	for node: Node in [accepted, rejected, unlinked, toggle]:
		node.queue_free()
	await process_frame
	_expect(
		toggle_ref.get_ref() == null
		and accepted_ref.get_ref() == null
		and rejected_ref.get_ref() == null
		and unlinked_ref.get_ref() == null
		and toggles == [false],
		"Active hinge or toggle feedback did not clean up on exit."
	)


func _test_rotating_warning_pulse() -> void:
	var platform := ROTATING_SCENE.instantiate() as RotatingPlatform
	platform.warning_time = 0.0
	root.add_child(platform)
	platform.set_process(false)
	await process_frame
	platform.set_process(false)

	var root_before := platform.transform
	var pivot_before := platform.visual_pivot.transform
	var rest_before := platform.rest_collision.transform
	var rest_shape := platform.rest_collision.shape as RectangleShape2D
	var rest_size_before := rest_shape.size
	var body_transform_before := platform.body_visual.transform
	var edge_transform_before := platform.edge_visual.transform
	var outline_transform_before := platform.outline.transform
	var base_width := platform.outline.width
	var launches: Array[int] = []
	var toggles: Array[bool] = []
	platform.launched.connect(func(count: int) -> void: launches.append(count))
	platform.toggled.connect(func(value: bool) -> void: toggles.append(value))

	var accepted := platform.request_toggle()
	var elapsed_before_duplicate := platform.warning_pulse.elapsed
	var width_before_duplicate := platform.outline.width
	var duplicate := platform.request_toggle()
	var body_color := platform.body_visual.color
	var edge_color := platform.edge_visual.color
	var outline_color := platform.outline.default_color
	platform._process(platform.warning_pulse.duration * 0.25)
	_expect(
		accepted
		and not duplicate
		and is_equal_approx(elapsed_before_duplicate, 0.0)
		and width_before_duplicate > base_width
		and platform.warning_pulse.active
		and platform.warning_pulse.elapsed > elapsed_before_duplicate
		and platform.outline.width > base_width
		and platform.body_visual.color == body_color
		and platform.edge_visual.color == edge_color
		and platform.outline.default_color == outline_color
		and platform.transform.is_equal_approx(root_before)
		and platform.visual_pivot.transform.is_equal_approx(pivot_before)
		and platform.rest_collision.transform.is_equal_approx(rest_before)
		and rest_shape.size.is_equal_approx(rest_size_before)
		and platform.body_visual.transform.is_equal_approx(
			body_transform_before
		)
		and platform.edge_visual.transform.is_equal_approx(
			edge_transform_before
		)
		and platform.outline.transform.is_equal_approx(
			outline_transform_before
		)
		and launches.is_empty()
		and toggles.is_empty(),
		"Rotating warning pulse restarted or changed gameplay state."
	)

	await process_frame
	await physics_frame
	_expect(
		not platform.warning_pulse.active
		and is_zero_approx(platform.warning_pulse.elapsed)
		and is_equal_approx(platform.outline.width, base_width)
		and launches == [0]
		and toggles.is_empty(),
		"Rotating warning pulse did not reset at the launch boundary."
	)
	var platform_ref: WeakRef = weakref(platform)
	platform.queue_free()
	await process_frame
	_expect(
		platform_ref.get_ref() == null and toggles.is_empty(),
		"Rotating feedback or tween did not clean up on exit."
	)


func _test_vertical_warning_pulse() -> void:
	var lift := VERTICAL_SCENE.instantiate() as VerticalPlatform
	lift.warning_time = 10.0
	root.add_child(lift)
	lift.set_process(false)
	lift.set_physics_process(false)
	await process_frame
	lift.set_process(false)
	lift.set_physics_process(false)

	var root_before := lift.transform
	var platform_before := lift.platform.transform
	var body_before := lift.body_visual.transform
	var edge_before := lift.edge_visual.transform
	var outline_before := lift.outline.transform
	var shape_node := lift.platform.get_node(
		"CollisionShape2D"
	) as CollisionShape2D
	var shape_transform_before := shape_node.transform
	var shape := shape_node.shape as RectangleShape2D
	var shape_size_before := shape.size
	var base_width := lift.outline.width
	var toggles: Array[bool] = []
	lift.toggled.connect(func(value: bool) -> void: toggles.append(value))

	var accepted := lift.request_toggle()
	lift._process(lift.warning_time * 0.25)
	var elapsed_before_duplicate := lift.warning_pulse.elapsed
	var width_before_duplicate := lift.outline.width
	var duplicate := lift.request_toggle()
	_expect(
		accepted
		and not duplicate
		and lift.warning_pulse.active
		and is_equal_approx(
			lift.warning_pulse.elapsed,
			elapsed_before_duplicate
		)
		and is_equal_approx(lift.outline.width, width_before_duplicate)
		and lift.outline.width > base_width
		and lift.body_visual.color == VerticalPlatform.WARNING_COLOR
		and lift.edge_visual.color == VerticalPlatform.WARNING_COLOR
		and lift.transform.is_equal_approx(root_before)
		and lift.platform.transform.is_equal_approx(platform_before)
		and lift.body_visual.transform.is_equal_approx(body_before)
		and lift.edge_visual.transform.is_equal_approx(edge_before)
		and lift.outline.transform.is_equal_approx(outline_before)
		and shape_node.transform.is_equal_approx(shape_transform_before)
		and shape.size.is_equal_approx(shape_size_before)
		and not lift.is_moving
		and is_zero_approx(lift.movement_elapsed)
		and toggles.is_empty(),
		"Vertical warning pulse restarted or changed motion geometry."
	)

	lift.call("_begin_travel")
	_expect(
		not lift.warning_pulse.active
		and is_zero_approx(lift.warning_pulse.elapsed)
		and is_equal_approx(lift.outline.width, base_width)
		and lift.is_moving
		and is_zero_approx(lift.movement_elapsed)
		and lift.platform.transform.is_equal_approx(platform_before)
		and toggles.is_empty(),
		"Vertical warning pulse did not reset at the travel boundary."
	)
	var lift_ref: WeakRef = weakref(lift)
	lift.queue_free()
	await process_frame
	_expect(
		lift_ref.get_ref() == null and toggles.is_empty(),
		"Vertical warning feedback did not clean up on exit."
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

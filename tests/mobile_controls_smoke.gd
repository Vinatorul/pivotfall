extends SceneTree

const MOBILE_CONTROLS_SCENE := preload(
	"res://scenes/mobile_controls.tscn"
)
const PLAYER_SCENE := preload("res://scenes/player.tscn")

var failures: Array[String] = []
var pause_request_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(
		bool(
			ProjectSettings.get_setting(
				"input_devices/pointing/emulate_mouse_from_touch",
				false
			)
		),
		"Touch input is not configured to activate menu buttons."
	)
	var controls := MOBILE_CONTROLS_SCENE.instantiate() as MobileControls
	root.add_child(controls)
	current_scene = controls
	await process_frame

	controls.set_touchscreen_override_for_tests(true, false)
	controls.set_active(true)
	_expect(
		not controls.is_active(),
		"Controls appeared when touchscreen availability was disabled."
	)

	controls.set_touchscreen_override_for_tests(true, true)
	_expect(
		controls.is_active(),
		"Controls did not appear for an available touchscreen."
	)
	_expect_button_contracts(controls)
	_expect_gameplay_buttons_clear_actor_floor(controls)
	controls.pause_requested.connect(_on_pause_requested)
	_expect(
		controls.call(
			"_button_at",
			controls.pause_button.get_global_transform_with_canvas().origin
		) == controls.pause_button,
		"Pause button center did not resolve to its touch area."
	)

	await _press_touch(controls.left_button, 0)
	_expect(
		Input.is_action_pressed("mobile_move_left"),
		"Left touch did not press the mobile movement action."
	)
	await _press_touch(controls.jump_button, 1)
	_expect(
		Input.is_action_pressed("mobile_move_left")
		and Input.is_action_pressed("mobile_jump"),
		"Movement and jump did not remain active as separate touches."
	)
	await _release_touch(controls.jump_button, 1)
	_expect(
		Input.is_action_pressed("mobile_move_left")
		and not Input.is_action_pressed("mobile_jump"),
		"Releasing jump also released the movement touch."
	)
	await _release_touch(controls.left_button, 0)

	await _press_touch(controls.right_button, 2)
	await _press_touch(controls.attack_button, 3)
	_expect(
		Input.is_action_pressed("mobile_move_right")
		and Input.is_action_pressed("mobile_attack"),
		"Movement and attack did not support simultaneous touches."
	)
	await _release_touch(controls.attack_button, 3)
	await _release_touch(controls.right_button, 2)

	await _press_touch(controls.pause_button, 4)
	_expect(
		pause_request_count == 1,
		"Pause touch emitted %d pause requests instead of one."
		% pause_request_count
	)
	await _release_touch(controls.pause_button, 4)

	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	await physics_frame
	await _press_touch(controls.right_button, 8)
	_expect(
		player.velocity.x > 0.0,
		"Player did not consume mobile right movement."
	)
	await _release_touch(controls.right_button, 8)
	await _press_touch(controls.attack_button, 9)
	_expect(
		player.attack_time_remaining > 0.0,
		"Player did not consume the mobile attack action."
	)
	await _release_touch(controls.attack_button, 9)
	player.queue_free()
	await player.tree_exited

	await _press_touch(controls.left_button, 5)
	await _press_touch(controls.attack_button, 6)
	Input.action_press("ui_left")
	controls.set_active(false)
	_expect(
		not controls.is_active()
		and not _any_mobile_action_pressed(),
		"Hiding mobile controls left a mobile action pressed."
	)
	_expect(
		Input.is_action_pressed("ui_left"),
		"Mobile cleanup released an unrelated desktop action."
	)
	Input.action_release("ui_left")

	controls.set_active(true)
	await _press_touch(controls.right_button, 7)
	controls.queue_free()
	await controls.tree_exited
	_expect(
		not _any_mobile_action_pressed(),
		"Freeing mobile controls left a mobile action pressed."
	)

	_finish()


func _expect_button_contracts(controls: MobileControls) -> void:
	var expected_actions := {
		controls.left_button: &"mobile_move_left",
		controls.right_button: &"mobile_move_right",
		controls.jump_button: &"mobile_jump",
		controls.attack_button: &"mobile_attack",
		controls.pause_button: &"mobile_pause",
	}
	for button: MobileTouchButton in expected_actions:
		var shape := button.touch_shape
		_expect(
			button.action == expected_actions[button]
			and is_instance_valid(shape)
			and shape.size.x >= 72.0
			and shape.size.y >= 52.0,
			"Mobile button '%s' has no usable action or hit area."
			% button.name
		)


func _expect_gameplay_buttons_clear_actor_floor(
	controls: MobileControls
) -> void:
	var view_rect := controls.get_viewport().get_visible_rect()
	var gameplay_buttons: Array[MobileTouchButton] = [
		controls.left_button,
		controls.right_button,
		controls.attack_button,
		controls.jump_button,
	]
	var all_buttons := gameplay_buttons.duplicate()
	all_buttons.append(controls.pause_button)
	for button: MobileTouchButton in all_buttons:
		var button_rect := _button_rect(button)
		_expect(
			view_rect.encloses(button_rect),
			"Mobile button '%s' is clipped by the viewport."
			% button.name
		)
		_expect(
			controls.call(
				"_button_at",
				button_rect.get_center()
			) == button,
			"Mobile button '%s' center is not touchable."
			% button.name
		)
	for button: MobileTouchButton in gameplay_buttons:
		_expect(
			_button_rect(button).end.y
			< view_rect.position.y + view_rect.size.y * 0.78,
			"Mobile button '%s' overlaps the actor floor zone."
			% button.name
		)
	_expect(
		not _button_rect(controls.left_button).intersects(
			_button_rect(controls.right_button)
		)
		and not _button_rect(controls.attack_button).intersects(
			_button_rect(controls.jump_button)
		),
		"Buttons in a side group overlap."
	)
	_expect(
		controls.left_button.position.x < view_rect.size.x * 0.25
		and controls.right_button.position.x < view_rect.size.x * 0.25
		and controls.attack_button.position.x > view_rect.size.x * 0.75
		and controls.jump_button.position.x > view_rect.size.x * 0.75,
		"Gameplay buttons are not docked to the arena sides."
	)


func _button_rect(button: MobileTouchButton) -> Rect2:
	var half_size := button.touch_shape.size * 0.5
	var transform := button.get_global_transform_with_canvas()
	var corners: Array[Vector2] = [
		transform * Vector2(-half_size.x, -half_size.y),
		transform * Vector2(half_size.x, -half_size.y),
		transform * Vector2(half_size.x, half_size.y),
		transform * Vector2(-half_size.x, half_size.y),
	]
	var minimum := corners[0]
	var maximum := corners[0]
	for corner: Vector2 in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _press_touch(button: MobileTouchButton, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.window_id = root.get_window_id()
	event.index = index
	event.position = button.get_global_transform_with_canvas().origin
	event.pressed = true
	root.push_input(event, true)
	await physics_frame
	await process_frame


func _release_touch(button: MobileTouchButton, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.window_id = root.get_window_id()
	event.index = index
	event.position = button.get_global_transform_with_canvas().origin
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _on_pause_requested() -> void:
	pause_request_count += 1


func _any_mobile_action_pressed() -> bool:
	for action: StringName in MobileControls.GAMEPLAY_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for action: StringName in MobileControls.GAMEPLAY_ACTIONS:
		Input.action_release(action)
	Input.action_release("ui_left")
	if failures.is_empty():
		print("MOBILE_CONTROLS_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)

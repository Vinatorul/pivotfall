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


func _press_touch(button: MobileTouchButton, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.window_id = root.get_window_id()
	event.index = index
	event.position = button.get_global_transform_with_canvas().origin
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	await physics_frame


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

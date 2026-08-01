class_name MobileControls
extends CanvasLayer

signal pause_requested

const MOVE_LEFT_ACTION := &"mobile_move_left"
const MOVE_RIGHT_ACTION := &"mobile_move_right"
const JUMP_ACTION := &"mobile_jump"
const ATTACK_ACTION := &"mobile_attack"
const PAUSE_ACTION := &"mobile_pause"
const GAMEPLAY_ACTIONS: Array[StringName] = [
	MOVE_LEFT_ACTION,
	MOVE_RIGHT_ACTION,
	JUMP_ACTION,
	ATTACK_ACTION,
	PAUSE_ACTION,
]
const GAMEPLAY_BUTTON_SIZE := Vector2(88.0, 88.0)
const PAUSE_BUTTON_SIZE := Vector2(72.0, 52.0)
const BASE_VIEW_SIZE := Vector2(960.0, 540.0)
const NORMAL_MODULATE := Color.WHITE
const PRESSED_MODULATE := Color(1.18, 1.18, 1.18, 1.0)

var left_button: MobileTouchButton
var right_button: MobileTouchButton
var jump_button: MobileTouchButton
var attack_button: MobileTouchButton
var pause_button: MobileTouchButton

var _active_requested := false
var _touchscreen_override_enabled := false
var _touchscreen_override_available := false
var _button_visuals: Dictionary = {}
var _touch_buttons: Dictionary = {}
var _button_touch_counts: Dictionary = {}


func _ready() -> void:
	left_button = _create_button(
		&"Left",
		"<",
		MOVE_LEFT_ACTION,
		GAMEPLAY_BUTTON_SIZE,
		Color(0.439, 0.827, 0.816, 1.0),
		32
	)
	right_button = _create_button(
		&"Right",
		">",
		MOVE_RIGHT_ACTION,
		GAMEPLAY_BUTTON_SIZE,
		Color(0.439, 0.827, 0.816, 1.0),
		32
	)
	attack_button = _create_button(
		&"Attack",
		"HIT",
		ATTACK_ACTION,
		GAMEPLAY_BUTTON_SIZE,
		Color(0.973, 0.58, 0.267, 1.0),
		15
	)
	jump_button = _create_button(
		&"Jump",
		"JUMP",
		JUMP_ACTION,
		GAMEPLAY_BUTTON_SIZE,
		Color(0.439, 0.827, 0.816, 1.0),
		14
	)
	pause_button = _create_button(
		&"Pause",
		"II",
		PAUSE_ACTION,
		PAUSE_BUTTON_SIZE,
		Color(0.651, 0.714, 0.82, 1.0),
		18
	)
	pause_button.pressed.connect(pause_requested.emit)

	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_refresh_visibility()


func _exit_tree() -> void:
	_release_actions()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventScreenTouch:
		return

	var touch := event as InputEventScreenTouch
	if touch.pressed and not touch.canceled:
		if _touch_buttons.has(touch.index):
			return
		var button := _button_at(touch.position)
		if not is_instance_valid(button):
			return
		_touch_buttons[touch.index] = button
		_press_button(button)
	else:
		var button := _touch_buttons.get(touch.index) as MobileTouchButton
		if not is_instance_valid(button):
			return
		_touch_buttons.erase(touch.index)
		_release_button(button)

	get_viewport().set_input_as_handled()


func set_active(active: bool) -> void:
	_active_requested = active
	_refresh_visibility()


func is_active() -> bool:
	return visible


func set_touchscreen_override_for_tests(
	enabled: bool,
	available: bool = true
) -> void:
	_touchscreen_override_enabled = enabled
	_touchscreen_override_available = available
	_refresh_visibility()


func _touchscreen_available() -> bool:
	if _touchscreen_override_enabled:
		return _touchscreen_override_available
	return DisplayServer.is_touchscreen_available()


func _refresh_visibility() -> void:
	var should_show := _active_requested and _touchscreen_available()
	if not should_show:
		_release_actions()
	visible = should_show
	for button: MobileTouchButton in _buttons():
		button.visible = should_show
		_set_button_pressed_visual(button, false)


func _release_actions() -> void:
	for raw_button: Variant in _button_touch_counts.keys():
		var button := raw_button as MobileTouchButton
		if is_instance_valid(button):
			button.released.emit()
	_button_touch_counts.clear()
	_touch_buttons.clear()
	for action: StringName in GAMEPLAY_ACTIONS:
		if InputMap.has_action(action):
			Input.action_release(action)


func _create_button(
	button_name: StringName,
	label_text: String,
	action_name: StringName,
	button_size: Vector2,
	accent_color: Color,
	font_size: int
) -> MobileTouchButton:
	var button := MobileTouchButton.new()
	button.name = button_name
	button.action = action_name
	var touch_shape := RectangleShape2D.new()
	touch_shape.size = button_size
	button.touch_shape = touch_shape
	add_child(button)

	var visual := Panel.new()
	visual.name = &"Visual"
	visual.position = -button_size * 0.5
	visual.size = button_size
	visual.pivot_offset = button_size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_theme_stylebox_override(
		"panel",
		_make_button_style(accent_color)
	)
	button.add_child(visual)

	var label := Label.new()
	label.name = &"Label"
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", accent_color)
	label.add_theme_font_size_override("font_size", font_size)
	visual.add_child(label)

	button.pressed.connect(_set_button_pressed_visual.bind(button, true))
	button.released.connect(_set_button_pressed_visual.bind(button, false))
	_button_visuals[button] = visual
	return button


func _button_at(viewport_position: Vector2) -> MobileTouchButton:
	for button: MobileTouchButton in [
		pause_button,
		jump_button,
		attack_button,
		left_button,
		right_button,
	]:
		if not is_instance_valid(button) or not button.visible:
			continue
		var shape := button.touch_shape
		if not is_instance_valid(shape):
			continue
		var local_position := (
			button.get_global_transform_with_canvas().affine_inverse()
			* viewport_position
		)
		if Rect2(-shape.size * 0.5, shape.size).has_point(
			local_position
		):
			return button
	return null


func _press_button(button: MobileTouchButton) -> void:
	var touch_count := int(_button_touch_counts.get(button, 0)) + 1
	_button_touch_counts[button] = touch_count
	if touch_count > 1:
		return
	var action := StringName(button.action)
	if InputMap.has_action(action):
		Input.action_press(action)
	button.pressed.emit()


func _release_button(button: MobileTouchButton) -> void:
	var touch_count := maxi(
		int(_button_touch_counts.get(button, 0)) - 1,
		0
	)
	if touch_count > 0:
		_button_touch_counts[button] = touch_count
		return
	_button_touch_counts.erase(button)
	var action := StringName(button.action)
	if InputMap.has_action(action):
		Input.action_release(action)
	button.released.emit()


func _make_button_style(accent_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.047, 0.082, 0.76)
	style.border_color = Color(
		accent_color.r,
		accent_color.g,
		accent_color.b,
		0.9
	)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	return style


func _set_button_pressed_visual(
	button: MobileTouchButton,
	pressed: bool
) -> void:
	var visual := _button_visuals.get(button) as Control
	if not is_instance_valid(visual):
		return
	visual.modulate = PRESSED_MODULATE if pressed else NORMAL_MODULATE
	visual.scale = Vector2(0.92, 0.92) if pressed else Vector2.ONE


func _update_layout() -> void:
	if not is_instance_valid(left_button):
		return
	var view_size := get_viewport().get_visible_rect().size
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		view_size = BASE_VIEW_SIZE

	var compact_scale := clampf(view_size.x / 720.0, 0.68, 1.0)
	for button: MobileTouchButton in _buttons():
		button.scale = Vector2.ONE * compact_scale

	var side_row_y := view_size.y * 0.62
	var left_x := 72.0 * compact_scale
	var right_x := view_size.x - 72.0 * compact_scale
	left_button.position = Vector2(left_x, side_row_y)
	right_button.position = Vector2(
		left_x + 100.0 * compact_scale,
		side_row_y
	)
	attack_button.position = Vector2(
		right_x - 100.0 * compact_scale,
		side_row_y
	)
	jump_button.position = Vector2(right_x, side_row_y)
	pause_button.position = Vector2(
		view_size.x * 0.5,
		36.0 * compact_scale
	)


func _buttons() -> Array[MobileTouchButton]:
	return [
		left_button,
		right_button,
		jump_button,
		attack_button,
		pause_button,
	]

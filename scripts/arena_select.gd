class_name ArenaSelect
extends Control

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const CAMPAIGN_SCENE_PATH := "res://scenes/campaign_runner.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GRID_COLUMNS := 3
const TOUCH_DRAG_CANCEL_DISTANCE := 12.0
const STATUS_ERROR_COLOR := Color(0.949, 0.427, 0.471, 1.0)
const STATUS_INFO_COLOR := Color(0.439, 0.827, 0.816, 1.0)

enum ArenaState {
	LOCKED,
	OPEN,
	COMPLETED,
	CURRENT,
}

@onready var arena_scroll: ScrollContainer = $Panel/ArenaScroll
@onready var arena_grid: GridContainer = (
	$Panel/ArenaScroll/ArenaGrid
)
@onready var status_label: Label = $Panel/Status
@onready var back_button: Button = $Panel/Back
@onready var footer_label: Label = $Panel/Footer

var campaign_entries: Array[Dictionary] = []
var arena_buttons: Array[Button] = []
var current_level_index := -1
var highest_unlocked_index := -1
var progress_completed := false
var has_valid_progress := false
var transitioning := false
var _touch_targets: Dictionary = {}
var _touch_start_positions: Dictionary = {}


func _ready() -> void:
	back_button.pressed.connect(_return_to_main_menu)
	if DisplayServer.is_touchscreen_available():
		footer_label.text = (
			"КАСАНИЕ — ВЫБОР    НАЗАД — В МЕНЮ"
		)

	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("set_context_suppressed")
	):
		selector.call("set_context_suppressed", true)

	get_tree().paused = false
	_load_campaign_and_progress()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_WM_GO_BACK_REQUEST
		and is_node_ready()
	):
		_return_to_main_menu()


func _input(event: InputEvent) -> void:
	if transitioning:
		return
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touch_start_positions.has(drag.index):
			return
		var start := _touch_start_positions[drag.index] as Vector2
		if drag.position.distance_to(start) > TOUCH_DRAG_CANCEL_DISTANCE:
			_touch_targets.erase(drag.index)
			_touch_start_positions.erase(drag.index)
		return
	if not event is InputEventScreenTouch:
		return

	var touch := event as InputEventScreenTouch
	if touch.pressed:
		var target := _touch_button_at(touch.position)
		if not is_instance_valid(target):
			return
		_touch_targets[touch.index] = target
		_touch_start_positions[touch.index] = touch.position
		target.grab_focus()
		return

	var target := _touch_targets.get(touch.index) as Button
	var start := _touch_start_positions.get(
		touch.index,
		touch.position
	) as Vector2
	_touch_targets.erase(touch.index)
	_touch_start_positions.erase(touch.index)
	if (
		not is_instance_valid(target)
		or target.disabled
		or touch.canceled
		or touch.position.distance_to(start)
		> TOUCH_DRAG_CANCEL_DISTANCE
		or not target.get_global_rect().has_point(touch.position)
	):
		return
	target.pressed.emit()
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		transitioning
		or not event is InputEventKey
		or not event.pressed
		or event.echo
	):
		return

	var key_event := event as InputEventKey
	var key := (
		key_event.physical_keycode
		if key_event.physical_keycode != 0
		else key_event.keycode
	)
	match key:
		KEY_ESCAPE:
			_return_to_main_menu()
		KEY_W, KEY_UP:
			_move_focus(Vector2i.UP)
		KEY_S, KEY_DOWN:
			_move_focus(Vector2i.DOWN)
		KEY_A, KEY_LEFT:
			_move_focus(Vector2i.LEFT)
		KEY_D, KEY_RIGHT:
			_move_focus(Vector2i.RIGHT)
		_:
			return
	get_viewport().set_input_as_handled()


func get_arena_button(level_id: String) -> Button:
	var index := _campaign_index_for_id(level_id)
	if index < 0 or index >= arena_buttons.size():
		return null
	return arena_buttons[index]


func _touch_button_at(position: Vector2) -> Button:
	if back_button.get_global_rect().has_point(position):
		return back_button
	if not arena_scroll.get_global_rect().has_point(position):
		return null
	for button: Button in arena_buttons:
		if (
			button.visible
			and not button.disabled
			and button.get_global_rect().has_point(position)
		):
			return button
	return null


func _load_campaign_and_progress() -> void:
	var campaign_result := CAMPAIGN_STORAGE.load_builtin_campaign()
	if not bool(campaign_result.get("ok", false)):
		_show_error("Не удалось загрузить кампанию.")
		_focus_back_deferred()
		return

	for raw_entry: Variant in campaign_result.get("entries", []):
		if typeof(raw_entry) == TYPE_DICTIONARY:
			campaign_entries.append(
				(raw_entry as Dictionary).duplicate(true)
			)
	if campaign_entries.is_empty():
		_show_error("Кампания не содержит арен.")
		_focus_back_deferred()
		return

	var progress_store := _progress_store()
	if not is_instance_valid(progress_store):
		_show_error("Хранилище прогресса недоступно.")
		_focus_back_deferred()
		return
	progress_store.cancel_launch_request()
	var loaded := progress_store.load_progress(campaign_entries)
	if not bool(loaded.get("ok", false)):
		_show_error("Не удалось прочитать сохранение.")
		_focus_back_deferred()
		return
	if not bool(loaded.get("exists", false)):
		_show_error("Сначала начните новую игру.")
		_focus_back_deferred()
		return

	var progress: Dictionary = loaded["data"]
	current_level_index = _campaign_index_for_id(
		str(progress.get("current_level_id", ""))
	)
	highest_unlocked_index = _campaign_index_for_id(
		str(progress.get("highest_unlocked_level_id", ""))
	)
	if current_level_index < 0 or highest_unlocked_index < 0:
		_show_error(
			"Сохранение не соответствует кампании."
		)
		_focus_back_deferred()
		return

	progress_completed = bool(progress.get("completed", false))
	has_valid_progress = true
	_build_arena_buttons()
	_show_status(
		"ОТКРЫТО  /  %d ИЗ %d"
		% [highest_unlocked_index + 1, campaign_entries.size()],
		false
	)
	_configure_focus_neighbors()
	call_deferred("_focus_initial_button")


func _build_arena_buttons() -> void:
	arena_buttons.clear()
	for index in campaign_entries.size():
		var entry: Dictionary = campaign_entries[index]
		var level_id := str(entry.get("id", ""))
		var title := str(entry.get("title", level_id)).to_upper()
		var state := _arena_state(index)
		var button := Button.new()
		button.name = "Arena%02d" % (index + 1)
		button.custom_minimum_size = Vector2(240.0, 64.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = (
			Control.FOCUS_NONE
			if state == ArenaState.LOCKED
			else Control.FOCUS_ALL
		)
		button.disabled = state == ArenaState.LOCKED
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text = "%s\n%s" % [title, _state_label(state)]
		button.tooltip_text = title
		button.set_meta("level_id", level_id)
		button.set_meta("state", _state_label(state))
		_style_arena_button(button, state)
		button.pressed.connect(_launch_replay.bind(level_id))
		arena_grid.add_child(button)
		arena_buttons.append(button)


func _arena_state(index: int) -> ArenaState:
	if index > highest_unlocked_index:
		return ArenaState.LOCKED
	if progress_completed:
		return ArenaState.COMPLETED
	if index == current_level_index:
		return ArenaState.CURRENT
	if index < highest_unlocked_index:
		return ArenaState.COMPLETED
	return ArenaState.OPEN


func _state_label(state: ArenaState) -> String:
	match state:
		ArenaState.LOCKED:
			return "ЗАКРЫТА"
		ArenaState.OPEN:
			return "ОТКРЫТА"
		ArenaState.COMPLETED:
			return "ПРОЙДЕНА"
		ArenaState.CURRENT:
			return "ТЕКУЩАЯ"
	return ""


func _style_arena_button(button: Button, state: ArenaState) -> void:
	var border_color := Color(0.173, 0.227, 0.337, 1.0)
	var font_color := Color(0.792, 0.835, 0.906, 1.0)
	match state:
		ArenaState.CURRENT:
			border_color = Color(0.973, 0.58, 0.267, 1.0)
			font_color = Color(0.973, 0.71, 0.49, 1.0)
		ArenaState.COMPLETED:
			border_color = Color(0.439, 0.827, 0.816, 1.0)
		ArenaState.OPEN:
			border_color = Color(0.651, 0.714, 0.82, 1.0)
		ArenaState.LOCKED:
			border_color = Color(0.173, 0.227, 0.337, 1.0)
			font_color = Color(0.439, 0.502, 0.616, 1.0)

	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override(
		"font_hover_color",
		Color(0.439, 0.827, 0.816, 1.0)
	)
	button.add_theme_color_override(
		"font_focus_color",
		Color(0.439, 0.827, 0.816, 1.0)
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color(0.973, 0.58, 0.267, 1.0)
	)
	button.add_theme_color_override(
		"font_disabled_color",
		Color(0.439, 0.502, 0.616, 1.0)
	)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_stylebox_override(
		"normal",
		_button_style(Color(0.075, 0.098, 0.165, 1.0), border_color, 2)
	)
	button.add_theme_stylebox_override(
		"hover",
		_button_style(
			Color(0.102, 0.137, 0.224, 1.0),
			Color(0.439, 0.827, 0.816, 1.0),
			2
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_button_style(
			Color(0.176, 0.118, 0.094, 1.0),
			Color(0.973, 0.58, 0.267, 1.0),
			2
		)
	)
	button.add_theme_stylebox_override(
		"focus",
		_button_style(
			Color(0.075, 0.098, 0.165, 1.0),
			Color(0.439, 0.827, 0.816, 1.0),
			3
		)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_button_style(
			Color(0.055, 0.071, 0.122, 1.0),
			Color(0.173, 0.227, 0.337, 1.0),
			2
		)
	)


func _button_style(
	background_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	return style


func _configure_focus_neighbors() -> void:
	if arena_buttons.is_empty() or highest_unlocked_index < 0:
		_focus_back_deferred()
		return

	var back_path := back_button.get_path()
	for index in arena_buttons.size():
		var button := arena_buttons[index]
		if button.disabled:
			continue
		button.focus_neighbor_left = _horizontal_focus_path(
			index,
			-1,
			button.get_path()
		)
		button.focus_neighbor_right = _horizontal_focus_path(
			index,
			1,
			button.get_path()
		)
		button.focus_neighbor_top = _vertical_focus_path(
			index,
			-GRID_COLUMNS,
			back_path
		)
		button.focus_neighbor_bottom = _vertical_focus_path(
			index,
			GRID_COLUMNS,
			back_path
		)

	back_button.focus_neighbor_top = arena_buttons[
		highest_unlocked_index
	].get_path()
	back_button.focus_neighbor_bottom = arena_buttons[
		current_level_index
	].get_path()
	back_button.focus_neighbor_left = back_button.get_path()
	back_button.focus_neighbor_right = back_button.get_path()


func _horizontal_focus_path(
	index: int,
	offset: int,
	fallback: NodePath
) -> NodePath:
	var target_index := index + offset
	if (
		target_index < 0
		or target_index > highest_unlocked_index
		or target_index / GRID_COLUMNS != index / GRID_COLUMNS
	):
		return fallback
	return arena_buttons[target_index].get_path()


func _vertical_focus_path(
	index: int,
	offset: int,
	fallback: NodePath
) -> NodePath:
	var target_index := index + offset
	if target_index < 0 or target_index > highest_unlocked_index:
		return fallback
	return arena_buttons[target_index].get_path()


func _move_focus(direction: Vector2i) -> void:
	if arena_buttons.is_empty() or highest_unlocked_index < 0:
		back_button.grab_focus()
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner == back_button:
		if direction == Vector2i.UP or direction == Vector2i.LEFT:
			arena_buttons[highest_unlocked_index].grab_focus()
		else:
			arena_buttons[current_level_index].grab_focus()
		return

	var current_index := arena_buttons.find(focus_owner)
	if current_index < 0 or current_index > highest_unlocked_index:
		arena_buttons[current_level_index].grab_focus()
		return

	var target_index := current_index
	if direction.x != 0:
		target_index += direction.x
		if (
			target_index < 0
			or target_index > highest_unlocked_index
			or target_index / GRID_COLUMNS
			!= current_index / GRID_COLUMNS
		):
			target_index = current_index
	else:
		target_index += direction.y * GRID_COLUMNS
		if target_index < 0 or target_index > highest_unlocked_index:
			back_button.grab_focus()
			return

	arena_buttons[target_index].grab_focus()


func _focus_initial_button() -> void:
	if (
		has_valid_progress
		and current_level_index >= 0
		and current_level_index < arena_buttons.size()
	):
		arena_buttons[current_level_index].grab_focus()
		return
	back_button.grab_focus()


func _focus_back_deferred() -> void:
	call_deferred("_focus_back_button")


func _focus_back_button() -> void:
	back_button.grab_focus()


func _launch_replay(level_id: String) -> void:
	if transitioning or not has_valid_progress:
		return
	var progress_store := _progress_store()
	if not is_instance_valid(progress_store):
		_show_error("Хранилище прогресса недоступно.")
		return

	_clear_debug_level_request()
	var prepared := progress_store.prepare_replay(
		campaign_entries,
		level_id
	)
	if not bool(prepared.get("ok", false)):
		_show_error("Эта арена пока недоступна.")
		return
	_change_scene(CAMPAIGN_SCENE_PATH, "campaign replay", true)


func _return_to_main_menu() -> void:
	if transitioning:
		return
	var progress_store := _progress_store()
	if is_instance_valid(progress_store):
		progress_store.cancel_launch_request()
	_change_scene(MAIN_MENU_SCENE_PATH, "main menu", false)


func _change_scene(
	scene_path: String,
	description: String,
	has_launch_request: bool
) -> bool:
	if transitioning:
		return false
	if not ResourceLoader.exists(scene_path):
		if has_launch_request:
			_cancel_launch_request()
		_show_error("Не найдена сцена: %s" % scene_path)
		return false

	transitioning = true
	_perform_scene_change.call_deferred(
		scene_path,
		description,
		has_launch_request
	)
	return true


func _perform_scene_change(
	scene_path: String,
	description: String,
	has_launch_request: bool
) -> void:
	if not is_inside_tree():
		return
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error == OK:
		return

	if has_launch_request:
		_cancel_launch_request()
	transitioning = false
	_show_error(
		"Не удалось открыть %s (ошибка %d)."
		% [description, change_error]
	)


func _cancel_launch_request() -> void:
	var progress_store := _progress_store()
	if is_instance_valid(progress_store):
		progress_store.cancel_launch_request()


func _campaign_index_for_id(level_id: String) -> int:
	for index in campaign_entries.size():
		if str(campaign_entries[index].get("id", "")) == level_id:
			return index
	return -1


func _progress_store() -> CampaignProgressStore:
	return get_node_or_null(
		"/root/CampaignProgress"
	) as CampaignProgressStore


func _clear_debug_level_request() -> void:
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method(
			"remember_requested_campaign_level_id"
		)
	):
		selector.call("remember_requested_campaign_level_id", "")


func _show_error(message: String) -> void:
	_show_status(message, true)


func _show_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		STATUS_ERROR_COLOR if is_error else STATUS_INFO_COLOR
	)

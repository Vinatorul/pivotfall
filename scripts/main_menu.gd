class_name MainMenu
extends Control

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const CAMPAIGN_SCENE_PATH := "res://scenes/campaign_runner.tscn"
const LEVEL_EDITOR_SCENE_PATH := "res://scenes/level_editor.tscn"
const STATUS_ERROR_COLOR := Color(0.949, 0.427, 0.471, 1.0)
const STATUS_INFO_COLOR := Color(0.439, 0.827, 0.816, 1.0)

@onready var continue_button: Button = $Panel/Continue
@onready var new_game_button: Button = $Panel/NewGame
@onready var editor_button: Button = $Panel/Editor
@onready var exit_button: Button = $Panel/Exit
@onready var status_label: Label = $Panel/Status
@onready var footer_label: Label = $Footer
@onready var new_game_confirm: Control = $NewGameConfirm
@onready var confirm_message: Label = (
	$NewGameConfirm/Panel/Message
)
@onready var confirm_button: Button = (
	$NewGameConfirm/Panel/Confirm
)
@onready var cancel_button: Button = $NewGameConfirm/Panel/Cancel

var transitioning := false
var confirming_new_game := false
var campaign_entries: Array[Dictionary] = []
var has_existing_save := false
var has_valid_progress := false
var progress_completed := false


func _ready() -> void:
	continue_button.pressed.connect(_continue_game)
	new_game_button.pressed.connect(_start_new_game)
	editor_button.pressed.connect(_open_level_editor)
	exit_button.pressed.connect(_quit_game)
	confirm_button.pressed.connect(_confirm_new_game)
	cancel_button.pressed.connect(_cancel_new_game)

	if OS.has_feature("web"):
		exit_button.visible = false
	if DisplayServer.is_touchscreen_available():
		editor_button.visible = false
		footer_label.text = "КАСАНИЕ — ВЫБОР"

	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("set_context_suppressed")
	):
		selector.call("set_context_suppressed", true)

	get_tree().paused = false
	_load_campaign_and_progress()
	_update_focus_neighbors()
	_focus_initial_button()


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
	if confirming_new_game:
		if key == KEY_ESCAPE:
			_cancel_new_game()
		elif key == KEY_W:
			_move_confirm_focus(-1)
		elif key == KEY_S:
			_move_confirm_focus(1)
		else:
			return
		get_viewport().set_input_as_handled()
		return

	if key == KEY_W:
		_move_focus(-1)
	elif key == KEY_S:
		_move_focus(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _continue_game() -> void:
	if transitioning or confirming_new_game:
		return

	var progress_store := _progress_store()
	if not is_instance_valid(progress_store):
		_show_error("Хранилище прогресса недоступно.")
		return
	_clear_debug_level_request()
	var prepared := progress_store.prepare_continue(campaign_entries)
	if not bool(prepared["ok"]):
		_show_error("Не удалось прочитать сохранение.")
		_refresh_progress_state()
		return

	_change_scene(CAMPAIGN_SCENE_PATH, "campaign")


func _start_new_game() -> void:
	if transitioning or confirming_new_game:
		return
	if campaign_entries.is_empty():
		_show_error("Кампания недоступна.")
		return

	if has_existing_save:
		_open_new_game_confirmation()
		return
	_begin_new_game()


func _begin_new_game() -> void:
	var progress_store := _progress_store()
	if not is_instance_valid(progress_store):
		_show_error("Хранилище прогресса недоступно.")
		return

	_clear_debug_level_request()
	var prepared := progress_store.begin_new_game(campaign_entries)
	if not bool(prepared["ok"]):
		_show_error("Не удалось создать сохранение.")
		_refresh_progress_state()
		return

	_change_scene(CAMPAIGN_SCENE_PATH, "campaign")


func _open_new_game_confirmation() -> void:
	confirming_new_game = true
	confirm_message.text = (
		"ТЕКУЩИЙ ПРОГРЕСС БУДЕТ СБРОШЕН"
		if has_valid_progress
		else "ПОВРЕЖДЁННОЕ СОХРАНЕНИЕ БУДЕТ ЗАМЕНЕНО"
	)
	new_game_confirm.visible = true
	cancel_button.grab_focus()


func _confirm_new_game() -> void:
	if not confirming_new_game or transitioning:
		return
	_close_new_game_confirmation()
	_begin_new_game()


func _cancel_new_game() -> void:
	if not confirming_new_game:
		return
	_close_new_game_confirmation()
	new_game_button.grab_focus()


func _close_new_game_confirmation() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused in [confirm_button, cancel_button]:
		focused.release_focus()
	confirming_new_game = false
	new_game_confirm.visible = false


func _open_level_editor() -> void:
	if transitioning:
		return

	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("open_level_editor_from_current_scene")
	):
		transitioning = true
		if bool(selector.call("open_level_editor_from_current_scene")):
			return
		transitioning = false
		_show_error("Не удалось открыть редактор уровней.")
		return

	_change_scene(LEVEL_EDITOR_SCENE_PATH, "level editor")


func _quit_game() -> void:
	if OS.has_feature("web"):
		return
	get_tree().quit()


func _change_scene(scene_path: String, description: String) -> bool:
	if transitioning:
		return false
	if not ResourceLoader.exists(scene_path):
		var progress_store := _progress_store()
		if is_instance_valid(progress_store):
			progress_store.cancel_launch_request()
		if scene_path == CAMPAIGN_SCENE_PATH:
			_refresh_progress_state()
		_show_error("Не найдена сцена: %s" % scene_path)
		return false

	transitioning = true
	_perform_scene_change.call_deferred(scene_path, description)
	return true


func _perform_scene_change(
	scene_path: String,
	description: String
) -> void:
	if not is_inside_tree():
		return
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error == OK:
		return

	var progress_store := _progress_store()
	if is_instance_valid(progress_store):
		progress_store.cancel_launch_request()
	transitioning = false
	if scene_path == CAMPAIGN_SCENE_PATH:
		_refresh_progress_state()
	_show_error(
		"Не удалось открыть %s (ошибка %d)."
		% [description, change_error]
	)


func _move_focus(offset: int) -> void:
	var buttons := _available_menu_buttons()
	if buttons.is_empty():
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	var current_index := buttons.find(focus_owner)
	if current_index < 0:
		current_index = 0
	buttons[posmod(current_index + offset, buttons.size())].grab_focus()


func _move_confirm_focus(offset: int) -> void:
	var buttons: Array[Button] = [confirm_button, cancel_button]
	var focus_owner := get_viewport().gui_get_focus_owner()
	var current_index := buttons.find(focus_owner)
	if current_index < 0:
		current_index = 0
	buttons[posmod(current_index + offset, buttons.size())].grab_focus()


func _load_campaign_and_progress() -> void:
	var campaign_result := CAMPAIGN_STORAGE.load_builtin_campaign()
	if not bool(campaign_result["ok"]):
		continue_button.disabled = true
		new_game_button.disabled = true
		_show_error("Не удалось загрузить кампанию.")
		return

	for raw_entry: Variant in campaign_result["entries"]:
		if typeof(raw_entry) == TYPE_DICTIONARY:
			campaign_entries.append(
				(raw_entry as Dictionary).duplicate(true)
			)
	_refresh_progress_state()


func _refresh_progress_state() -> void:
	continue_button.text = "ПРОДОЛЖИТЬ"
	continue_button.disabled = true
	has_existing_save = false
	has_valid_progress = false
	progress_completed = false

	var progress_store := _progress_store()
	if not is_instance_valid(progress_store):
		_show_error("Хранилище прогресса недоступно.")
		return
	var loaded := progress_store.load_progress(campaign_entries)
	if not bool(loaded["ok"]):
		has_existing_save = bool(loaded.get("exists", false))
		_show_error(
			"Сохранение повреждено — начните новую игру."
		)
		_update_focus_neighbors()
		return
	if not bool(loaded["exists"]):
		status_label.visible = false
		_update_focus_neighbors()
		return

	has_existing_save = true
	has_valid_progress = true
	var progress: Dictionary = loaded["data"]
	progress_completed = bool(progress["completed"])
	var current_index := _campaign_index_for_id(
		str(progress["current_level_id"])
	)
	if progress_completed:
		continue_button.text = "КАМПАНИЯ ПРОЙДЕНА"
		_show_status(
			"ПРОГРЕСС  /  %d ИЗ %d"
			% [campaign_entries.size(), campaign_entries.size()],
			false
		)
	else:
		continue_button.disabled = false
		continue_button.text = "ПРОДОЛЖИТЬ  /  АРЕНА %02d" % (
			current_index + 1
		)
		status_label.visible = false

	if not loaded.get("warnings", []).is_empty():
		_show_status("СОХРАНЕНИЕ ВОССТАНОВЛЕНО", false)
	_update_focus_neighbors()


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


func _available_menu_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for button: Button in [
		continue_button,
		new_game_button,
		editor_button,
		exit_button,
	]:
		if button.visible and not button.disabled:
			buttons.append(button)
	return buttons


func _update_focus_neighbors() -> void:
	var buttons := _available_menu_buttons()
	if buttons.is_empty():
		return
	for index in buttons.size():
		buttons[index].focus_neighbor_top = buttons[
			posmod(index - 1, buttons.size())
		].get_path()
		buttons[index].focus_neighbor_bottom = buttons[
			posmod(index + 1, buttons.size())
		].get_path()


func _focus_initial_button() -> void:
	var buttons := _available_menu_buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()


func _show_error(message: String) -> void:
	_show_status(message, true)
	_focus_initial_button()


func _show_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		STATUS_ERROR_COLOR if is_error else STATUS_INFO_COLOR
	)
	status_label.visible = true

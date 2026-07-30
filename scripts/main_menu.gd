class_name MainMenu
extends Control

const CAMPAIGN_SCENE_PATH := "res://scenes/campaign_runner.tscn"
const LEVEL_EDITOR_SCENE_PATH := "res://scenes/level_editor.tscn"

@onready var new_game_button: Button = $Panel/NewGame
@onready var editor_button: Button = $Panel/Editor
@onready var exit_button: Button = $Panel/Exit
@onready var status_label: Label = $Panel/Status

var transitioning := false


func _ready() -> void:
	new_game_button.pressed.connect(_start_new_game)
	editor_button.pressed.connect(_open_level_editor)
	exit_button.pressed.connect(_quit_game)

	if OS.has_feature("web"):
		exit_button.visible = false
		new_game_button.focus_neighbor_top = editor_button.get_path()
		editor_button.focus_neighbor_bottom = new_game_button.get_path()

	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("set_context_suppressed")
	):
		selector.call("set_context_suppressed", true)

	get_tree().paused = false
	new_game_button.grab_focus()


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
	if key == KEY_W:
		_move_focus(-1)
	elif key == KEY_S:
		_move_focus(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _start_new_game() -> void:
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("remember_requested_campaign_level_id")
	):
		selector.call("remember_requested_campaign_level_id", "")

	_change_scene(CAMPAIGN_SCENE_PATH, "campaign")


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
		_show_error("Не найдена сцена: %s" % scene_path)
		return false

	transitioning = true
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error == OK:
		return true

	transitioning = false
	_show_error(
		"Не удалось открыть %s (ошибка %d)."
		% [description, change_error]
	)
	return false


func _move_focus(offset: int) -> void:
	var buttons: Array[Button] = []
	for button: Button in [
		new_game_button,
		editor_button,
		exit_button,
	]:
		if button.visible and not button.disabled:
			buttons.append(button)
	if buttons.is_empty():
		return

	var focus_owner := get_viewport().gui_get_focus_owner()
	var current_index := buttons.find(focus_owner)
	if current_index < 0:
		current_index = 0
	buttons[posmod(current_index + offset, buttons.size())].grab_focus()


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.visible = true
	new_game_button.grab_focus()

class_name CampaignPauseMenu
extends CanvasLayer

signal resume_requested
signal restart_requested
signal main_menu_requested

@onready var arena_label: Label = $Overlay/Panel/Arena
@onready var resume_button: Button = $Overlay/Panel/Resume
@onready var restart_button: Button = $Overlay/Panel/Restart
@onready var main_menu_button: Button = $Overlay/Panel/MainMenu
@onready var footer_label: Label = $Overlay/Panel/Footer

var _previous_tree_paused := false


func _ready() -> void:
	resume_button.pressed.connect(resume_requested.emit)
	restart_button.pressed.connect(restart_requested.emit)
	main_menu_button.pressed.connect(main_menu_requested.emit)
	if DisplayServer.is_touchscreen_available():
		footer_label.text = "КАСАНИЕ — ВЫБОР"
	visible = false


func _exit_tree() -> void:
	if visible:
		get_tree().paused = _previous_tree_paused
		visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if (
		not visible
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
			resume_requested.emit()
		KEY_W:
			_move_focus(-1)
		KEY_S:
			_move_focus(1)
		_:
			return
	get_viewport().set_input_as_handled()


func open_menu(arena_text: String) -> bool:
	if visible:
		return false

	arena_label.text = arena_text
	_previous_tree_paused = get_tree().paused
	visible = true
	get_tree().paused = true
	resume_button.grab_focus()
	return true


func close_menu() -> bool:
	if not visible:
		return false

	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and _buttons().has(focused):
		focused.release_focus()

	visible = false
	get_tree().paused = _previous_tree_paused
	return true


func is_open() -> bool:
	return visible


func _move_focus(offset: int) -> void:
	var buttons := _buttons()
	var current := get_viewport().gui_get_focus_owner() as Button
	var index := buttons.find(current)
	if index < 0:
		index = 0
	buttons[posmod(index + offset, buttons.size())].grab_focus()


func _buttons() -> Array[Button]:
	return [
		resume_button,
		restart_button,
		main_menu_button,
	]

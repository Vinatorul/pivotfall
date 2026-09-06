class_name CampaignPauseMenu
extends CanvasLayer

signal resume_requested
signal restart_requested
signal main_menu_requested

var _previous_tree_paused := false
var _previous_content_scale_size := Vector2i.ZERO
var _help_view := false
var _touch_controls := false

@onready var panel: PanelContainer = $Overlay/Panel
@onready var content: VBoxContainer = $Overlay/Panel/Margin/Content
@onready var title_label: Label = content.get_node("Title")
@onready var arena_label: Label = content.get_node("Arena")
@onready var help_scroll: ScrollContainer = content.get_node("HelpScroll")
@onready var objective_label: Label = help_scroll.get_node("Help/Objective")
@onready var controls_label: Label = help_scroll.get_node("Help/Controls")
@onready var actions: BoxContainer = content.get_node("Actions")
@onready var resume_button: Button = actions.get_node("Resume")
@onready var restart_button: Button = actions.get_node("Restart")
@onready var main_menu_button: Button = actions.get_node("MainMenu")
@onready var footer_label: Label = content.get_node("Footer")


func _ready() -> void:
	resume_button.pressed.connect(resume_requested.emit)
	restart_button.pressed.connect(restart_requested.emit)
	main_menu_button.pressed.connect(main_menu_requested.emit)
	get_viewport().size_changed.connect(_update_layout)
	visible = false
	_update_layout()


func _exit_tree() -> void:
	if visible:
		visible = false
		get_tree().root.content_scale_size = _previous_content_scale_size
		get_tree().paused = _previous_tree_paused


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return

	var key_event := event as InputEventKey
	var key := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	match key:
		KEY_ESCAPE:
			resume_requested.emit()
		KEY_H:
			if _help_view:
				resume_requested.emit()
			else:
				_set_view(true)
		KEY_W:
			_move_focus(-1)
		KEY_S:
			_move_focus(1)
		KEY_PAGEUP:
			help_scroll.scroll_vertical -= int(help_scroll.size.y * 0.8)
		KEY_PAGEDOWN:
			help_scroll.scroll_vertical += int(help_scroll.size.y * 0.8)
		_:
			return
	get_viewport().set_input_as_handled()


func open_menu(
	arena_text: String,
	objective_text: String = "",
	touch_controls: bool = false,
	editor_test: bool = false,
	show_help: bool = false
) -> bool:
	if visible:
		return false

	arena_label.text = arena_text
	objective_label.text = objective_text
	main_menu_button.text = "В редактор" if editor_test else "В меню"
	_touch_controls = touch_controls
	_set_controls(touch_controls)
	_previous_tree_paused = get_tree().paused
	_previous_content_scale_size = get_tree().root.content_scale_size
	visible = true
	get_tree().paused = true
	_set_view(show_help)
	_update_layout()
	return true


func close_menu() -> bool:
	if not visible:
		return false

	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and content.is_ancestor_of(focused):
		focused.release_focus()

	visible = false
	get_tree().root.content_scale_size = _previous_content_scale_size
	get_tree().paused = _previous_tree_paused
	return true


func is_open() -> bool:
	return visible


func is_help_view() -> bool:
	return _help_view


func _move_focus(offset: int) -> void:
	var buttons := _buttons()
	var current := get_viewport().gui_get_focus_owner() as Button
	var index := buttons.find(current)
	if index < 0:
		index = 0
	buttons[posmod(index + offset, buttons.size())].grab_focus()


func _buttons() -> Array[Button]:
	var buttons: Array[Button] = [resume_button]
	if restart_button.visible:
		buttons.append(restart_button)
	if main_menu_button.visible:
		buttons.append(main_menu_button)
	return buttons


func _set_controls(touch_controls: bool) -> void:
	if touch_controls:
		controls_label.text = (
			"< / > — движение · JUMP — прыжок · HIT — удар\n" + "II — пауза · ? — подсказка\n"
		)
	else:
		controls_label.text = (
			"A / D или стрелки — движение\n"
			+ "W / Пробел / стрелка вверх — прыжок · X / J — удар\n"
			+ "R — заново · Esc — пауза · H или кнопка «?» — подсказка"
		)


func _set_view(help_view: bool) -> void:
	_help_view = help_view
	title_label.text = "Подсказка" if help_view else "Пауза"
	objective_label.visible = help_view
	controls_label.visible = not help_view
	help_scroll.get_node("Help/ControlsTitle").visible = not help_view
	restart_button.visible = not help_view
	main_menu_button.visible = not help_view
	resume_button.text = "К игре" if help_view else "Продолжить"
	help_scroll.scroll_vertical = 0
	_set_footer()
	_update_focus_neighbors()
	resume_button.grab_focus()


func _set_footer() -> void:
	if _touch_controls:
		footer_label.text = (
			"Листайте подсказку пальцем. Коснитесь «К игре», чтобы продолжить."
			if _help_view
			else "Коснитесь действия."
		)
	elif _help_view:
		footer_label.text = (
			"Esc / H — к игре\n" + "Колесо мыши / PgUp / PgDn — прокрутка подсказки"
		)
	else:
		footer_label.text = ("Esc — продолжить · W / S или стрелки — выбор · Enter — выбрать")


func _update_focus_neighbors() -> void:
	var buttons := _buttons()
	for index in buttons.size():
		var button := buttons[index]
		var previous := button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		var next := button.get_path_to(buttons[posmod(index + 1, buttons.size())])
		button.focus_neighbor_top = previous
		button.focus_neighbor_left = previous
		button.focus_neighbor_bottom = next
		button.focus_neighbor_right = next


func _update_layout() -> void:
	if visible:
		_fit_window()
	var view_size := get_viewport().get_visible_rect().size
	var panel_width := minf(760.0, view_size.x - 32.0)
	var panel_height := minf(490.0, view_size.y - 32.0)
	actions.vertical = panel_width < 600.0
	if actions.vertical:
		panel_height = view_size.y - 32.0
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5


func _fit_window() -> void:
	var window := get_tree().root
	var compact := window.size.x < 800 or window.size.y < 480
	var scale_size := Vector2i.ZERO if compact else _previous_content_scale_size
	if window.content_scale_size != scale_size:
		window.content_scale_size = scale_size

extends CanvasLayer

const ARENA_PATHS := [
	"res://scenes/arena_01.tscn",
	"res://scenes/arena_02.tscn",
	"res://scenes/arena_03.tscn",
	"res://scenes/arena_04.tscn",
	"res://scenes/arena_05.tscn",
	"res://scenes/arena_06.tscn",
	"res://scenes/arena_07.tscn",
	"res://scenes/arena_08.tscn",
]
const LEVEL_EDITOR_PATH := "res://scenes/level_editor.tscn"
const DEFAULT_EDITOR_RETURN_PATH := "res://scenes/arena_01.tscn"

const ARENA_NAMES := [
	"ARENA 01  /  ИМПУЛЬС",
	"ARENA 02  /  ОПОРА",
	"ARENA 03  /  ОТВЕТНЫЙ УДАР",
	"ARENA 04  /  КАТАПУЛЬТА",
	"ARENA 05  /  ЛИНИЯ ОГНЯ",
	"ARENA 06  /  ЧУЖАЯ РУКА",
	"ARENA 07  /  ВЫСОТА",
	"ARENA 08  /  ЭКЗАМЕН",
]

@onready var menu: Control = $Menu
@onready var arena_list: RichTextLabel = $Menu/Panel/ArenaList
@onready var current_label: Label = $Menu/Panel/Current
@onready var hint: Label = $Hint

var selected_index := 0
var previous_tree_paused := false
var context_suppressed := false
var editor_return_scene_path := DEFAULT_EDITOR_RETURN_PATH


func _ready() -> void:
	if not OS.is_debug_build():
		menu.visible = false
		hint.visible = false
		set_process_input(false)
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	process_mode = Node.PROCESS_MODE_ALWAYS
	menu.visible = false
	_apply_context_availability()


func set_context_suppressed(suppressed: bool) -> void:
	context_suppressed = suppressed
	if not is_node_ready():
		return

	if menu.visible:
		_close_menu()

	_apply_context_availability()


func _input(event: InputEvent) -> void:
	if context_suppressed:
		return

	if not event is InputEventKey or not event.pressed or event.echo:
		return

	var key_event := event as InputEventKey
	var key := (
		key_event.physical_keycode
		if key_event.physical_keycode != 0
		else key_event.keycode
	)

	if key == KEY_F1:
		_toggle_menu()
		get_viewport().set_input_as_handled()
		return

	if not menu.visible:
		return

	var digit_index := _digit_to_arena_index(key_event)
	if digit_index >= 0:
		_load_arena(digit_index)
		get_viewport().set_input_as_handled()
		return
	if key == KEY_E:
		_open_level_editor()
		get_viewport().set_input_as_handled()
		return

	match key:
		KEY_ESCAPE:
			_close_menu()
		KEY_UP, KEY_W:
			_move_selection(-1)
		KEY_DOWN, KEY_S:
			_move_selection(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_load_arena(selected_index)
		_:
			return

	get_viewport().set_input_as_handled()


func _toggle_menu() -> void:
	if menu.visible:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	if context_suppressed:
		return

	selected_index = _current_arena_index()
	previous_tree_paused = get_tree().paused
	get_tree().paused = true
	menu.visible = true
	hint.visible = false
	_render_menu()


func _close_menu() -> void:
	menu.visible = false
	hint.visible = OS.is_debug_build() and not context_suppressed
	get_tree().paused = previous_tree_paused


func _apply_context_availability() -> void:
	var available := OS.is_debug_build() and not context_suppressed
	set_process_input(available)
	menu.visible = false
	hint.visible = available


func _move_selection(offset: int) -> void:
	selected_index = posmod(selected_index + offset, ARENA_PATHS.size())
	_render_menu()


func _load_arena(index: int) -> void:
	if index < 0 or index >= ARENA_PATHS.size():
		return

	var arena_path: String = ARENA_PATHS[index]
	if not ResourceLoader.exists(arena_path):
		push_error("Debug arena does not exist: %s" % arena_path)
		return

	selected_index = index
	_load_scene(ARENA_PATHS[index], "debug arena")


func _open_level_editor() -> void:
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene):
		var current_path := current_scene.scene_file_path
		if (
			not current_path.is_empty()
			and current_path != LEVEL_EDITOR_PATH
			and ResourceLoader.exists(current_path)
		):
			editor_return_scene_path = current_path

	_load_scene(LEVEL_EDITOR_PATH, "level editor")


func get_editor_return_scene_path() -> String:
	if ResourceLoader.exists(editor_return_scene_path):
		return editor_return_scene_path
	return DEFAULT_EDITOR_RETURN_PATH


func _load_scene(scene_path: String, description: String) -> void:
	_close_menu()
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error(
			"Could not open %s '%s' (error %d)."
			% [description, scene_path, change_error]
		)


func _current_arena_index() -> int:
	var current_scene := get_tree().current_scene
	if not is_instance_valid(current_scene):
		return selected_index

	var current_path := current_scene.scene_file_path
	var current_index := ARENA_PATHS.find(current_path)
	return current_index if current_index >= 0 else selected_index


func _digit_to_arena_index(event: InputEventKey) -> int:
	var digit := int(event.unicode) - 48
	if digit >= 1 and digit <= ARENA_PATHS.size():
		return digit - 1

	var key := (
		event.physical_keycode
		if event.physical_keycode != 0
		else event.keycode
	)
	match key:
		KEY_1, KEY_KP_1:
			return 0
		KEY_2, KEY_KP_2:
			return 1
		KEY_3, KEY_KP_3:
			return 2
		KEY_4, KEY_KP_4:
			return 3
		KEY_5, KEY_KP_5:
			return 4
		KEY_6, KEY_KP_6:
			return 5
		KEY_7, KEY_KP_7:
			return 6
		KEY_8, KEY_KP_8:
			return 7

	return -1


func _render_menu() -> void:
	var lines := PackedStringArray()
	for index in range(ARENA_NAMES.size()):
		var is_selected := index == selected_index
		var marker := "▶" if is_selected else " "
		var color := "#6fe0d0" if is_selected else "#a6b6d1"
		lines.append(
			"[color=%s]%s  [%d]  %s[/color]"
			% [color, marker, index + 1, ARENA_NAMES[index]]
		)
	lines.append("[color=#f89444]   [E]  LEVEL EDITOR[/color]")

	arena_list.text = "\n".join(lines)
	current_label.text = "СЕЙЧАС: %s" % ARENA_NAMES[_current_arena_index()]

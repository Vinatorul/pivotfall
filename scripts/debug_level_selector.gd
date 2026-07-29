extends CanvasLayer

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const CAMPAIGN_SCENE_PATH := "res://scenes/campaign_runner.tscn"
const LEVEL_EDITOR_PATH := "res://scenes/level_editor.tscn"
const DEFAULT_EDITOR_RETURN_PATH := CAMPAIGN_SCENE_PATH

@onready var menu: Control = $Menu
@onready var arena_list: RichTextLabel = $Menu/Panel/ArenaList
@onready var current_label: Label = $Menu/Panel/Current
@onready var hint: Label = $Hint

var campaign_entries: Array[Dictionary] = []
var campaign_load_errors: Array[String] = []
var selected_index := 0
var previous_tree_paused := false
var context_suppressed := false
var editor_return_scene_path := DEFAULT_EDITOR_RETURN_PATH
var requested_campaign_level_id := ""


func _ready() -> void:
	_refresh_campaign_entries()
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
	if campaign_entries.is_empty():
		return

	selected_index = posmod(
		selected_index + offset,
		campaign_entries.size()
	)
	_render_menu()


func _load_arena(index: int) -> void:
	if index < 0 or index >= campaign_entries.size():
		return

	var level_id := str(campaign_entries[index].get("id", ""))
	if level_id.is_empty():
		push_error("Debug campaign entry %d has no level ID." % index)
		return

	selected_index = index
	remember_requested_campaign_level_id(level_id)

	var runner := _active_campaign_runner()
	if is_instance_valid(runner):
		_close_menu()
		if bool(runner.call("open_level_by_id", level_id)):
			return

		push_error(
			"Campaign runner could not open debug level '%s'."
			% level_id
		)
		return

	if not ResourceLoader.exists(CAMPAIGN_SCENE_PATH):
		push_error(
			"Campaign scene does not exist: %s"
			% CAMPAIGN_SCENE_PATH
		)
		return

	_load_scene(CAMPAIGN_SCENE_PATH, "campaign")


func _open_level_editor() -> void:
	var current_scene := get_tree().current_scene
	if is_instance_valid(current_scene):
		var current_level_id := _current_campaign_level_id()
		if not current_level_id.is_empty():
			remember_requested_campaign_level_id(current_level_id)

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


func remember_requested_campaign_level_id(level_id: String) -> void:
	var index := _campaign_index_for_id(level_id)
	if index < 0:
		requested_campaign_level_id = ""
		return

	requested_campaign_level_id = level_id
	selected_index = index


func get_requested_campaign_level_id() -> String:
	return requested_campaign_level_id


func _load_scene(scene_path: String, description: String) -> void:
	_close_menu()
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		push_error(
			"Could not open %s '%s' (error %d)."
			% [description, scene_path, change_error]
		)


func _current_arena_index() -> int:
	if campaign_entries.is_empty():
		return 0

	var current_index := _campaign_index_for_id(
		_current_campaign_level_id()
	)
	if current_index >= 0:
		return current_index

	var requested_index := _campaign_index_for_id(
		requested_campaign_level_id
	)
	if requested_index >= 0:
		return requested_index

	return clampi(selected_index, 0, campaign_entries.size() - 1)


func _digit_to_arena_index(event: InputEventKey) -> int:
	var digit := int(event.unicode) - 48
	if digit >= 1 and digit <= campaign_entries.size():
		return digit - 1

	var key := (
		event.physical_keycode
		if event.physical_keycode != 0
		else event.keycode
	)
	var key_index := -1
	match key:
		KEY_1, KEY_KP_1:
			key_index = 0
		KEY_2, KEY_KP_2:
			key_index = 1
		KEY_3, KEY_KP_3:
			key_index = 2
		KEY_4, KEY_KP_4:
			key_index = 3
		KEY_5, KEY_KP_5:
			key_index = 4
		KEY_6, KEY_KP_6:
			key_index = 5
		KEY_7, KEY_KP_7:
			key_index = 6
		KEY_8, KEY_KP_8:
			key_index = 7

	return (
		key_index
		if key_index >= 0 and key_index < campaign_entries.size()
		else -1
	)


func _render_menu() -> void:
	var lines := PackedStringArray()
	for index in range(campaign_entries.size()):
		var is_selected := index == selected_index
		var marker := "▶" if is_selected else " "
		var color := "#6fe0d0" if is_selected else "#a6b6d1"
		var title := str(
			campaign_entries[index].get(
				"title",
				campaign_entries[index].get("id", "ARENA")
			)
		)
		lines.append(
			"[color=%s]%s  [%d]  %s[/color]"
			% [color, marker, index + 1, title]
		)
	if campaign_entries.is_empty():
		lines.append(
			"[color=#f26d78]   КАМПАНИЯ НЕДОСТУПНА[/color]"
		)
		if not campaign_load_errors.is_empty():
			var error_summary := campaign_load_errors[0]
			error_summary = error_summary.replace("[", "(").replace("]", ")")
			lines.append(
				"[color=#f26d78]   %s[/color]" % error_summary
			)
	lines.append("[color=#f89444]   [E]  LEVEL EDITOR[/color]")

	arena_list.text = "\n".join(lines)
	if campaign_entries.is_empty():
		current_label.text = "СЕЙЧАС: КАМПАНИЯ НЕДОСТУПНА"
		return

	current_label.text = "СЕЙЧАС: %s" % campaign_entries[
		_current_arena_index()
	].get("title", "ARENA")


func _refresh_campaign_entries() -> void:
	campaign_entries.clear()
	campaign_load_errors.clear()
	var campaign_result: Dictionary = (
		CAMPAIGN_STORAGE.load_builtin_campaign()
	)
	if not bool(campaign_result.get("ok", false)):
		for error: Variant in campaign_result.get("errors", []):
			campaign_load_errors.append(str(error))
		for error: String in campaign_load_errors:
			push_error("Debug campaign unavailable: %s" % error)

	for raw_entry: Variant in campaign_result.get("entries", []):
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry := raw_entry as Dictionary
		var level_id := str(entry.get("id", ""))
		if level_id.is_empty():
			continue
		campaign_entries.append(
			{
				"id": level_id,
				"path": entry.get("path", ""),
				"title": entry.get("title", level_id),
			}
		)

	if campaign_entries.is_empty():
		selected_index = 0
		requested_campaign_level_id = ""
		return

	selected_index = clampi(
		selected_index,
		0,
		campaign_entries.size() - 1
	)
	if (
		not requested_campaign_level_id.is_empty()
		and _campaign_index_for_id(requested_campaign_level_id) < 0
	):
		requested_campaign_level_id = ""


func _campaign_index_for_id(level_id: String) -> int:
	if level_id.is_empty():
		return -1

	for index in campaign_entries.size():
		if str(campaign_entries[index].get("id", "")) == level_id:
			return index
	return -1


func _active_campaign_runner() -> Node:
	var current_scene := get_tree().current_scene
	if (
		is_instance_valid(current_scene)
		and current_scene.has_method("open_level_by_id")
		and current_scene.has_method("get_current_level_id")
	):
		return current_scene
	return null


func _current_campaign_level_id() -> String:
	var runner := _active_campaign_runner()
	if not is_instance_valid(runner):
		return ""
	return str(runner.call("get_current_level_id"))

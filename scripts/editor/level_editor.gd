class_name LevelEditor
extends Node

const LEVEL_DRAFT := preload(
	"res://scripts/editor/level_draft.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)
const PLAYTEST_SCENE := preload(
	"res://scenes/data_arena_01.tscn"
)

const TOOL_SELECT := "select"
const TOOL_SOLID := "solid_rect"
const TOOL_PLAYER := "player_spawn"
const TOOL_PATROL := "patrol_enemy"

@onready var editor_view: Control = $EditorView
@onready var discard_dialog: ConfirmationDialog = $DiscardDialog
@onready var playtest_host: Node2D = $PlaytestHost
@onready var playtest_overlay: CanvasLayer = $PlaytestOverlay
@onready var return_button: Button = $PlaytestOverlay/ReturnButton

@onready var canvas: LevelEditorCanvas = $EditorView/EditorCanvas
@onready var dirty_label: Label = $EditorView/Toolbar/DirtyLabel
@onready var exit_button: Button = $EditorView/Toolbar/ExitButton
@onready var undo_button: Button = $EditorView/Toolbar/UndoButton
@onready var redo_button: Button = $EditorView/Toolbar/RedoButton
@onready var test_button: Button = $EditorView/Toolbar/TestButton

@onready var select_button: Button = (
	$EditorView/PalettePanel/SelectButton
)
@onready var solid_button: Button = (
	$EditorView/PalettePanel/SolidButton
)
@onready var player_button: Button = (
	$EditorView/PalettePanel/PlayerButton
)
@onready var patrol_button: Button = (
	$EditorView/PalettePanel/PatrolButton
)
@onready var duplicate_button: Button = (
	$EditorView/PalettePanel/DuplicateButton
)
@onready var delete_button: Button = (
	$EditorView/PalettePanel/DeleteButton
)

@onready var level_id_edit: LineEdit = (
	$EditorView/ProblemsPanel/LevelIdEdit
)
@onready var title_edit: LineEdit = (
	$EditorView/ProblemsPanel/TitleEdit
)
@onready var objective_edit: LineEdit = (
	$EditorView/ProblemsPanel/ObjectiveEdit
)
@onready var validation_chip: Label = (
	$EditorView/ProblemsPanel/ValidationChip
)
@onready var problems: RichTextLabel = (
	$EditorView/ProblemsPanel/Problems
)

@onready var load_options: OptionButton = (
	$EditorView/InspectorPanel/LoadOptions
)
@onready var new_button: Button = $EditorView/InspectorPanel/NewButton
@onready var load_button: Button = $EditorView/InspectorPanel/LoadButton
@onready var save_button: Button = $EditorView/InspectorPanel/SaveButton
@onready var inspector_title: Label = (
	$EditorView/InspectorPanel/InspectorTitle
)
@onready var properties: VBoxContainer = (
	$EditorView/InspectorPanel/PropertiesScroll/Properties
)

var draft: LevelDraft = LEVEL_DRAFT.new()
var selected_id := ""
var active_tool := TOOL_SELECT
var validation_result: Dictionary = {}
var load_entries: Array[Dictionary] = []
var playtest_runtime: LevelRuntimeArena
var playtest_snapshot_json := ""
var playtest_generation := 0
var playtest_transitioning := false
var source_label := "ПРИМЕР"
var notice_text := ""
var notice_is_error := false
var syncing_ui := false
var pending_destructive_action := ""
var pending_load_index := -1
var pending_save_level_id := ""
var loaded_user_level_id := ""


func _ready() -> void:
	_connect_ui()
	draft.changed.connect(_on_draft_changed)
	_set_debug_selector_suppressed(true)
	var storage_notice := _refresh_load_options()

	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_arena_01()
	if bool(loaded.get("ok", false)):
		source_label = "ПРИМЕР"
		draft.replace(loaded["data"], true)
		_set_notice(
			_append_storage_notice(
				"Загружен встроенный пример Arena 01.",
				storage_notice
			),
			not storage_notice.is_empty()
		)
	else:
		source_label = "НОВЫЙ"
		var id_result: Dictionary = (
			LEVEL_STORAGE.next_available_level_id("my_arena")
		)
		var fallback_id := (
			str(id_result["data"])
			if bool(id_result.get("ok", false))
			else "my_arena"
		)
		var default_result: Dictionary = (
			LEVEL_STORAGE.make_default_level(fallback_id)
		)
		if bool(default_result.get("ok", false)):
			draft.replace(default_result["data"], false)
			_set_notice(
				_append_storage_notice(
					"Не удалось открыть пример; создан новый уровень.",
					storage_notice
				),
				true
			)

	_set_tool(TOOL_SELECT)


func _exit_tree() -> void:
	_set_debug_selector_suppressed(false)


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if (
		(
			is_instance_valid(playtest_runtime)
			or playtest_transitioning
		)
		and is_instance_valid(key_event)
		and key_event.pressed
		and not key_event.echo
		and _event_key(key_event) == KEY_ESCAPE
	):
		_stop_playtest()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if (
		not is_instance_valid(key_event)
		or not key_event.pressed
		or key_event.echo
		or is_instance_valid(playtest_runtime)
		or playtest_transitioning
	):
		return

	var key := _event_key(key_event)
	if key == KEY_F5:
		_start_playtest()
		get_viewport().set_input_as_handled()
		return

	if _text_field_has_focus():
		return

	var command_pressed := key_event.ctrl_pressed or key_event.meta_pressed
	if command_pressed:
		if key == KEY_Z and key_event.shift_pressed:
			_redo()
		elif key == KEY_Z:
			_undo()
		elif key == KEY_Y:
			_redo()
		elif key == KEY_D:
			_duplicate_selected()
		elif key == KEY_S:
			_save_level()
		elif key == KEY_N:
			_new_level()
		elif key == KEY_O:
			_load_selected_level()
		else:
			return
		get_viewport().set_input_as_handled()
		return

	match key:
		KEY_Q:
			_set_tool(TOOL_SELECT)
		KEY_1:
			_set_tool(TOOL_SOLID)
		KEY_2:
			_set_tool(TOOL_PLAYER)
		KEY_3:
			_set_tool(TOOL_PATROL)
		KEY_DELETE, KEY_BACKSPACE:
			_delete_selected()
		KEY_LEFT:
			_nudge_selected(Vector2i.LEFT, key_event.shift_pressed)
		KEY_RIGHT:
			_nudge_selected(Vector2i.RIGHT, key_event.shift_pressed)
		KEY_UP:
			_nudge_selected(Vector2i.UP, key_event.shift_pressed)
		KEY_DOWN:
			_nudge_selected(Vector2i.DOWN, key_event.shift_pressed)
		KEY_ESCAPE:
			if active_tool != TOOL_SELECT:
				_set_tool(TOOL_SELECT)
			elif not selected_id.is_empty():
				_select_object("")
			else:
				_request_return_to_game()
		_:
			return

	get_viewport().set_input_as_handled()


func _connect_ui() -> void:
	var tool_group := ButtonGroup.new()
	for button: Button in [
		select_button,
		solid_button,
		player_button,
		patrol_button,
	]:
		button.button_group = tool_group

	select_button.pressed.connect(_set_tool.bind(TOOL_SELECT))
	solid_button.pressed.connect(_set_tool.bind(TOOL_SOLID))
	player_button.pressed.connect(_set_tool.bind(TOOL_PLAYER))
	patrol_button.pressed.connect(_set_tool.bind(TOOL_PATROL))
	duplicate_button.pressed.connect(_duplicate_selected)
	delete_button.pressed.connect(_delete_selected)

	undo_button.pressed.connect(_undo)
	redo_button.pressed.connect(_redo)
	test_button.pressed.connect(_start_playtest)
	exit_button.pressed.connect(_request_return_to_game)
	return_button.pressed.connect(_stop_playtest)

	new_button.pressed.connect(_new_level)
	load_button.pressed.connect(_load_selected_level)
	save_button.pressed.connect(_save_level)
	discard_dialog.confirmed.connect(_on_discard_confirmed)
	discard_dialog.canceled.connect(_clear_pending_destructive_action)

	canvas.selection_requested.connect(_select_object)
	canvas.placement_requested.connect(_place_object)
	canvas.move_requested.connect(_move_object)
	canvas.nudge_requested.connect(_nudge_selected)

	_connect_metadata_field(level_id_edit, "level_id")
	_connect_metadata_field(title_edit, "title")
	_connect_metadata_field(objective_edit, "objective")


func _connect_metadata_field(field: LineEdit, key: String) -> void:
	field.text_submitted.connect(
		func(_text: String) -> void:
			_commit_metadata_field(field, key)
	)
	field.focus_exited.connect(
		func() -> void:
			_commit_metadata_field(field, key)
	)


func _on_draft_changed() -> void:
	if (
		not selected_id.is_empty()
		and draft.find_object(selected_id).is_empty()
	):
		selected_id = ""

	var document := draft.to_dictionary()
	canvas.set_document(document)
	canvas.set_selected_id(selected_id)
	validation_result = (
		LEVEL_DATA_VALIDATOR.validate_and_normalize(document)
	)
	_sync_metadata_fields(document)
	_rebuild_inspector()
	_refresh_validation()
	_refresh_buttons()


func _sync_metadata_fields(document: Dictionary) -> void:
	syncing_ui = true
	if not level_id_edit.has_focus():
		level_id_edit.text = str(document.get("level_id", ""))
	if not title_edit.has_focus():
		title_edit.text = str(document.get("title", ""))
	if not objective_edit.has_focus():
		objective_edit.text = str(document.get("objective", ""))
	syncing_ui = false


func _refresh_validation() -> void:
	var is_valid := bool(validation_result.get("ok", false))
	var errors: Array = validation_result.get("errors", [])
	var warnings: Array = validation_result.get("warnings", [])
	if is_valid:
		if warnings.is_empty():
			validation_chip.text = "✓  ГОТОВО К ТЕСТУ"
			validation_chip.modulate = Color(0.439, 0.878, 0.816)
			problems.text = (
				notice_text
				if not notice_text.is_empty()
				else "Ошибок нет. Можно сохранить или запустить тест."
			)
			problems.modulate = (
				Color(0.925, 0.365, 0.231)
				if notice_is_error
				else Color(0.651, 0.714, 0.82)
			)
		else:
			validation_chip.text = (
				"△  ГОТОВО / %d ПРЕДУПРЕЖДЕНИЙ"
				% warnings.size()
			)
			validation_chip.modulate = Color(0.973, 0.58, 0.267)
			var visible_warnings := PackedStringArray()
			for index in warnings.size():
				visible_warnings.append("△ %s" % warnings[index])
			problems.text = "\n".join(visible_warnings)
			problems.modulate = Color(0.973, 0.58, 0.267)
	else:
		validation_chip.text = "✕  %d ОШИБОК" % errors.size()
		validation_chip.modulate = Color(0.925, 0.365, 0.231)
		var visible_errors := PackedStringArray()
		for index in errors.size():
			visible_errors.append("• %s" % errors[index])
		problems.text = "\n".join(visible_errors)
		problems.modulate = Color(0.925, 0.58, 0.267)

	dirty_label.text = (
		"●  НЕ СОХРАНЕНО"
		if draft.is_dirty()
		else "✓  %s / СОХРАНЕНО" % source_label
	)
	dirty_label.modulate = (
		Color(0.973, 0.58, 0.267)
		if draft.is_dirty()
		else Color(0.439, 0.827, 0.816)
	)


func _refresh_buttons() -> void:
	var is_valid := bool(validation_result.get("ok", false))
	undo_button.disabled = not draft.can_undo()
	redo_button.disabled = not draft.can_redo()
	test_button.disabled = not is_valid
	save_button.disabled = not is_valid

	var selected := draft.find_object(selected_id)
	delete_button.disabled = selected.is_empty()
	duplicate_button.disabled = (
		selected.is_empty()
		or selected.get("type", "") == TOOL_PLAYER
	)


func _set_tool(tool: String) -> void:
	active_tool = tool
	canvas.set_tool(tool)
	select_button.set_pressed_no_signal(tool == TOOL_SELECT)
	solid_button.set_pressed_no_signal(tool == TOOL_SOLID)
	player_button.set_pressed_no_signal(tool == TOOL_PLAYER)
	patrol_button.set_pressed_no_signal(tool == TOOL_PATROL)


func _select_object(object_id: String) -> void:
	selected_id = object_id
	canvas.set_selected_id(selected_id)
	_rebuild_inspector()
	_refresh_buttons()


func _place_object(object_type: String, payload: Variant) -> void:
	notice_text = ""
	match object_type:
		TOOL_SOLID:
			var object_id := draft.make_unique_id("floor")
			selected_id = object_id
			draft.add_object(
				{
					"id": object_id,
					"type": TOOL_SOLID,
					"rect": (payload as Array).duplicate(),
				}
			)
		TOOL_PLAYER:
			var existing := draft.find_first_object_of_type(TOOL_PLAYER)
			if existing.is_empty():
				var object_id := draft.make_unique_id("player_start")
				selected_id = object_id
				draft.add_object(
					{
						"id": object_id,
						"type": TOOL_PLAYER,
						"position": (payload as Array).duplicate(),
					}
				)
			else:
				selected_id = existing["id"]
				draft.update_object(
					selected_id,
					{"position": (payload as Array).duplicate()}
				)
			_set_tool(TOOL_SELECT)
		TOOL_PATROL:
			var object_id := draft.make_unique_id("patrol")
			selected_id = object_id
			draft.add_object(
				{
					"id": object_id,
					"type": TOOL_PATROL,
					"position": (payload as Array).duplicate(),
					"speed": 65.0,
					"direction": 1,
				}
			)


func _move_object(object_id: String, payload: Variant) -> void:
	var object := draft.find_object(object_id)
	if object.is_empty():
		return

	selected_id = object_id
	var key := (
		"rect"
		if object.get("type", "") == TOOL_SOLID
		else "position"
	)
	draft.update_object(
		object_id,
		{key: (payload as Array).duplicate()}
	)


func _delete_selected() -> void:
	if selected_id.is_empty():
		return
	var deleted_id := selected_id
	selected_id = ""
	if draft.remove_object(deleted_id):
		_set_notice("Объект '%s' удалён." % deleted_id)


func _duplicate_selected() -> void:
	var object := draft.find_object(selected_id)
	if object.is_empty():
		return
	if object.get("type", "") == TOOL_PLAYER:
		_set_notice("В уровне может быть только один игрок.", true)
		return

	var duplicate := object.duplicate(true)
	var new_id := draft.make_unique_id("%s_copy" % object["id"])
	duplicate["id"] = new_id
	if duplicate["type"] == TOOL_SOLID:
		var rect: Array = duplicate["rect"]
		rect[0] = clampi(rect[0] + 20, 0, 960 - rect[2])
		rect[1] = clampi(rect[1] + 20, 0, 540 - rect[3])
		duplicate["rect"] = rect
	else:
		var position: Array = duplicate["position"]
		position[0] = clampi(position[0] + 20, 0, 959)
		position[1] = clampi(position[1] + 20, 0, 539)
		duplicate["position"] = position

	selected_id = new_id
	draft.add_object(duplicate)


func _nudge_selected(direction: Vector2i, fine: bool) -> void:
	var object := draft.find_object(selected_id)
	if object.is_empty():
		return

	var grid_size: int = draft.to_dictionary().get(
		"canvas",
		{}
	).get("grid_size", 20)
	var amount := 1 if fine else grid_size
	var delta := direction * amount
	if object["type"] == TOOL_SOLID:
		var rect: Array = object["rect"]
		rect[0] = clampi(rect[0] + delta.x, 0, 960 - rect[2])
		rect[1] = clampi(rect[1] + delta.y, 0, 540 - rect[3])
		draft.update_object(selected_id, {"rect": rect})
	else:
		var position: Array = object["position"]
		position[0] = clampi(position[0] + delta.x, 0, 959)
		position[1] = clampi(position[1] + delta.y, 0, 539)
		draft.update_object(selected_id, {"position": position})


func _undo() -> void:
	if draft.undo():
		_set_notice("Undo.")


func _redo() -> void:
	if draft.redo():
		_set_notice("Redo.")


func _new_level() -> void:
	if draft.is_dirty():
		_show_confirmation(
			"Несохранённые изменения",
			"Текущий черновик изменён. Отбросить изменения?",
			"ОТБРОСИТЬ",
			"new"
		)
		return
	_create_new_level()


func _create_new_level() -> void:
	_release_text_focus()
	var id_result: Dictionary = (
		LEVEL_STORAGE.next_available_level_id("my_arena")
	)
	if not bool(id_result.get("ok", false)):
		_set_notice(
			"Новый уровень не создан: %s" % _first_error(id_result),
			true
		)
		return

	var level_id := str(id_result["data"])
	var default_result: Dictionary = (
		LEVEL_STORAGE.make_default_level(level_id)
	)
	if not bool(default_result.get("ok", false)):
		_set_notice(
			"Новый уровень не создан: %s"
			% _first_error(default_result),
			true
		)
		return

	source_label = "НОВЫЙ"
	loaded_user_level_id = ""
	selected_id = ""
	draft.replace(default_result["data"], false)
	_set_tool(TOOL_SELECT)
	_set_notice("Создан новый черновик '%s'." % level_id)


func _load_selected_level() -> void:
	if load_entries.is_empty():
		return

	var selected := load_options.selected
	if selected < 0 or selected >= load_entries.size():
		return

	if draft.is_dirty():
		_show_confirmation(
			"Несохранённые изменения",
			"Текущий черновик изменён. Отбросить изменения?",
			"ОТБРОСИТЬ",
			"load",
			selected
		)
		return
	_perform_load_selected_level(selected)


func _perform_load_selected_level(selected: int) -> void:
	_release_text_focus()
	var entry: Dictionary = load_entries[selected]
	if entry["kind"] == "invalid":
		_set_notice(
			"Этот уровень повреждён и не может быть загружен.",
			true
		)
		return

	var result: Dictionary
	var loaded_source := ""
	if entry["kind"] == "builtin":
		result = LEVEL_STORAGE.load_builtin_arena_01()
		loaded_source = "ПРИМЕР"
	else:
		result = LEVEL_STORAGE.load_user_level(entry["id"])
		loaded_source = "USER"

	if not bool(result.get("ok", false)):
		_set_notice(
			_append_storage_notice(
				(
					"Не удалось загрузить уровень: %s"
					% _first_error(result)
				),
				_storage_notice_from_result(result)
			),
			true
		)
		return

	var storage_notice := _storage_notice_from_result(result)
	source_label = loaded_source
	loaded_user_level_id = (
		str(result["data"]["level_id"])
		if entry["kind"] == "user"
		else ""
	)
	selected_id = ""
	draft.replace(result["data"], true)
	_set_tool(TOOL_SELECT)
	_set_notice(
		_append_storage_notice(
			"Уровень '%s' загружен." % result["data"]["level_id"],
			storage_notice
		),
		not storage_notice.is_empty()
	)


func _on_discard_confirmed() -> void:
	var action := pending_destructive_action
	var load_index := pending_load_index
	var save_level_id := pending_save_level_id
	_clear_pending_destructive_action()
	if action == "new":
		_create_new_level()
	elif action == "load" and load_index >= 0:
		_perform_load_selected_level(load_index)
	elif action == "overwrite" and not save_level_id.is_empty():
		_perform_save_level(save_level_id)
	elif action == "exit":
		_perform_return_to_game()


func _clear_pending_destructive_action() -> void:
	pending_destructive_action = ""
	pending_load_index = -1
	pending_save_level_id = ""


func _show_confirmation(
	title: String,
	message: String,
	confirm_text: String,
	action: String,
	load_index := -1,
	save_level_id := ""
) -> void:
	pending_destructive_action = action
	pending_load_index = load_index
	pending_save_level_id = save_level_id
	discard_dialog.title = title
	discard_dialog.dialog_text = message
	discard_dialog.ok_button_text = confirm_text
	discard_dialog.cancel_button_text = "ОСТАТЬСЯ"
	discard_dialog.popup_centered()


func _save_level() -> void:
	_commit_all_metadata()
	if not bool(validation_result.get("ok", false)):
		_set_notice("Сначала исправьте ошибки уровня.", true)
		return

	var level_id := str(draft.to_dictionary().get("level_id", ""))
	var exists_result: Dictionary = LEVEL_STORAGE.user_level_exists(
		level_id
	)
	var exists_notice := _storage_notice_from_result(exists_result)
	if not bool(exists_result.get("ok", false)):
		_set_notice(
			_append_storage_notice(
				(
					"Сохранение не удалось: %s"
					% _first_error(exists_result)
				),
				exists_notice
			),
			true
		)
		return
	if (
		bool(exists_result.get("data", false))
		and loaded_user_level_id != level_id
	):
		if not exists_notice.is_empty():
			_set_notice(exists_notice, true)
		_show_confirmation(
			"Перезаписать уровень?",
			(
				"Пользовательский уровень '%s' уже существует. "
				+ "Заменить его текущим черновиком?"
			)
			% level_id,
			"ПЕРЕЗАПИСАТЬ",
			"overwrite",
			-1,
			level_id
		)
		return

	_perform_save_level(level_id)


func _perform_save_level(expected_level_id: String) -> void:
	if (
		str(draft.to_dictionary().get("level_id", ""))
		!= expected_level_id
	):
		_set_notice(
			"ID уровня изменился; повторите сохранение.",
			true
		)
		return

	var result: Dictionary = LEVEL_STORAGE.save_user_level(
		draft.to_dictionary()
	)
	var result_notice := _storage_notice_from_result(result)
	if not bool(result.get("ok", false)):
		_set_notice(
			_append_storage_notice(
				"Сохранение не удалось: %s" % _first_error(result),
				result_notice
			),
			true
		)
		return

	source_label = "USER"
	loaded_user_level_id = expected_level_id
	draft.mark_saved()
	var storage_notice := _refresh_load_options(
		result["data"]["level_id"]
	)
	storage_notice = _combine_storage_notices(
		result_notice,
		storage_notice
	)
	_set_notice(
		_append_storage_notice(
			(
				"Сохранено: user://levels/%s.json"
				% result["data"]["level_id"]
			),
			storage_notice
		),
		not storage_notice.is_empty()
	)


func _request_return_to_game() -> void:
	_commit_all_metadata()
	if draft.is_dirty():
		_show_confirmation(
			"Выйти из редактора?",
			"Текущий черновик изменён. Выйти без сохранения?",
			"ВЫЙТИ",
			"exit"
		)
		return
	_perform_return_to_game()


func _perform_return_to_game() -> void:
	var scene_path := "res://scenes/arena_01.tscn"
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("get_editor_return_scene_path")
	):
		scene_path = str(
			selector.call("get_editor_return_scene_path")
		)

	if not ResourceLoader.exists(scene_path):
		_set_notice(
			"Не найдена сцена для возврата: %s" % scene_path,
			true
		)
		return

	_set_debug_selector_suppressed(false)
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		_set_debug_selector_suppressed(true)
		_set_notice(
			"Не удалось вернуться в игру (ошибка %d)." % change_error,
			true
		)


func _refresh_load_options(select_id := "") -> String:
	load_entries.clear()
	load_options.clear()
	load_entries.append(
		{
			"kind": "builtin",
			"id": "arena_01_data",
			"title": "★ Пример: Arena 01",
		}
	)
	load_options.add_item("★ Пример: Arena 01")

	var result: Dictionary = LEVEL_STORAGE.list_user_levels()
	for entry: Dictionary in result.get("entries", []):
		if not bool(entry.get("ok", false)):
			var invalid_index := load_entries.size()
			var invalid_id := str(entry.get("level_id", "unknown"))
			load_entries.append(
				{
					"kind": "invalid",
					"id": invalid_id,
					"title": "ТРЕБУЕТ ВНИМАНИЯ",
					"errors": entry.get("errors", []),
				}
			)
			load_options.add_item(
				"⚠ %s / ТРЕБУЕТ ВНИМАНИЯ" % invalid_id
			)
			load_options.set_item_disabled(invalid_index, true)
			load_options.set_item_tooltip(
				invalid_index,
				_first_error(entry)
			)
			continue
		var level_id := str(entry["level_id"])
		load_entries.append(
			{
				"kind": "user",
				"id": level_id,
				"title": entry["title"],
			}
		)
		load_options.add_item("%s  /  %s" % [level_id, entry["title"]])

	if not select_id.is_empty():
		for index in load_entries.size():
			if load_entries[index]["id"] == select_id:
				load_options.select(index)

	var storage_messages := PackedStringArray()
	var result_notice := _storage_notice_from_result(result)
	if not result_notice.is_empty():
		storage_messages.append(result_notice)
	for entry: Dictionary in result.get("entries", []):
		if bool(entry.get("ok", false)):
			continue
		storage_messages.append(
			"Уровень '%s' требует внимания: %s"
			% [entry.get("level_id", "?"), _first_error(entry)]
		)
	return "\n".join(storage_messages)


func _start_playtest() -> void:
	if is_instance_valid(playtest_runtime) or playtest_transitioning:
		return
	_commit_all_metadata()

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(
		draft.to_dictionary()
	)
	if not bool(encoded.get("ok", false)):
		validation_result = encoded
		_refresh_validation()
		_refresh_buttons()
		_set_notice("Тест заблокирован: исправьте ошибки.", true)
		return

	playtest_snapshot_json = encoded["text"]
	playtest_generation += 1
	editor_view.visible = false
	editor_view.process_mode = Node.PROCESS_MODE_DISABLED
	playtest_overlay.visible = true
	_spawn_playtest(playtest_generation)


func _spawn_playtest(generation: int) -> void:
	if (
		generation != playtest_generation
		or playtest_snapshot_json.is_empty()
	):
		return

	var runtime := PLAYTEST_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(playtest_snapshot_json)
	runtime.embedded_restart_requested.connect(
		_on_playtest_restart_requested.bind(runtime, generation)
	)
	playtest_host.add_child(runtime)
	playtest_runtime = runtime
	playtest_transitioning = false


func _on_playtest_restart_requested(
	runtime: LevelRuntimeArena,
	generation: int
) -> void:
	if (
		runtime != playtest_runtime
		or generation != playtest_generation
		or playtest_transitioning
	):
		return

	playtest_transitioning = true
	playtest_runtime = null
	runtime.queue_free()
	await runtime.tree_exited
	if (
		generation == playtest_generation
		and not playtest_snapshot_json.is_empty()
	):
		_spawn_playtest(generation)


func _stop_playtest() -> void:
	if (
		not is_instance_valid(playtest_runtime)
		and not playtest_transitioning
	):
		return

	playtest_generation += 1
	playtest_snapshot_json = ""
	playtest_transitioning = false
	if is_instance_valid(playtest_runtime):
		playtest_runtime.queue_free()
	playtest_runtime = null
	playtest_overlay.visible = false
	editor_view.visible = true
	editor_view.process_mode = Node.PROCESS_MODE_INHERIT
	_set_notice("Возврат из теста: черновик и Undo/Redo сохранены.")
	canvas.grab_focus()


func _rebuild_inspector() -> void:
	syncing_ui = true
	for child: Node in properties.get_children():
		child.queue_free()

	var object := draft.find_object(selected_id)
	if object.is_empty():
		inspector_title.text = "СВОЙСТВА УРОВНЯ"
		_add_readonly_property("SCHEMA", "1")
		_add_root_text_property(
			"CLEAR TEXT",
			"clear_message",
			str(
				draft.to_dictionary().get(
					"clear_message",
					"АРЕНА ПРОЙДЕНА"
				)
			)
		)
		syncing_ui = false
		return

	inspector_title.text = "СВОЙСТВА ОБЪЕКТА"
	_add_readonly_property("TYPE", str(object["type"]))
	_add_readonly_property("ID", str(object["id"]))
	match object["type"]:
		TOOL_SOLID:
			var rect: Array = object["rect"]
			_add_numeric_property("X", "rect:0", rect[0])
			_add_numeric_property("Y", "rect:1", rect[1])
			_add_numeric_property("WIDTH", "rect:2", rect[2])
			_add_numeric_property("HEIGHT", "rect:3", rect[3])
		TOOL_PLAYER:
			var position: Array = object["position"]
			_add_numeric_property("X", "position:0", position[0])
			_add_numeric_property("Y", "position:1", position[1])
		TOOL_PATROL:
			var position: Array = object["position"]
			_add_numeric_property("X", "position:0", position[0])
			_add_numeric_property("Y", "position:1", position[1])
			_add_numeric_property("SPEED", "speed", object["speed"], true)
			_add_direction_property(int(object["direction"]))
	syncing_ui = false


func _add_readonly_property(label_text: String, value: String) -> void:
	var row := _make_property_row(label_text)
	var value_label := Label.new()
	value_label.text = value
	value_label.modulate = Color(0.651, 0.714, 0.82)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value_label)


func _add_numeric_property(
	label_text: String,
	key: String,
	value: Variant,
	is_float := false
) -> void:
	var target_id := selected_id
	var row := _make_property_row(label_text)
	var field := LineEdit.new()
	field.text = str(value)
	field.custom_minimum_size = Vector2(104, 28)
	field.select_all_on_focus = true
	field.set_meta("is_float", is_float)
	field.text_submitted.connect(
		func(_text: String) -> void:
			_commit_object_property(field, key, target_id)
	)
	field.focus_exited.connect(
		func() -> void:
			_commit_object_property(field, key, target_id)
	)
	row.add_child(field)


func _add_root_text_property(
	label_text: String,
	key: String,
	value: String
) -> void:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.439, 0.502, 0.616)
	properties.add_child(label)

	var field := LineEdit.new()
	field.text = value
	field.custom_minimum_size = Vector2(184, 30)
	field.text_submitted.connect(
		func(_text: String) -> void:
			_commit_metadata_field(field, key)
	)
	field.focus_exited.connect(
		func() -> void:
			_commit_metadata_field(field, key)
	)
	properties.add_child(field)


func _add_direction_property(current: int) -> void:
	var target_id := selected_id
	var row := _make_property_row("DIRECTION")
	var options := OptionButton.new()
	options.add_item("←  -1")
	options.add_item("→  +1")
	options.select(0 if current == -1 else 1)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.item_selected.connect(
		func(index: int) -> void:
			if syncing_ui:
				return
			var direction := -1 if index == 0 else 1
			draft.update_object(
				target_id,
				{"direction": direction}
			)
	)
	row.add_child(options)


func _make_property_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(72, 28)
	label.modulate = Color(0.439, 0.502, 0.616)
	row.add_child(label)
	properties.add_child(row)
	return row


func _commit_object_property(
	field: LineEdit,
	key: String,
	target_id: String
) -> void:
	if syncing_ui or target_id.is_empty():
		return

	var text := field.text.strip_edges()
	var is_float: bool = bool(field.get_meta("is_float", false))
	if (
		(is_float and not text.is_valid_float())
		or (not is_float and not text.is_valid_int())
	):
		_set_notice("Введите корректное число.", true)
		_rebuild_inspector()
		return

	var value: Variant = text.to_float() if is_float else text.to_int()
	if is_float and not is_finite(float(value)):
		_set_notice("Число должно быть конечным.", true)
		_rebuild_inspector()
		return

	var object := draft.find_object(target_id)
	if object.is_empty():
		return

	if ":" in key:
		var parts := key.split(":")
		var array_key: String = parts[0]
		var index := int(parts[1])
		var values: Array = object[array_key]
		values[index] = value
		draft.update_object(target_id, {array_key: values})
	else:
		draft.update_object(target_id, {key: value})


func _commit_metadata_field(field: LineEdit, key: String) -> void:
	if syncing_ui:
		return
	draft.set_root_value(key, field.text.strip_edges())


func _commit_all_metadata() -> void:
	var pending_values := {
		"level_id": level_id_edit.text.strip_edges(),
		"title": title_edit.text.strip_edges(),
		"objective": objective_edit.text.strip_edges(),
	}
	for key: String in pending_values:
		draft.set_root_value(key, pending_values[key])
	_release_text_focus()


func _release_text_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus_owner):
		focus_owner.release_focus()


func _text_field_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return (
		focus_owner is LineEdit
		or focus_owner is TextEdit
		or focus_owner is SpinBox
	)


func _set_notice(message: String, is_error := false) -> void:
	notice_text = message
	notice_is_error = is_error
	_refresh_validation()


func _append_storage_notice(
	primary: String,
	storage_notice: String
) -> String:
	if storage_notice.is_empty():
		return primary
	return "%s\n%s" % [primary, storage_notice]


func _combine_storage_notices(
	first: String,
	second: String
) -> String:
	if first.is_empty():
		return second
	if second.is_empty():
		return first
	return "%s\n%s" % [first, second]


func _storage_notice_from_result(result: Dictionary) -> String:
	var messages := PackedStringArray()
	for recovery: Dictionary in result.get("recoveries", []):
		var message := str(recovery.get("message", ""))
		if message.is_empty():
			message = "Recovery: %s" % recovery.get("path", "")
		if not messages.has(message):
			messages.append(message)
	for warning: Variant in result.get("warnings", []):
		var warning_message := str(warning)
		if (
			not warning_message.is_empty()
			and not messages.has(warning_message)
		):
			messages.append(warning_message)
	return "\n".join(messages)


func _first_error(result: Dictionary) -> String:
	var errors: Array = result.get("errors", [])
	return str(errors[0]) if not errors.is_empty() else "неизвестная ошибка"


func _event_key(event: InputEventKey) -> Key:
	return (
		event.physical_keycode
		if event.physical_keycode != 0
		else event.keycode
	)


func _set_debug_selector_suppressed(suppressed: bool) -> void:
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("set_context_suppressed")
	):
		selector.call("set_context_suppressed", suppressed)

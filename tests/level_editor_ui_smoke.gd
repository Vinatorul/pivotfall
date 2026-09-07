extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const LEVEL_STORAGE := preload("res://scripts/levels/level_storage.gd")
const LEVEL_DATA_CODEC := preload("res://scripts/levels/level_data_codec.gd")

var failures: Array[String] = []
var temporary_level_id := ""
var exported_bytes := PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	_cleanup()


func _run() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.size = Vector2i(960, 540)
	root.add_child(editor)
	current_scene = editor
	await process_frame
	await _test_layout(editor)
	await _test_panel_state(editor)
	await _test_metadata(editor)
	await _test_inspector_fields(editor)
	await _test_shortcuts_and_escape(editor)
	await _test_modal_arrow_keys(editor)
	await _test_modal_tab_focus(editor)
	await _test_file_load_shortcut(editor)
	await _test_canvas_resize(editor)
	await _test_drag_escape(editor)
	await _test_validation(editor)
	await _test_file_error_notice(editor)
	await _test_file_commands(editor)
	await _test_playtest_return(editor)
	editor.queue_free()
	await editor.tree_exited
	_finish()


func _test_layout(editor: LevelEditor) -> void:
	var arena: Rect2 = editor.canvas.call("_canvas_view_rect")
	_expect(arena.size.x >= 780, "Collapsed inspector did not enlarge the drawn arena.")
	_expect(is_equal_approx(arena.size.x / arena.size.y, 16.0 / 9.0),
		"Drawn arena lost its 16:9 aspect ratio.")
	_expect(arena.get_area() >= 960.0 * 540.0 * 0.65,
		"Drawn arena still occupies less than 65 percent of the logical screen.")
	_expect(not editor.inspector_panel.visible, "Empty inspector starts expanded.")
	_expect(not editor.level_id_edit.is_visible_in_tree(), "Metadata is permanently visible.")
	_expect(not editor.problems.is_visible_in_tree(), "Diagnostics is permanently visible.")
	_expect(editor.tool_scroll.size.y >= 380, "Palette did not regain vertical space.")
	var screen := Rect2(Vector2.ZERO, Vector2(960, 540))
	for button: Button in [editor.file_button, editor.save_button, editor.undo_button,
		editor.redo_button, editor.test_button, editor.settings_button,
		editor.help_button, editor.exit_button, editor.validation_chip]:
		_expect(button.is_visible_in_tree() and screen.encloses(button.get_global_rect()),
			"A primary command is hidden or outside the 960x540 screen: %s" % button.name)


func _test_panel_state(editor: LevelEditor) -> void:
	var patrol := editor.draft.find_first_object_of_type("patrol_enemy")
	editor.call("_select_object", patrol["id"])
	editor.draft.set_root_value("title", "PANEL HISTORY FIRST")
	editor.draft.set_root_value("objective", "PANEL HISTORY SECOND")
	editor.call("_undo")
	var snapshot := _state(editor)
	for panel: Control in [editor.file_panel, editor.settings_panel,
		editor.help_panel, editor.problems_panel]:
		editor.call("_toggle_panel", panel)
		await process_frame
		_expect(panel.is_visible_in_tree(), "Requested panel did not open: %s" % panel.name)
		editor.call("_close_panel")
		await process_frame
		_expect(not panel.is_visible_in_tree(), "Panel did not close: %s" % panel.name)
		_expect(_state(editor) == snapshot, "Panel changed draft, selection, or history.")
	_expect(not editor.inspector_panel.visible, "Selection unexpectedly opened the inspector.")
	editor.inspector_button.pressed.emit()
	await process_frame
	_expect(editor.inspector_panel.visible, "Inspector command did not open properties.")
	editor.call("_toggle_inspector")
	await process_frame
	_expect(_state(editor) == snapshot, "Inspector visibility changed draft state.")


func _test_metadata(editor: LevelEditor) -> void:
	editor.settings_button.pressed.emit()
	await process_frame
	var title := "LONG LEVEL TITLE / " + "A title with room to read. ".repeat(2)
	editor.title_edit.grab_focus()
	editor.title_edit.text = title
	await _press_key(KEY_ENTER)
	_expect(editor.draft.to_dictionary()["title"] == title.strip_edges(), "Enter did not commit the title.")
	editor.objective_edit.grab_focus()
	editor.objective_edit.text = "Use the hinge, then cross the bridge."
	editor.clear_message_edit.grab_focus()
	await process_frame
	_expect(editor.draft.to_dictionary()["objective"] == editor.objective_edit.text,
		"Focus loss did not commit the objective.")
	editor.clear_message_edit.text = "CUSTOM CLEAR MESSAGE"
	await _press_key(KEY_ENTER)
	_expect(editor.draft.to_dictionary()["clear_message"] == "CUSTOM CLEAR MESSAGE",
		"Level settings lost the supported completion text.")
	_expect(editor.title_edit.size.x >= 400, "Level title is still confined to a narrow row.")
	await _press_key(KEY_ESCAPE)
	_expect(not editor.settings_panel.visible and not editor.discard_dialog.visible,
		"Escape from a focused field did not close only the settings panel.")


func _test_inspector_fields(editor: LevelEditor) -> void:
	editor.call("_toggle_inspector")
	await process_frame
	var speed := _property_field(editor, "SPEED")
	_expect(is_instance_valid(speed), "Selected patrol has no editable speed.")
	if not is_instance_valid(speed):
		return
	speed.grab_focus()
	speed.text = "73"
	await _press_key(KEY_ENTER)
	_expect(editor.draft.find_object(editor.selected_id)["speed"] == 73,
		"Enter did not commit an object property.")
	speed = _property_field(editor, "SPEED")
	speed.grab_focus()
	speed.text = "81"
	editor.canvas.grab_focus()
	await process_frame
	_expect(editor.draft.find_object(editor.selected_id)["speed"] == 81,
		"Leaving an object property did not commit it.")
	editor.call("_toggle_inspector")
	await process_frame


func _test_shortcuts_and_escape(editor: LevelEditor) -> void:
	editor.call("_set_tool", "solid_rect")
	editor.call("_toggle_panel", editor.settings_panel)
	editor.title_edit.grab_focus()
	await process_frame
	var snapshot := _state(editor)
	for key: Key in [KEY_P, KEY_K, KEY_Q, KEY_DELETE]:
		await _press_key(key)
	_expect(editor.active_tool == "solid_rect", "Text entry activated a palette shortcut.")
	_expect(editor.selected_id == snapshot["selected"], "Text entry changed selection.")
	editor.title_edit.text = snapshot["data"]["title"]
	await _press_key(KEY_ESCAPE)
	_expect(editor.active_tool == "solid_rect" and not editor.settings_panel.visible,
		"Escape closed settings and also changed the active tool.")
	editor.call("_new_level")
	await process_frame
	snapshot = _state(editor)
	_expect(editor.discard_dialog.visible, "New skipped the dirty-draft confirmation.")
	for key: Key in [KEY_P, KEY_DELETE, KEY_F5]:
		editor.call("_unhandled_key_input", _key_event(key, true))
	_expect(_state(editor) == snapshot and not is_instance_valid(editor.playtest_runtime),
		"A confirmation dialog allowed editor shortcuts or playtest.")
	await _press_key(KEY_ESCAPE)
	_expect(not editor.discard_dialog.visible and current_scene == editor,
		"Escape did not cancel only the confirmation dialog.")
	editor.call("_close_panel")
	editor.call("_set_tool", "select")


func _test_canvas_resize(editor: LevelEditor) -> void:
	editor.call("_set_tool", "solid_rect")
	await _drag(editor, Vector2(420, 320), Vector2(520, 360))
	var object_id := editor.selected_id
	_expect(editor.draft.find_object(object_id).get("rect") == [420, 320, 100, 40],
		"Enlarged arena placement did not use logical coordinates.")
	var wide_scale: float = editor.canvas.call("_canvas_scale")
	editor.call("_set_tool", "select")
	editor.call("_toggle_inspector")
	await process_frame
	_expect(float(editor.canvas.call("_canvas_scale")) < wide_scale,
		"Opening inspector did not yield canvas space.")
	await _drag(editor, Vector2(440, 340), Vector2(460, 340))
	_expect(editor.draft.find_object(object_id)["rect"] == [440, 320, 100, 40],
		"Inspector resize broke object hit-testing or snapped dragging.")
	editor.call("_undo")
	editor.call("_redo")
	_expect(editor.draft.find_object(object_id)["rect"][0] == 440,
		"Undo/Redo lost a move made with the smaller arena.")
	editor.call("_toggle_inspector")
	await process_frame
	await _drag(editor, Vector2(460, 340), Vector2(480, 340))
	_expect(editor.draft.find_object(object_id)["rect"][0] == 460,
		"Closing inspector left stale hit-test coordinates.")


func _test_modal_arrow_keys(editor: LevelEditor) -> void:
	for button: Button in [editor.help_button, editor.file_button, editor.validation_chip]:
		var snapshot := _state(editor)
		editor.canvas.grab_focus()
		await process_frame
		button.pressed.emit()
		await process_frame
		for key: Key in [KEY_RIGHT, KEY_LEFT, KEY_UP, KEY_DOWN]:
			var focus_before := _focused_control(editor)
			await _press_key(key)
			_expect(_state(editor) == snapshot,
				"Arrow %s changed draft behind %s; focus %s -> %s."
				% [key, button.name, focus_before, _focused_control(editor)])
		await _press_key(KEY_ESCAPE)
		_expect(_state(editor) == snapshot, "Closing a modal panel changed editor state.")


func _test_file_load_shortcut(editor: LevelEditor) -> void:
	editor.file_button.pressed.emit()
	await process_frame
	editor.load_options.select(0)
	var snapshot := _state(editor)
	await _press_key(KEY_O, true)
	_expect(editor.discard_dialog.visible and editor.pending_destructive_action == "load",
		"Ctrl+O inside the File panel did not request dirty-draft load confirmation.")
	_expect(_state(editor) == snapshot, "Ctrl+O loaded a level before confirmation.")
	await _press_key(KEY_ESCAPE)
	_expect(not editor.discard_dialog.visible and _state(editor) == snapshot,
		"Cancelling keyboard-initiated Load changed the draft, selection, or history.")
	editor.call("_close_panel")


func _test_modal_tab_focus(editor: LevelEditor) -> void:
	editor.call("_toggle_inspector")
	await process_frame
	var snapshot := _state(editor)
	editor.help_button.pressed.emit()
	await process_frame
	for index in 8:
		await _press_key(KEY_TAB)
		var control := editor.get_viewport().gui_get_focus_owner()
		_expect(is_instance_valid(control)
			and (control == editor.help_panel or editor.help_panel.is_ancestor_of(control)),
			"Tab %d escaped Help to %s while inspector was open."
			% [index, _focused_control(editor)])
	await _press_key(KEY_ESCAPE)
	_expect(_state(editor) == snapshot, "Modal Tab navigation changed draft or history.")
	editor.call("_toggle_inspector")
	await process_frame


func _test_drag_escape(editor: LevelEditor) -> void:
	var snapshot := _state(editor)
	editor.canvas.call("_begin_primary_action", _local(editor, Vector2(480, 340)))
	editor.canvas.call("_update_drag", _local(editor, Vector2(520, 340)))
	var scale_before: float = editor.canvas.call("_canvas_scale")
	editor.call("_toggle_inspector")
	await process_frame
	_expect(is_equal_approx(editor.canvas.call("_canvas_scale"), scale_before),
		"Inspector changed arena scale in the middle of a drag.")
	await _press_key(KEY_ESCAPE)
	_expect(not editor.canvas.get("_drag_active") and _state(editor) == snapshot,
		"Escape did not cancel only the pending object drag.")
	_expect(current_scene == editor, "Cancelling a drag exited the editor.")


func _test_validation(editor: LevelEditor) -> void:
	var original_id: String = editor.draft.to_dictionary()["level_id"]
	var size_before := editor.canvas.size
	editor.draft.set_root_value("level_id", "INVALID ID")
	await process_frame
	_expect(editor.save_button.disabled and editor.test_button.disabled
		and editor.export_button.disabled, "Invalid draft did not block Save, Test, and Export.")
	_expect(editor.validation_chip.is_visible_in_tree()
		and not editor.validation_chip.text.is_empty(), "Blocking errors have no visible status.")
	editor.validation_chip.pressed.emit()
	await process_frame
	_expect(editor.problems.is_visible_in_tree() and "level_id" in editor.problems.text,
		"Clicking error status did not explain the blocking error.")
	editor.call("_set_notice", "read failed / ".repeat(100), true)
	_expect(editor.canvas.size == size_before, "Long error text displaced the arena.")
	editor.call("_close_panel")
	editor.draft.set_root_value("level_id", original_id)
	editor.call("_set_notice", "", false)


func _test_file_commands(editor: LevelEditor) -> void:
	editor.call("_toggle_panel", editor.file_panel)
	await process_frame
	for control: Control in [editor.new_button, editor.load_options, editor.load_button,
		editor.import_button, editor.export_button]:
		_expect(control.is_visible_in_tree(), "File panel lost an operation: %s" % control.name)
	_expect(editor.load_options.size.x >= 400, "Library selector still truncates ordinary titles.")
	editor.load_options.select(0)
	editor.load_button.pressed.emit()
	_expect(editor.discard_dialog.visible, "Load discarded an unsaved draft without confirmation.")
	editor.discard_dialog.hide()
	editor.discard_dialog.canceled.emit()
	temporary_level_id = "ui_smoke_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	editor.draft.set_root_value("level_id", temporary_level_id)
	editor.save_button.pressed.emit()
	_expect(bool(LEVEL_STORAGE.load_user_level(temporary_level_id).get("ok", false))
		and not editor.draft.is_dirty(), "Save did not write a unique user copy: %s / %s" % [editor.notice_text, editor.validation_result])
	_expect(editor.file_transfer.configure_for_tests(_fake_export, _fake_import),
		"Could not configure the existing file-transfer test seam.")
	editor.export_button.pressed.emit()
	_expect(not exported_bytes.is_empty(), "Export no longer uses the existing transfer path: %s" % editor.notice_text)
	await _test_import_confirmation(editor)


func _test_file_error_notice(editor: LevelEditor) -> void:
	var patrol := editor.draft.find_first_object_of_type("patrol_enemy")
	for invalid in [false, true]:
		if invalid:
			editor.draft.set_root_value("level_id", "INVALID ID")
		else:
			editor.draft.update_object(patrol["id"], {"speed": 0})
		var diagnostic := "errors" if invalid else "warnings"
		_expect(not editor.validation_result.get(diagnostic, []).is_empty(),
			"File notice fixture has no validation %s." % diagnostic)
		await _test_visible_transfer_failure(editor)
		editor.draft.undo()
		await process_frame
		editor.call("_set_notice", "", false)


func _test_visible_transfer_failure(editor: LevelEditor) -> void:
	var message := "browser read failed\nThe chosen file could not be read. Retry the import."
	var snapshot := _state(editor)
	editor.file_button.pressed.emit()
	await process_frame
	editor.call("_on_file_transfer_failed", message)
	var notice := editor.file_panel.get_node("NoticeButton") as Button
	_expect(notice.is_visible_in_tree() and "browser read failed" in notice.text,
		"File panel swallowed a transfer failure behind existing validation diagnostics.")
	_expect(message in notice.tooltip_text, "File notice tooltip lost transfer failure details.")
	notice.pressed.emit()
	await process_frame
	_expect(editor.problems.is_visible_in_tree() and message in editor.problems.text,
		"File notice did not open the complete multiline transfer failure.")
	_expect(_state(editor) == snapshot, "Showing a file failure changed draft or history.")
	editor.call("_close_panel")


func _test_import_confirmation(editor: LevelEditor) -> void:
	var exported := LEVEL_DATA_CODEC.decode_text(exported_bytes.get_string_from_utf8())
	editor.draft.set_root_value("objective", "UNSAVED AFTER EXPORT")
	var snapshot := _state(editor)
	editor.import_button.pressed.emit()
	_expect(editor.discard_dialog.visible, "Import skipped dirty/overwrite confirmation.")
	editor.discard_dialog.hide()
	editor.discard_dialog.canceled.emit()
	_expect(_state(editor) == snapshot, "Cancelling Import changed draft or history.")
	editor.import_button.pressed.emit()
	editor.discard_dialog.hide()
	editor.call("_on_discard_confirmed")
	_expect(editor.draft.to_dictionary() == exported.get("data", {})
		and not editor.draft.is_dirty(), "Confirmed Import did not reopen the exported user copy.")
	editor.call("_close_panel")


func _test_playtest_return(editor: LevelEditor) -> void:
	var patrol := editor.draft.find_first_object_of_type("patrol_enemy")
	editor.call("_select_object", patrol["id"])
	editor.draft.set_root_value("objective", "PLAYTEST HISTORY")
	editor.draft.set_root_value("title", "PLAYTEST REDO")
	editor.call("_undo")
	var snapshot := _state(editor)
	editor.test_button.pressed.emit()
	await process_frame
	_expect(is_instance_valid(editor.playtest_runtime), "Toolbar Test did not start the draft: %s" % editor.notice_text)
	await _press_key(KEY_ESCAPE)
	await process_frame
	_expect(not is_instance_valid(editor.playtest_runtime) and _state(editor) == snapshot,
		"Return from Test changed draft, selection, or complete Undo/Redo history.")


func _state(editor: LevelEditor) -> Dictionary:
	return {
		"data": editor.draft.to_dictionary(), "selected": editor.selected_id,
		"undo": editor.draft.get("_undo_stack").duplicate(true),
		"redo": editor.draft.get("_redo_stack").duplicate(true),
		"dirty": editor.draft.is_dirty(),
	}


func _property_field(editor: LevelEditor, label_text: String) -> LineEdit:
	for row: Node in editor.properties.get_children():
		if row is HBoxContainer and row.get_child_count() >= 2:
			var label := row.get_child(0) as Label
			if is_instance_valid(label) and label.text == label_text:
				return row.get_child(1) as LineEdit
	return null


func _focused_control(editor: LevelEditor) -> String:
	var control := editor.get_viewport().gui_get_focus_owner()
	return str(control.name) if is_instance_valid(control) else "none"


func _local(editor: LevelEditor, point: Vector2) -> Vector2:
	return editor.canvas.call("_logical_point_to_local", point,
		editor.canvas.call("_canvas_view_rect"))


func _drag(editor: LevelEditor, start: Vector2, finish: Vector2) -> void:
	editor.canvas.call("_begin_primary_action", _local(editor, start))
	editor.canvas.call("_update_drag", _local(editor, finish))
	editor.canvas.call("_finish_primary_action", _local(editor, finish))
	await process_frame


func _key_event(key: Key, pressed: bool, command := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.ctrl_pressed = command
	return event


func _press_key(key: Key, command := false) -> void:
	Input.parse_input_event(_key_event(key, true, command))
	await process_frame
	await physics_frame
	Input.parse_input_event(_key_event(key, false, command))
	await process_frame


func _fake_export(_name: String, bytes: PackedByteArray, _mime: String) -> Dictionary:
	exported_bytes = bytes.duplicate()
	return {"ok": true}


func _fake_import() -> Dictionary:
	return {"ok": true, "file_name": "ui_smoke.json", "bytes": exported_bytes.duplicate()}


func _cleanup() -> void:
	if temporary_level_id.is_empty():
		return
	var path := ProjectSettings.globalize_path("user://levels/%s.json" % temporary_level_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	temporary_level_id = ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup()
	if failures.is_empty():
		print("LEVEL_EDITOR_UI_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

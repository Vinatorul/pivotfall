extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)

var failures: Array[String] = []
var temporary_level_ids: Array[String] = []
var queued_import_result: Dictionary = {}
var exported_files: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	_cleanup_temporary_levels()


func _run() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		is_instance_valid(editor.import_button)
		and is_instance_valid(editor.export_button)
		and is_instance_valid(editor.file_transfer)
		and not editor.problems.bbcode_enabled,
		"Editor did not expose Import, Export, and file transfer controls."
	)
	_expect(
		editor.file_transfer.configure_for_tests(
			_fake_export,
			_fake_import
		),
		"Debug build rejected the file-transfer test seam."
	)

	await _test_export(editor)
	await _test_invalid_imports(editor)
	await _test_new_import(editor)
	await _test_dirty_and_conflicting_import(editor)
	await _test_transport_results(editor)

	editor.queue_free()
	await editor.tree_exited
	_finish()


func _test_export(editor: LevelEditor) -> void:
	var level_id := _new_level_id("export")
	var data := _make_level(level_id, "SHARED EXPORT")
	editor.draft.replace(data, false)
	var history_before := editor.draft.can_undo()
	exported_files.clear()

	editor.export_button.pressed.emit()
	_expect(
		exported_files.size() == 1,
		"Export button did not invoke the configured transfer."
	)
	if exported_files.size() == 1:
		var exported := exported_files[0]
		var decoded: Dictionary = LEVEL_DATA_CODEC.decode_text(
			(exported["bytes"] as PackedByteArray).get_string_from_utf8()
		)
		_expect(
			exported["file_name"] == "%s.json" % level_id
			and exported["mime_type"] == "application/json"
			and bool(decoded.get("ok", false))
			and decoded["data"] == data,
			"Export did not produce the canonical current level JSON."
		)
	_expect(
		editor.draft.is_dirty()
		and editor.draft.can_undo() == history_before
		and not bool(
			LEVEL_STORAGE.user_level_exists(level_id).get(
				"data",
				false
			)
		),
		"Export saved or altered the current draft."
	)

	var invalid_data := data.duplicate(true)
	invalid_data["level_id"] = "INVALID ID"
	editor.draft.replace(invalid_data, false)
	exported_files.clear()
	editor.call("_request_export_level")
	_expect(
		exported_files.is_empty()
		and editor.notice_is_error
		and "Экспорт не выполнен" in editor.notice_text,
		"Invalid draft was exported or did not report an error."
	)


func _test_invalid_imports(editor: LevelEditor) -> void:
	var baseline := _make_level(
		_new_level_id("baseline"),
		"IMPORT BASELINE"
	)
	editor.draft.replace(baseline, true)
	var snapshot := editor.draft.to_dictionary()

	queued_import_result = {
		"ok": true,
		"file_name": "broken.json",
		"bytes": "{broken".to_utf8_buffer(),
	}
	editor.import_button.pressed.emit()
	_expect(
		editor.draft.to_dictionary() == snapshot
		and editor.pending_import_data.is_empty()
		and editor.notice_is_error
		and "Invalid level JSON" in editor.notice_text,
		"Malformed imported JSON mutated the editor."
	)

	var oversized := PackedByteArray()
	oversized.resize(LEVEL_DATA_CODEC.MAX_FILE_BYTES + 1)
	queued_import_result = {
		"ok": true,
		"file_name": "oversized.json",
		"bytes": oversized,
	}
	editor.import_button.pressed.emit()
	_expect(
		editor.draft.to_dictionary() == snapshot
		and editor.pending_import_data.is_empty()
		and "%d КБ" % int(
			LEVEL_DATA_CODEC.MAX_FILE_BYTES / 1024
		) in editor.notice_text,
		"Oversized imported JSON was accepted or changed the draft."
	)


func _test_new_import(editor: LevelEditor) -> void:
	var level_id := _new_level_id("new_import")
	var data := _make_level(level_id, "FRIEND LEVEL")
	var shared_file_name := "friend_[color=red]level.json"
	queued_import_result = _import_result(data, shared_file_name)
	editor.import_button.pressed.emit()

	var stored: Dictionary = LEVEL_STORAGE.load_user_level(level_id)
	_expect(
		bool(stored.get("ok", false))
		and stored["data"] == data
		and editor.draft.to_dictionary() == data
		and not editor.draft.is_dirty()
		and editor.source_label == "USER"
		and editor.loaded_user_level_id == level_id
		and shared_file_name in editor.notice_text,
		(
			"Valid imported level was not stored and opened as a clean draft: "
			+ "%s / %s" % [stored.get("errors", []), editor.notice_text]
		)
	)
	_expect(
		_selected_load_id(editor) == level_id
		and not _has_auxiliary_storage_files(level_id),
		"Imported level was not selected cleanly in Load."
	)


func _test_dirty_and_conflicting_import(editor: LevelEditor) -> void:
	var level_id := _new_level_id("conflict")
	var old_data := _make_level(level_id, "OLD LEVEL")
	var new_data := _make_level(level_id, "NEW LEVEL")
	var fixture_result: Dictionary = LEVEL_STORAGE.save_user_level(old_data)
	_expect(
		bool(fixture_result.get("ok", false)),
		"Could not create the import collision fixture: %s"
		% [fixture_result.get("errors", [])]
	)

	editor.draft.set_root_value("title", "UNSAVED LOCAL DRAFT")
	var dirty_snapshot := editor.draft.to_dictionary()
	queued_import_result = _import_result(new_data, "replacement.json")
	editor.import_button.pressed.emit()
	var stored_before: Dictionary = LEVEL_STORAGE.load_user_level(level_id)
	_expect(
		editor.discard_dialog.visible
		and editor.pending_destructive_action == "import"
		and editor.pending_import_data == new_data
		and "черновик" in editor.discard_dialog.dialog_text
		and "будет заменён" in editor.discard_dialog.dialog_text
		and stored_before["data"]["title"] == "OLD LEVEL",
		"Dirty/conflicting import did not wait for combined confirmation."
	)

	editor.discard_dialog.hide()
	editor.discard_dialog.canceled.emit()
	var stored_after_cancel: Dictionary = LEVEL_STORAGE.load_user_level(
		level_id
	)
	_expect(
		editor.draft.to_dictionary() == dirty_snapshot
		and editor.pending_destructive_action.is_empty()
		and editor.pending_import_data.is_empty()
		and stored_after_cancel["data"]["title"] == "OLD LEVEL",
		"Cancelling import changed the draft, pending state, or old file."
	)

	queued_import_result = _import_result(new_data, "replacement.json")
	editor.import_button.pressed.emit()
	editor.discard_dialog.hide()
	editor.call("_on_discard_confirmed")
	var stored_after_confirm: Dictionary = LEVEL_STORAGE.load_user_level(
		level_id
	)
	_expect(
		bool(stored_after_confirm.get("ok", false))
		and stored_after_confirm["data"]["title"] == "NEW LEVEL"
		and editor.draft.to_dictionary() == new_data
		and not editor.draft.is_dirty()
		and editor.pending_import_data.is_empty()
		and not _has_auxiliary_storage_files(level_id),
		"Confirmed import did not atomically replace and open the level."
	)


func _test_transport_results(editor: LevelEditor) -> void:
	var snapshot := editor.draft.to_dictionary()
	var notice_before := editor.notice_text
	queued_import_result = {"ok": true, "cancelled": true}
	editor.import_button.pressed.emit()
	_expect(
		editor.draft.to_dictionary() == snapshot
		and editor.notice_text == notice_before,
		"Cancelling the browser picker changed editor state."
	)

	queued_import_result = {
		"ok": false,
		"error": "browser read failed",
	}
	editor.import_button.pressed.emit()
	_expect(
		editor.draft.to_dictionary() == snapshot
		and editor.notice_is_error
		and "browser read failed" in editor.notice_text,
		"File-transfer failure was not surfaced without mutation."
	)


func _fake_export(
	file_name: String,
	bytes: PackedByteArray,
	mime_type: String
) -> Dictionary:
	exported_files.append(
		{
			"file_name": file_name,
			"bytes": bytes.duplicate(),
			"mime_type": mime_type,
		}
	)
	return {"ok": true}


func _fake_import() -> Dictionary:
	return queued_import_result.duplicate(true)


func _import_result(data: Dictionary, file_name: String) -> Dictionary:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	if not bool(encoded.get("ok", false)):
		return {
			"ok": false,
			"error": "Could not encode import fixture.",
		}
	return {
		"ok": true,
		"file_name": file_name,
		"bytes": str(encoded["text"]).to_utf8_buffer(),
	}


func _make_level(level_id: String, title: String) -> Dictionary:
	var result: Dictionary = LEVEL_STORAGE.make_default_level(level_id)
	if not bool(result.get("ok", false)):
		failures.append("Could not create level fixture '%s'." % level_id)
		return {}
	var data: Dictionary = result["data"]
	data["title"] = title
	var normalized: Dictionary = LEVEL_DATA_CODEC.encode(data)
	if not bool(normalized.get("ok", false)):
		failures.append("Could not normalize level fixture '%s'." % level_id)
		return data
	return normalized["data"]


func _new_level_id(kind: String) -> String:
	var level_id := "share_%s_%d" % [kind, Time.get_ticks_usec()]
	temporary_level_ids.append(level_id)
	return level_id


func _selected_load_id(editor: LevelEditor) -> String:
	var selected := editor.load_options.selected
	if selected < 0 or selected >= editor.load_entries.size():
		return ""
	return str(editor.load_entries[selected].get("id", ""))


func _has_auxiliary_storage_files(level_id: String) -> bool:
	var directory := DirAccess.open("user://levels")
	if not is_instance_valid(directory):
		return false
	directory.include_hidden = true
	for file_name: String in directory.get_files():
		if file_name.begins_with(".level_editor.%s." % level_id):
			return true
	return false


func _cleanup_temporary_levels() -> void:
	var directory := DirAccess.open("user://levels")
	if is_instance_valid(directory):
		directory.include_hidden = true
	for level_id: String in temporary_level_ids:
		var target := ProjectSettings.globalize_path(
			"user://levels/%s.json" % level_id
		)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)
		if not is_instance_valid(directory):
			continue
		for file_name: String in directory.get_files():
			if file_name.begins_with(".level_editor.%s." % level_id):
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path(
						"user://levels/%s" % file_name
					)
				)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	_cleanup_temporary_levels()
	if failures.is_empty():
		print("LEVEL_IMPORT_EXPORT_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

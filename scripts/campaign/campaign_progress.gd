class_name CampaignProgressStore
extends Node

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)

const SCHEMA_VERSION := 1
const MAX_FILE_BYTES := 8_192
const DEFAULT_STORAGE_PATH := "user://campaign_progress.json"
const LEGACY_COMPLETED_FINAL_LEVEL_ID := "arena_08_data"
const ROOT_KEYS := [
	"schema_version",
	"campaign_id",
	"current_level_id",
	"highest_unlocked_level_id",
	"completed",
]

var _storage_path := DEFAULT_STORAGE_PATH
var _pending_level_id := ""
var _pending_tracking := false


func load_progress(entries: Array[Dictionary]) -> Dictionary:
	var entry_result := _campaign_level_ids(entries)
	if not bool(entry_result["ok"]):
		return _failure(entry_result["errors"])
	if not _is_safe_storage_path(_storage_path):
		return _failure(["Campaign progress path is unsafe."])

	var target_exists := FileAccess.file_exists(_storage_path)
	if target_exists:
		var loaded := _load_path(_storage_path, entries)
		if bool(loaded["ok"]):
			_remove_if_present(_temporary_path())
			_remove_if_present(_backup_path())
			var warnings: Array[String] = []
			for warning: Variant in loaded.get("warnings", []):
				warnings.append(str(warning))
			return _success(true, loaded["data"], warnings)
		return _recover_progress(
			entries,
			loaded["errors"],
			true
		)

	return _recover_progress(entries, [], false)


func begin_new_game(entries: Array[Dictionary]) -> Dictionary:
	var progress_result := _new_progress(entries)
	if not bool(progress_result["ok"]):
		return progress_result

	var saved := _save_progress(
		progress_result["data"],
		entries
	)
	if not bool(saved["ok"]):
		return saved

	_prepare_launch(
		str(progress_result["data"]["current_level_id"]),
		true
	)
	return saved


func prepare_continue(entries: Array[Dictionary]) -> Dictionary:
	var loaded := load_progress(entries)
	if not bool(loaded["ok"]):
		return loaded
	if not bool(loaded["exists"]):
		return _failure(["Campaign progress does not exist."])

	var progress: Dictionary = loaded["data"]
	if bool(progress["completed"]):
		return _failure(["Campaign progress is already complete."], true)

	_prepare_launch(str(progress["current_level_id"]), true)
	return loaded


func reset_progress(entries: Array[Dictionary]) -> Dictionary:
	var progress_result := _new_progress(entries)
	if not bool(progress_result["ok"]):
		return progress_result
	return _save_progress(progress_result["data"], entries)


func record_level_started(
	entries: Array[Dictionary],
	level_id: String
) -> Dictionary:
	var loaded := load_progress(entries)
	if not bool(loaded["ok"]):
		return loaded
	if not bool(loaded["exists"]):
		return _failure(["Campaign progress does not exist."])

	var ids_result := _campaign_level_ids(entries)
	if not bool(ids_result["ok"]):
		return ids_result
	var level_ids: Array[String] = ids_result["ids"]
	var target_index := level_ids.find(level_id)
	if target_index < 0:
		return _failure(
			["Campaign level '%s' is not available." % level_id],
			true
		)

	var progress: Dictionary = loaded["data"].duplicate(true)
	var highest_index := level_ids.find(
		str(progress["highest_unlocked_level_id"])
	)
	if target_index > highest_index + 1:
		return _failure(
			["Campaign progress cannot skip locked levels."],
			true
		)
	progress["current_level_id"] = level_id
	progress["highest_unlocked_level_id"] = level_ids[
		maxi(highest_index, target_index)
	]
	progress["completed"] = false
	return _save_progress(progress, entries)


func mark_completed(entries: Array[Dictionary]) -> Dictionary:
	var loaded := load_progress(entries)
	if not bool(loaded["ok"]):
		return loaded
	if not bool(loaded["exists"]):
		return _failure(["Campaign progress does not exist."])

	var ids_result := _campaign_level_ids(entries)
	if not bool(ids_result["ok"]):
		return ids_result
	var level_ids: Array[String] = ids_result["ids"]
	var final_level_id := level_ids[-1]
	var progress: Dictionary = loaded["data"].duplicate(true)
	if str(progress["current_level_id"]) != final_level_id:
		return _failure(
			["Campaign cannot be completed before the final level."],
			true
		)
	progress["current_level_id"] = final_level_id
	progress["highest_unlocked_level_id"] = final_level_id
	progress["completed"] = true
	return _save_progress(progress, entries)


func consume_launch_request() -> Dictionary:
	var request := {
		"level_id": _pending_level_id,
		"track_progress": _pending_tracking,
	}
	cancel_launch_request()
	return request


func cancel_launch_request() -> void:
	_pending_level_id = ""
	_pending_tracking = false


func configure_storage_path_for_tests(path: String) -> bool:
	if (
		not OS.is_debug_build()
		or not _is_safe_storage_path(path)
		or path == DEFAULT_STORAGE_PATH
		or not path.begins_with("user://campaign_progress_test_")
	):
		return false
	_storage_path = path
	cancel_launch_request()
	return true


func restore_default_storage_path() -> void:
	_storage_path = DEFAULT_STORAGE_PATH
	cancel_launch_request()


func get_storage_path() -> String:
	return _storage_path


func clear_progress() -> Dictionary:
	cancel_launch_request()
	if not _is_safe_storage_path(_storage_path):
		return _failure(["Campaign progress path is unsafe."])
	var errors: Array[String] = []
	for path: String in _progress_artifact_paths():
		if not FileAccess.file_exists(path):
			continue
		var remove_error := DirAccess.remove_absolute(path)
		if remove_error != OK and FileAccess.file_exists(path):
			errors.append(
				"Could not remove campaign progress file '%s' (error %d)."
				% [path, remove_error]
			)
	if not errors.is_empty():
		return _failure(errors)
	return _success(false, {}, [])


func _prepare_launch(level_id: String, track_progress: bool) -> void:
	_pending_level_id = level_id
	_pending_tracking = track_progress


func _new_progress(entries: Array[Dictionary]) -> Dictionary:
	var ids_result := _campaign_level_ids(entries)
	if not bool(ids_result["ok"]):
		return ids_result
	var level_ids: Array[String] = ids_result["ids"]
	var first_level_id := level_ids[0]
	return {
		"ok": true,
		"data": {
			"schema_version": SCHEMA_VERSION,
			"campaign_id": CAMPAIGN_STORAGE.BUILTIN_CAMPAIGN_ID,
			"current_level_id": first_level_id,
			"highest_unlocked_level_id": first_level_id,
			"completed": false,
		},
		"errors": [] as Array[String],
	}


func _save_progress(
	raw: Variant,
	entries: Array[Dictionary]
) -> Dictionary:
	if not _is_safe_storage_path(_storage_path):
		return _failure(["Campaign progress path is unsafe."])

	var validation := _validate_progress(raw, entries)
	if not bool(validation["ok"]):
		return validation

	var text := JSON.stringify(
		validation["data"],
		"\t",
		true,
		false
	) + "\n"
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure(["Encoded campaign progress is too large."])

	var temporary_path := _temporary_path()
	var backup_path := _backup_path()
	_remove_if_present(temporary_path)
	_remove_if_present(backup_path)

	var write_result := _write_text_file(temporary_path, text)
	if not bool(write_result["ok"]):
		_remove_if_present(temporary_path)
		return write_result

	var temporary_check := _load_path(temporary_path, entries)
	if not bool(temporary_check["ok"]):
		_remove_if_present(temporary_path)
		return _failure(temporary_check["errors"])

	var target_exists := FileAccess.file_exists(_storage_path)
	if target_exists:
		var backup_error := DirAccess.rename_absolute(
			_storage_path,
			backup_path
		)
		if backup_error != OK:
			_remove_if_present(temporary_path)
			return _failure(
				[
					"Could not back up campaign progress (error %d)."
					% backup_error
				]
			)

	var replace_error := DirAccess.rename_absolute(
		temporary_path,
		_storage_path
	)
	if replace_error != OK:
		var replace_errors: Array[String] = [
			"Could not replace campaign progress (error %d)."
			% replace_error
		]
		_remove_if_present(temporary_path)
		_restore_backup(backup_path, replace_errors)
		return _failure(replace_errors)

	var final_check := _load_path(_storage_path, entries)
	if not bool(final_check["ok"]):
		var verification_errors: Array[String] = []
		verification_errors.append_array(final_check["errors"])
		_remove_if_present(_storage_path)
		_restore_backup(backup_path, verification_errors)
		return _failure(verification_errors)

	_remove_if_present(backup_path)
	return _success(true, final_check["data"], [])


func _load_path(
	path: String,
	entries: Array[Dictionary]
) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure(["Campaign progress file does not exist."])

	var file := FileAccess.open(path, FileAccess.READ)
	if not is_instance_valid(file):
		return _failure(
			[
				"Could not open campaign progress (error %d)."
				% FileAccess.get_open_error()
			]
		)
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return _failure(["Campaign progress file is too large."])

	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _failure(
			[
				"Could not read campaign progress (error %d)."
				% read_error
			]
		)

	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return _failure(
			[
				"Invalid campaign progress JSON at line %d: %s."
				% [
					parser.get_error_line(),
					parser.get_error_message(),
				]
			]
		)
	var migration := _migrate_legacy_completed_progress(
		parser.data,
		entries
	)
	var validation := _validate_progress(
		migration["data"],
		entries
	)
	if bool(validation.get("ok", false)):
		validation["warnings"] = migration["warnings"]
	return validation


func _validate_progress(
	raw: Variant,
	entries: Array[Dictionary]
) -> Dictionary:
	var ids_result := _campaign_level_ids(entries)
	if not bool(ids_result["ok"]):
		return ids_result
	var level_ids: Array[String] = ids_result["ids"]
	var errors: Array[String] = []

	if typeof(raw) != TYPE_DICTIONARY:
		return _failure(["Campaign progress must be a dictionary."])
	var root: Dictionary = raw

	for key: Variant in root.keys():
		if not ROOT_KEYS.has(str(key)):
			errors.append(
				"Campaign progress contains unknown field '%s'."
				% str(key)
			)
	for key: String in ROOT_KEYS:
		if not root.has(key):
			errors.append(
				"Campaign progress is missing field '%s'." % key
			)
	if not errors.is_empty():
		return _failure(errors)

	var schema_version := _read_integer(root["schema_version"])
	if schema_version != SCHEMA_VERSION:
		errors.append(
			"Campaign progress schema must be %d."
			% SCHEMA_VERSION
		)

	if (
		typeof(root["campaign_id"]) != TYPE_STRING
		or str(root["campaign_id"])
		!= CAMPAIGN_STORAGE.BUILTIN_CAMPAIGN_ID
	):
		errors.append("Campaign progress belongs to another campaign.")

	var current_level_id := ""
	if typeof(root["current_level_id"]) == TYPE_STRING:
		current_level_id = str(root["current_level_id"])
	if not level_ids.has(current_level_id):
		errors.append("Campaign progress has an unknown current level.")

	var highest_level_id := ""
	if typeof(root["highest_unlocked_level_id"]) == TYPE_STRING:
		highest_level_id = str(root["highest_unlocked_level_id"])
	if not level_ids.has(highest_level_id):
		errors.append(
			"Campaign progress has an unknown highest unlocked level."
		)

	if typeof(root["completed"]) != TYPE_BOOL:
		errors.append("Campaign progress completed flag must be boolean.")
	var completed := (
		bool(root["completed"])
		if typeof(root["completed"]) == TYPE_BOOL
		else false
	)

	var current_index := level_ids.find(current_level_id)
	var highest_index := level_ids.find(highest_level_id)
	if (
		current_index >= 0
		and highest_index >= 0
		and current_index > highest_index
	):
		errors.append(
			"Current level cannot be beyond the unlocked campaign progress."
		)

	if completed and (
		current_index != level_ids.size() - 1
		or highest_index != level_ids.size() - 1
	):
		errors.append(
			"Completed progress must point to the final campaign level."
		)

	if not errors.is_empty():
		return _failure(errors)
	return {
		"ok": true,
		"data": {
			"schema_version": SCHEMA_VERSION,
			"campaign_id": CAMPAIGN_STORAGE.BUILTIN_CAMPAIGN_ID,
			"current_level_id": current_level_id,
			"highest_unlocked_level_id": highest_level_id,
			"completed": completed,
		},
		"errors": [] as Array[String],
	}


func _migrate_legacy_completed_progress(
	raw: Variant,
	entries: Array[Dictionary]
) -> Dictionary:
	var result := {
		"data": raw,
		"warnings": [] as Array[String],
	}
	if typeof(raw) != TYPE_DICTIONARY:
		return result

	var root := raw as Dictionary
	if (
		_read_integer(root.get("schema_version")) != SCHEMA_VERSION
		or root.get("campaign_id")
		!= CAMPAIGN_STORAGE.BUILTIN_CAMPAIGN_ID
		or root.get("current_level_id")
		!= LEGACY_COMPLETED_FINAL_LEVEL_ID
		or root.get("highest_unlocked_level_id")
		!= LEGACY_COMPLETED_FINAL_LEVEL_ID
		or typeof(root.get("completed")) != TYPE_BOOL
		or not bool(root.get("completed"))
	):
		return result

	var ids_result := _campaign_level_ids(entries)
	if not bool(ids_result.get("ok", false)):
		return result
	var level_ids: Array[String] = ids_result["ids"]
	var legacy_index := level_ids.find(
		LEGACY_COMPLETED_FINAL_LEVEL_ID
	)
	if legacy_index < 0 or legacy_index + 1 >= level_ids.size():
		return result

	var next_level_id := level_ids[legacy_index + 1]
	var migrated := root.duplicate(true)
	migrated["current_level_id"] = next_level_id
	migrated["highest_unlocked_level_id"] = next_level_id
	migrated["completed"] = false
	result["data"] = migrated
	result["warnings"] = [
		"Campaign expanded after Arena 08; the next level was unlocked."
	] as Array[String]
	return result


func _campaign_level_ids(
	entries: Array[Dictionary]
) -> Dictionary:
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		var level_id := str(entry.get("id", ""))
		if level_id.is_empty() or ids.has(level_id):
			return _failure(
				["Campaign entries do not contain unique stable IDs."]
			)
		ids.append(level_id)
	if ids.is_empty():
		return _failure(["Campaign does not contain any levels."])
	return {
		"ok": true,
		"ids": ids,
		"errors": [] as Array[String],
	}


func _recover_progress(
	entries: Array[Dictionary],
	target_errors: Array,
	target_existed: bool
) -> Dictionary:
	var recovery_errors: Array[String] = []
	for error: Variant in target_errors:
		recovery_errors.append(str(error))
	var damaged_state_exists := (
		target_existed
		or not _corrupt_artifact_paths().is_empty()
	)
	var sidecar_exists := false
	for recovery_path: String in [
		_temporary_path(),
		_backup_path(),
	]:
		if not FileAccess.file_exists(recovery_path):
			continue
		sidecar_exists = true
		var loaded := _load_path(recovery_path, entries)
		if not bool(loaded["ok"]):
			for error: Variant in loaded["errors"]:
				recovery_errors.append(
					"%s: %s" % [recovery_path, str(error)]
				)
			continue

		var promoted := _promote_recovery_candidate(
			recovery_path,
			entries
		)
		if bool(promoted["ok"]):
			_remove_if_present(_temporary_path())
			_remove_if_present(_backup_path())
			var warnings: Array[String] = [
				"Recovered interrupted campaign progress save."
			]
			if damaged_state_exists:
				warnings.append(
					"Damaged campaign progress was preserved for diagnosis."
				)
			return _success(
				true,
				promoted["data"],
				warnings
			)
		for error: Variant in promoted["errors"]:
			recovery_errors.append(str(error))
		if not bool(promoted.get("can_continue", false)):
			break

	if not damaged_state_exists and not sidecar_exists:
		return _success(false, {}, [])
	if recovery_errors.is_empty():
		recovery_errors.append(
			"Campaign progress is damaged and cannot be recovered."
		)
	return _failure(recovery_errors, true)


func _promote_recovery_candidate(
	recovery_path: String,
	entries: Array[Dictionary]
) -> Dictionary:
	var target_existed := FileAccess.file_exists(_storage_path)
	var corrupt_path := ""
	if target_existed:
		corrupt_path = _next_corrupt_path()
		if corrupt_path.is_empty():
			return _promotion_failure(
				["Could not reserve a campaign progress quarantine path."],
				false
			)
		var quarantine_error := DirAccess.rename_absolute(
			_storage_path,
			corrupt_path
		)
		if quarantine_error != OK:
			return _promotion_failure(
				[
					"Could not quarantine damaged campaign progress "
					+ "(error %d)." % quarantine_error
				],
				true
			)

	var promote_error := DirAccess.rename_absolute(
		recovery_path,
		_storage_path
	)
	if promote_error != OK:
		var promote_errors: Array[String] = [
			"Could not recover campaign progress (error %d)."
			% promote_error
		]
		var promotion_restore_ok := _restore_quarantined_target(
			corrupt_path,
			promote_errors
		)
		return _promotion_failure(
			promote_errors,
			promotion_restore_ok
		)

	var verified := _load_path(_storage_path, entries)
	if bool(verified["ok"]):
		return verified

	var verification_errors: Array[String] = []
	for error: Variant in verified["errors"]:
		verification_errors.append(str(error))
	var remove_error := DirAccess.remove_absolute(_storage_path)
	if (
		remove_error != OK
		and FileAccess.file_exists(_storage_path)
	):
		verification_errors.append(
			"Could not remove failed campaign recovery (error %d)."
			% remove_error
		)
		return _promotion_failure(verification_errors, false)

	var verification_restore_ok := _restore_quarantined_target(
		corrupt_path,
		verification_errors
	)
	return _promotion_failure(
		verification_errors,
		verification_restore_ok
	)


func _restore_quarantined_target(
	corrupt_path: String,
	errors: Array[String]
) -> bool:
	if corrupt_path.is_empty():
		return true
	if FileAccess.file_exists(_storage_path):
		errors.append(
			"Could not restore damaged campaign progress because "
			+ "the destination is occupied."
		)
		return false
	var restore_error := DirAccess.rename_absolute(
		corrupt_path,
		_storage_path
	)
	if (
		restore_error != OK
		or not FileAccess.file_exists(_storage_path)
	):
		errors.append(
			"Could not restore damaged campaign progress (error %d)."
			% restore_error
		)
		return false
	return true


func _promotion_failure(
	errors: Array,
	can_continue: bool
) -> Dictionary:
	var result := _failure(errors, true)
	result["can_continue"] = can_continue
	return result


func _write_text_file(path: String, text: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not is_instance_valid(file):
		return _failure(
			[
				"Could not open campaign progress temporary file (error %d)."
				% FileAccess.get_open_error()
			]
		)

	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure(
			[
				"Could not write campaign progress (error %d)."
				% write_error
			]
		)
	return {"ok": true, "errors": [] as Array[String]}


func _restore_backup(
	backup_path: String,
	errors: Array[String]
) -> void:
	if backup_path.is_empty() or not FileAccess.file_exists(backup_path):
		return
	if FileAccess.file_exists(_storage_path):
		_remove_if_present(_storage_path)
	var restore_error := DirAccess.rename_absolute(
		backup_path,
		_storage_path
	)
	if restore_error != OK:
		errors.append(
			"Could not restore campaign progress backup (error %d)."
			% restore_error
		)


func _remove_if_present(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)


func _temporary_path() -> String:
	return "%s.tmp" % _storage_path


func _backup_path() -> String:
	return "%s.bak" % _storage_path


func _corrupt_path() -> String:
	return "%s.corrupt" % _storage_path


func _next_corrupt_path() -> String:
	var base_path := _corrupt_path()
	if not FileAccess.file_exists(base_path):
		return base_path
	for index: int in range(1, 10_000):
		var candidate := "%s.%d" % [base_path, index]
		if not FileAccess.file_exists(candidate):
			return candidate
	return ""


func _corrupt_artifact_paths() -> Array[String]:
	var paths: Array[String] = []
	var storage_file_name := _storage_path.trim_prefix("user://")
	var corrupt_file_name := "%s.corrupt" % storage_file_name
	for file_name: String in DirAccess.get_files_at("user://"):
		if (
			file_name == corrupt_file_name
			or file_name.begins_with("%s." % corrupt_file_name)
		):
			paths.append("user://%s" % file_name)
	return paths


func _progress_artifact_paths() -> Array[String]:
	var paths: Array[String] = [
		_storage_path,
		_temporary_path(),
		_backup_path(),
	]
	for corrupt_path: String in _corrupt_artifact_paths():
		paths.append(corrupt_path)
	return paths


func _is_safe_storage_path(path: String) -> bool:
	if not path.begins_with("user://"):
		return false
	var file_name := path.trim_prefix("user://")
	return (
		not file_name.is_empty()
		and file_name.length() <= 128
		and "/" not in file_name
		and "\\" not in file_name
		and file_name.ends_with(".json")
	)


func _read_integer(raw: Variant) -> int:
	if typeof(raw) == TYPE_INT:
		return int(raw)
	if typeof(raw) != TYPE_FLOAT:
		return -1
	var number := float(raw)
	if not is_finite(number) or number != floorf(number):
		return -1
	return int(number)


func _success(
	exists: bool,
	data: Dictionary,
	warnings: Array[String]
) -> Dictionary:
	return {
		"ok": true,
		"exists": exists,
		"data": data.duplicate(true),
		"errors": [] as Array[String],
		"warnings": warnings,
		"path": _storage_path,
	}


func _failure(
	errors: Array,
	exists: bool = false
) -> Dictionary:
	var messages: Array[String] = []
	for error: Variant in errors:
		messages.append(str(error))
	return {
		"ok": false,
		"exists": exists,
		"data": {},
		"errors": messages,
		"warnings": [] as Array[String],
		"path": _storage_path,
	}

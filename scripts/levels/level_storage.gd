class_name LevelStorage
extends RefCounted

## Owns every filesystem path used by the level editor.
##
## Public methods accept stable level IDs or level data, never paths. User
## levels are always stored directly under `user://levels/` as `<level_id>.json`.

const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)

const BUILTIN_ARENA_01_PATH := "res://levels/arena_01.json"
const BUILTIN_ARENA_01_ID := "arena_01_data"
const USER_LEVEL_ROOT := "user://levels"
const USER_LEVEL_DIRECTORY := "levels"
const LEVEL_EXTENSION := ".json"
const AUXILIARY_NAMESPACE := "level_editor"
const MAX_LEVEL_ID_LENGTH := 64
const MAX_GENERATED_ID_ATTEMPTS := 10_000


static func load_builtin_arena_01() -> Dictionary:
	return _load_verified_file(
		BUILTIN_ARENA_01_PATH,
		BUILTIN_ARENA_01_ID
	)


static func load_user_level(level_id: String) -> Dictionary:
	var id_error := _validate_level_id(level_id)
	if not id_error.is_empty():
		return _failure([id_error])

	var directory_result := _open_user_level_directory(false)
	if not bool(directory_result["ok"]):
		return _failure(directory_result["errors"])
	if not bool(directory_result["exists"]):
		return _failure(["User level '%s' does not exist." % level_id])

	var directory := directory_result["directory"] as DirAccess
	var recovery_result := _recover_interrupted_save(
		level_id,
		directory
	)
	if not bool(recovery_result["ok"]):
		return recovery_result

	var file_name := _file_name_for_id(level_id)
	if directory.is_link(file_name):
		return _merge_recovery_metadata(
			_failure(
				["User level '%s' must not be a symbolic link." % level_id]
			),
			recovery_result
		)
	if directory.dir_exists(file_name):
		return _merge_recovery_metadata(
			_failure(
				[
					"User level '%s' points to a directory, not a file."
					% level_id
				]
			),
			recovery_result
		)

	return _merge_recovery_metadata(
		_load_verified_file(
			_user_path_for_id(level_id),
			level_id
		),
		recovery_result
	)


static func user_level_exists(level_id: String) -> Dictionary:
	var id_error := _validate_level_id(level_id)
	if not id_error.is_empty():
		return _failure([id_error])

	var directory_result := _open_user_level_directory(false)
	if not bool(directory_result["ok"]):
		return _failure(directory_result["errors"])
	if not bool(directory_result["exists"]):
		return _success(false, _user_path_for_id(level_id))

	var directory := directory_result["directory"] as DirAccess
	var recovery_result := _recover_interrupted_save(
		level_id,
		directory
	)
	if not bool(recovery_result["ok"]):
		return recovery_result

	var file_name := _file_name_for_id(level_id)
	if directory.is_link(file_name):
		return _merge_recovery_metadata(
			_failure(
				["User level '%s' must not be a symbolic link." % level_id]
			),
			recovery_result
		)
	if directory.dir_exists(file_name):
		return _merge_recovery_metadata(
			_failure(
				[
					"User level '%s' points to a directory, not a file."
					% level_id
				]
			),
			recovery_result
		)

	return _merge_recovery_metadata(
		_success(
			directory.file_exists(file_name),
			_user_path_for_id(level_id)
		),
		recovery_result
	)


static func save_user_level(data: Variant) -> Dictionary:
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	if not bool(encoded["ok"]):
		return _failure(encoded["errors"])

	var canonical_data: Dictionary = encoded["data"]
	var level_id: String = canonical_data["level_id"]
	var id_error := _validate_level_id(level_id)
	if not id_error.is_empty():
		return _failure([id_error])

	var text: String = encoded["text"]
	if text.to_utf8_buffer().size() > LEVEL_DATA_CODEC.MAX_FILE_BYTES:
		return _failure(
			[
				"Encoded level exceeds the %d byte limit."
				% LEVEL_DATA_CODEC.MAX_FILE_BYTES
			]
		)

	var directory_result := _open_user_level_directory(true)
	if not bool(directory_result["ok"]):
		return _failure(directory_result["errors"])

	var directory := directory_result["directory"] as DirAccess
	var recovery_result := _recover_interrupted_save(
		level_id,
		directory
	)
	if not bool(recovery_result["ok"]):
		return recovery_result

	var file_name := _file_name_for_id(level_id)
	if directory.is_link(file_name):
		return _merge_recovery_metadata(
			_failure(
				["Refusing to replace symbolic link '%s'." % file_name]
			),
			recovery_result
		)
	if directory.dir_exists(file_name):
		return _merge_recovery_metadata(
			_failure(
				["Refusing to replace directory '%s'." % file_name]
			),
			recovery_result
		)

	var target_path := _user_path_for_id(level_id)
	var target_exists := directory.file_exists(file_name)
	var temporary_path := _make_unique_auxiliary_path(
		directory,
		level_id,
		"tmp"
	)
	if temporary_path.is_empty():
		return _failure(
			["Could not allocate a temporary file for '%s'." % level_id],
			target_path
		)

	var write_result := _write_text_file(temporary_path, text)
	if not bool(write_result["ok"]):
		_remove_if_present(temporary_path)
		return _failure(write_result["errors"], target_path)

	var temporary_verification := _verify_file(
		temporary_path,
		level_id,
		text
	)
	if not bool(temporary_verification["ok"]):
		_remove_if_present(temporary_path)
		return _failure(
			temporary_verification["errors"],
			target_path
		)

	var backup_path := ""
	if target_exists:
		backup_path = _make_unique_auxiliary_path(
			directory,
			level_id,
			"bak"
		)
		if backup_path.is_empty():
			_remove_if_present(temporary_path)
			return _failure(
				["Could not allocate a backup file for '%s'." % level_id],
				target_path
			)

		var backup_error := DirAccess.rename_absolute(
			target_path,
			backup_path
		)
		if backup_error != OK:
			_remove_if_present(temporary_path)
			_remove_if_present(backup_path)
			return _failure(
				[
					"Could not move level '%s' to its backup (error %d)."
					% [level_id, backup_error]
				],
				target_path
			)

	var replace_error := DirAccess.rename_absolute(
		temporary_path,
		target_path
	)
	if replace_error != OK:
		var replace_errors: Array[String] = [
			"Could not replace level '%s' (error %d)."
			% [level_id, replace_error]
		]
		_remove_if_present(temporary_path)
		_restore_backup(backup_path, target_path, replace_errors)
		return _failure(replace_errors, target_path)

	var final_verification := _verify_file(
		target_path,
		level_id,
		text
	)
	if not bool(final_verification["ok"]):
		var verification_errors: Array[String] = []
		verification_errors.append_array(final_verification["errors"])
		if backup_path.is_empty():
			var remove_error := DirAccess.remove_absolute(target_path)
			if remove_error != OK and FileAccess.file_exists(target_path):
				verification_errors.append(
					"Could not remove the invalid new level (error %d)."
					% remove_error
				)
		else:
			_restore_backup(
				backup_path,
				target_path,
				verification_errors
			)
		return _failure(verification_errors, target_path)

	_remove_if_present(backup_path)
	return _merge_recovery_metadata(
		_success(canonical_data, target_path),
		recovery_result
	)


static func list_user_levels() -> Dictionary:
	var directory_result := _open_user_level_directory(false)
	if not bool(directory_result["ok"]):
		return {
			"ok": false,
			"entries": [] as Array[Dictionary],
			"errors": directory_result["errors"],
			"warnings": [] as Array[String],
			"recoveries": [] as Array[Dictionary],
		}
	if not bool(directory_result["exists"]):
		return {
			"ok": true,
			"entries": [] as Array[Dictionary],
			"errors": [] as Array[String],
			"warnings": [] as Array[String],
			"recoveries": [] as Array[Dictionary],
		}

	var directory := directory_result["directory"] as DirAccess
	var recovery_result := _recover_all_interrupted_saves(directory)
	var entries: Array[Dictionary] = []
	var listed_ids := {}
	for file_name: String in directory.get_files():
		if not file_name.ends_with(LEVEL_EXTENSION):
			continue

		var level_id := file_name.left(
			file_name.length() - LEVEL_EXTENSION.length()
		)
		if not _validate_level_id(level_id).is_empty():
			continue
		listed_ids[level_id] = true

		var loaded := load_user_level(level_id)
		if bool(loaded["ok"]):
			var level_data: Dictionary = loaded["data"]
			entries.append(
				{
					"ok": true,
					"level_id": level_id,
					"title": level_data["title"],
					"path": loaded["path"],
					"errors": [] as Array[String],
				}
			)
		else:
			entries.append(
				{
					"ok": false,
					"level_id": level_id,
					"title": "",
					"path": _user_path_for_id(level_id),
					"errors": loaded["errors"],
				}
			)

	for failure: Dictionary in recovery_result.get("failures", []):
		var failed_level_id := str(failure["level_id"])
		if listed_ids.has(failed_level_id):
			continue
		entries.append(
			{
				"ok": false,
				"level_id": failed_level_id,
				"title": "",
				"path": _user_path_for_id(failed_level_id),
				"errors": failure["errors"],
			}
		)

	return {
		"ok": true,
		"entries": entries,
		"errors": recovery_result["errors"],
		"warnings": recovery_result["warnings"],
		"recoveries": recovery_result["recoveries"],
	}


static func next_available_level_id(base: String = "my_arena") -> Dictionary:
	var id_error := _validate_level_id(base)
	if not id_error.is_empty():
		return _failure([id_error])

	var directory_result := _open_user_level_directory(false)
	if not bool(directory_result["ok"]):
		return _failure(directory_result["errors"])

	var directory := directory_result["directory"] as DirAccess
	var unavailable_ids := {}
	if bool(directory_result["exists"]):
		var recovery_result := _recover_all_interrupted_saves(directory)
		for failure: Dictionary in recovery_result.get("failures", []):
			unavailable_ids[str(failure["level_id"])] = true
		for file_name: String in directory.get_files():
			var auxiliary := _owned_auxiliary_info(file_name)
			if not auxiliary.is_empty():
				unavailable_ids[str(auxiliary["level_id"])] = true

	for index in MAX_GENERATED_ID_ATTEMPTS:
		var suffix := "" if index == 0 else "_%d" % (index + 1)
		var maximum_base_length := MAX_LEVEL_ID_LENGTH - suffix.length()
		var candidate := base.left(maximum_base_length) + suffix
		if candidate == BUILTIN_ARENA_01_ID:
			continue
		if unavailable_ids.has(candidate):
			continue
		if (
			not bool(directory_result["exists"])
			or not _directory_has_name(
				directory,
				_file_name_for_id(candidate)
			)
		):
			return _success(
				candidate,
				_user_path_for_id(candidate)
			)

	return _failure(
		[
			"Could not find an available level ID after %d attempts."
			% MAX_GENERATED_ID_ATTEMPTS
		]
	)


static func make_default_level(level_id: String) -> Dictionary:
	var id_error := _validate_level_id(level_id)
	if not id_error.is_empty():
		return _failure([id_error])

	var data := {
		"schema_version": 1,
		"level_id": level_id,
		"title": "MY ARENA",
		"objective": "СТОЛКНИ ВРАГА В ЯМУ ↓",
		"clear_message": "АРЕНА ПРОЙДЕНА  /  ПЕРЕЗАПУСК...",
		"canvas": {
			"width": 960,
			"height": 540,
			"grid_size": 20,
		},
		"objects": [
			{
				"id": "left_floor",
				"type": "solid_rect",
				"rect": [32, 496, 368, 44],
			},
			{
				"id": "right_floor",
				"type": "solid_rect",
				"rect": [560, 496, 368, 44],
			},
			{
				"id": "player_start",
				"type": "player_spawn",
				"position": [150, 450],
			},
			{
				"id": "patrol_1",
				"type": "patrol_enemy",
				"position": [360, 450],
				"speed": 65,
				"direction": 1,
			},
		],
	}
	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	if not bool(encoded["ok"]):
		return _failure(encoded["errors"])
	return _success(encoded["data"])


static func _load_verified_file(
	path: String,
	expected_level_id: String
) -> Dictionary:
	var loaded: Dictionary = LEVEL_DATA_CODEC.load_file(path)
	if not bool(loaded["ok"]):
		return _failure(loaded["errors"], path)

	var data: Dictionary = loaded["data"]
	if data["level_id"] != expected_level_id:
		return _failure(
			[
				"Level ID '%s' does not match expected ID '%s'."
				% [data["level_id"], expected_level_id]
			],
			path
		)

	return _success(data, path)


static func _verify_file(
	path: String,
	expected_level_id: String,
	expected_text: String
) -> Dictionary:
	var loaded := _load_verified_file(path, expected_level_id)
	if not bool(loaded["ok"]):
		return loaded

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(loaded["data"])
	if not bool(encoded["ok"]):
		return _failure(encoded["errors"], path)
	if encoded["text"] != expected_text:
		return _failure(
			["Saved level differs from its canonical JSON snapshot."],
			path
		)

	return loaded


static func _write_text_file(path: String, text: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not is_instance_valid(file):
		return _failure(
			[
				"Could not open temporary level file (error %d)."
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
				"Could not write temporary level file (error %d)."
				% write_error
			]
		)

	return _success({})


static func _open_user_level_directory(create: bool) -> Dictionary:
	var user_directory := DirAccess.open("user://")
	if not is_instance_valid(user_directory):
		return _directory_failure(
			"Could not open the user data directory (error %d)."
			% DirAccess.get_open_error()
		)

	if user_directory.dir_exists(USER_LEVEL_DIRECTORY):
		if user_directory.is_link(USER_LEVEL_DIRECTORY):
			return _directory_failure(
				"User level directory must not be a symbolic link."
			)
	else:
		if not create:
			return {
				"ok": true,
				"exists": false,
				"directory": null,
				"errors": [] as Array[String],
			}

		var create_error := user_directory.make_dir(
			USER_LEVEL_DIRECTORY
		)
		if create_error != OK:
			return _directory_failure(
				"Could not create the user level directory (error %d)."
				% create_error
			)

	var level_directory := DirAccess.open(USER_LEVEL_ROOT)
	if not is_instance_valid(level_directory):
		return _directory_failure(
			"Could not open the user level directory (error %d)."
			% DirAccess.get_open_error()
		)
	level_directory.include_hidden = true

	return {
		"ok": true,
		"exists": true,
		"directory": level_directory,
		"errors": [] as Array[String],
	}


static func _recover_all_interrupted_saves(
	directory: DirAccess
) -> Dictionary:
	var level_ids := {}
	for file_name: String in directory.get_files():
		var auxiliary := _owned_auxiliary_info(file_name)
		if not auxiliary.is_empty():
			level_ids[str(auxiliary["level_id"])] = true

	var ordered_ids: Array = level_ids.keys()
	ordered_ids.sort()
	var failures: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var recoveries: Array[Dictionary] = []
	for level_id: Variant in ordered_ids:
		var recovery_result := _recover_interrupted_save(
			str(level_id),
			directory
		)
		if not bool(recovery_result["ok"]):
			failures.append(
				{
					"level_id": str(level_id),
					"errors": recovery_result["errors"],
				}
			)
			for message: Variant in recovery_result["errors"]:
				errors.append(
					"Level '%s': %s" % [level_id, message]
				)
		else:
			for warning: Variant in recovery_result.get(
				"warnings",
				[]
			):
				warnings.append(str(warning))
			for recovery: Dictionary in recovery_result.get(
				"recoveries",
				[]
			):
				recoveries.append(recovery.duplicate(true))

	return {
		"ok": true,
		"data": {},
		"failures": failures,
		"errors": errors,
		"warnings": warnings,
		"recoveries": recoveries,
		"path": "",
	}


static func _recover_interrupted_save(
	level_id: String,
	directory: DirAccess
) -> Dictionary:
	var conflict_metadata := _existing_conflict_metadata(
		level_id,
		directory
	)
	var transaction_result := _recover_interrupted_transaction(
		level_id,
		directory
	)
	return _merge_recovery_metadata(
		transaction_result,
		conflict_metadata
	)


static func _existing_conflict_metadata(
	level_id: String,
	directory: DirAccess
) -> Dictionary:
	var warnings: Array[String] = []
	var recoveries: Array[Dictionary] = []
	for file_name: String in directory.get_files():
		var auxiliary := _owned_auxiliary_info(file_name)
		if (
			auxiliary.is_empty()
			or auxiliary["level_id"] != level_id
			or auxiliary["kind"] != "conflict"
		):
			continue

		var path := USER_LEVEL_ROOT.path_join(file_name)
		var message := (
			"Level '%s' has a preserved quarantine file at '%s'."
			% [level_id, path]
		)
		warnings.append(message)
		recoveries.append(
			{
				"level_id": level_id,
				"kind": "quarantine",
				"path": path,
				"message": message,
			}
		)

	return _success({}, "", warnings, recoveries)


static func _recover_interrupted_transaction(
	level_id: String,
	directory: DirAccess
) -> Dictionary:
	var backup_files: Array[Dictionary] = []
	var temporary_files: Array[Dictionary] = []
	for file_name: String in directory.get_files():
		var auxiliary := _owned_auxiliary_info(file_name)
		if (
			auxiliary.is_empty()
			or auxiliary["level_id"] != level_id
			or auxiliary["kind"] == "conflict"
		):
			continue
		if directory.is_link(file_name):
			return _failure(
				[
					"Recovery file for '%s' must not be a symbolic link."
					% level_id,
				]
			)

		var path := USER_LEVEL_ROOT.path_join(file_name)
		auxiliary["name"] = file_name
		auxiliary["path"] = path
		auxiliary["modified"] = FileAccess.get_modified_time(path)
		if auxiliary["kind"] == "bak":
			backup_files.append(auxiliary)
		else:
			temporary_files.append(auxiliary)

	if backup_files.is_empty() and temporary_files.is_empty():
		return _success({})

	_sort_auxiliary_files(backup_files)
	_sort_auxiliary_files(temporary_files)

	var target_name := _file_name_for_id(level_id)
	var target_path := _user_path_for_id(level_id)
	if directory.is_link(target_name):
		return _failure(
			["User level '%s' must not be a symbolic link." % level_id]
		)
	if directory.dir_exists(target_name):
		return _failure(
			["User level '%s' points to a directory, not a file." % level_id]
		)

	var target_exists := directory.file_exists(target_name)
	var current_result: Dictionary = {}
	if target_exists:
		current_result = _load_verified_file(target_path, level_id)
		if bool(current_result["ok"]):
			_remove_auxiliary_files(backup_files)
			_remove_auxiliary_files(temporary_files)
			return _success({})

	var recovery_candidate := _newest_valid_auxiliary(
		temporary_files,
		level_id
	)
	if recovery_candidate.is_empty():
		recovery_candidate = _newest_valid_auxiliary(
			backup_files,
			level_id
		)

	if recovery_candidate.is_empty():
		var candidate_errors: Array[String] = [
			(
				"No valid recovery file remains for user level '%s'; "
				+ "all transaction files were preserved."
			)
			% level_id
		]
		if not current_result.is_empty():
			candidate_errors.append_array(current_result["errors"])
		return _failure(candidate_errors, target_path)

	var conflict_path := ""
	if target_exists:
		if backup_files.is_empty():
			var current_errors: Array[String] = []
			current_errors.append_array(current_result["errors"])
			current_errors.append(
				(
					"The invalid current file and uncommitted temporary "
					+ "file were both preserved."
				)
			)
			return _failure(current_errors, target_path)

		conflict_path = _make_unique_auxiliary_path(
			directory,
			level_id,
			"conflict"
		)
		if conflict_path.is_empty():
			return _failure(
				[
					"Could not allocate a quarantine file for '%s'."
					% level_id
				],
				target_path
			)

		var quarantine_error := DirAccess.rename_absolute(
			target_path,
			conflict_path
		)
		if quarantine_error != OK:
			return _failure(
				[
					"Could not quarantine invalid level '%s' (error %d)."
					% [level_id, quarantine_error]
				],
				target_path
			)

	var promote_result := _promote_recovery_candidate(
		recovery_candidate,
		level_id,
		target_path
	)
	if not bool(promote_result["ok"]):
		var promote_errors: Array[String] = []
		promote_errors.append_array(promote_result["errors"])
		_restore_quarantined_target(
			conflict_path,
			target_path,
			promote_errors
		)
		return _failure(promote_errors, target_path)

	_remove_auxiliary_files(backup_files)
	_remove_auxiliary_files(temporary_files)
	var recovery_warnings: Array[String] = []
	var recoveries: Array[Dictionary] = []
	if not conflict_path.is_empty():
		var recovery_message := (
			"Recovered level '%s'; the invalid newer file was "
			+ "preserved at '%s'."
		) % [level_id, conflict_path]
		recovery_warnings.append(recovery_message)
		recoveries.append(
			{
				"level_id": level_id,
				"kind": "quarantine",
				"path": conflict_path,
				"message": recovery_message,
			}
		)

	return _success(
		{},
		target_path,
		recovery_warnings,
		recoveries
	)


static func _sort_auxiliary_files(
	files: Array[Dictionary]
) -> void:
	files.sort_custom(
		func(first: Dictionary, second: Dictionary) -> bool:
			var first_modified := int(first["modified"])
			var second_modified := int(second["modified"])
			if first_modified == second_modified:
				return str(first["name"]) > str(second["name"])
			return first_modified > second_modified
	)


static func _newest_valid_auxiliary(
	files: Array[Dictionary],
	level_id: String
) -> Dictionary:
	for file: Dictionary in files:
		var candidate_result := _load_verified_file(
			str(file["path"]),
			level_id
		)
		if bool(candidate_result["ok"]):
			return file
	return {}


static func _promote_recovery_candidate(
	candidate: Dictionary,
	level_id: String,
	target_path: String
) -> Dictionary:
	var promote_error := DirAccess.rename_absolute(
		str(candidate["path"]),
		target_path
	)
	if promote_error != OK:
		return _failure(
			[
				"Could not promote recovery file for '%s' (error %d)."
				% [level_id, promote_error]
			],
			target_path
		)

	var restored_result := _load_verified_file(target_path, level_id)
	if not bool(restored_result["ok"]):
		return _failure(restored_result["errors"], target_path)
	return _success({}, target_path)


static func _restore_quarantined_target(
	conflict_path: String,
	target_path: String,
	errors: Array[String]
) -> void:
	if conflict_path.is_empty() or not FileAccess.file_exists(conflict_path):
		return
	_remove_if_present(target_path)
	var restore_error := DirAccess.rename_absolute(
		conflict_path,
		target_path
	)
	if restore_error != OK:
		errors.append(
			(
				"Could not restore quarantined file (error %d); "
				+ "it remains at '%s'."
			)
			% [restore_error, conflict_path]
		)


static func _remove_auxiliary_files(
	files: Array[Dictionary]
) -> void:
	for file: Dictionary in files:
		_remove_if_present(str(file["path"]))


static func _owned_auxiliary_info(file_name: String) -> Dictionary:
	if not file_name.begins_with(
		".%s." % AUXILIARY_NAMESPACE
	):
		return {}

	var parts := file_name.split(".", false)
	if (
		parts.size() != 4
		or parts[0] != AUXILIARY_NAMESPACE
	):
		return {}

	var level_id := str(parts[1])
	var token := str(parts[2])
	var kind := str(parts[3])
	if (
		not _validate_level_id(level_id).is_empty()
		or kind not in ["tmp", "bak", "conflict"]
	):
		return {}

	var token_parts := token.split("_", false)
	if token_parts.size() != 3:
		return {}
	for token_part: String in token_parts:
		if not _is_ascii_digits_string(token_part):
			return {}

	return {
		"level_id": level_id,
		"token": token,
		"kind": kind,
	}


static func _is_ascii_digits_string(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		if not _is_ascii_digit(value.unicode_at(index)):
			return false
	return true


static func _make_unique_auxiliary_path(
	directory: DirAccess,
	level_id: String,
	kind: String
) -> String:
	for attempt in 16:
		var file_name := ".%s.%s.%d_%d_%d.%s" % [
			AUXILIARY_NAMESPACE,
			level_id,
			OS.get_process_id(),
			Time.get_ticks_usec(),
			attempt,
			kind,
		]
		if not _directory_has_name(directory, file_name):
			return USER_LEVEL_ROOT.path_join(file_name)
	return ""


static func _directory_has_name(
	directory: DirAccess,
	file_name: String
) -> bool:
	return (
		directory.file_exists(file_name)
		or directory.dir_exists(file_name)
		or directory.is_link(file_name)
	)


static func _restore_backup(
	backup_path: String,
	target_path: String,
	errors: Array[String]
) -> void:
	if backup_path.is_empty() or not FileAccess.file_exists(backup_path):
		return

	if FileAccess.file_exists(target_path):
		var remove_error := DirAccess.remove_absolute(target_path)
		if remove_error != OK:
			errors.append(
				"Could not remove the failed replacement (error %d)."
				% remove_error
			)
			return

	var restore_error := DirAccess.rename_absolute(
		backup_path,
		target_path
	)
	if restore_error != OK:
		errors.append(
			(
				"Could not restore the previous level (error %d); "
				+ "the backup remains at '%s'."
			)
			% [restore_error, backup_path]
		)


static func _remove_if_present(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var remove_error := DirAccess.remove_absolute(path)
	if remove_error != OK:
		push_warning(
			"Could not remove temporary level file '%s' (error %d)."
			% [path, remove_error]
		)


static func _file_name_for_id(level_id: String) -> String:
	return level_id + LEVEL_EXTENSION


static func _user_path_for_id(level_id: String) -> String:
	return USER_LEVEL_ROOT.path_join(_file_name_for_id(level_id))


static func _validate_level_id(level_id: String) -> String:
	if (
		level_id.is_empty()
		or level_id.length() > MAX_LEVEL_ID_LENGTH
	):
		return (
			"Level ID must contain 1 to %d characters."
			% MAX_LEVEL_ID_LENGTH
		)

	var first := level_id.unicode_at(0)
	if not _is_ascii_lower(first):
		return "Level ID must match [a-z][a-z0-9_]*."

	for index in range(1, level_id.length()):
		var character := level_id.unicode_at(index)
		if (
			not _is_ascii_lower(character)
			and not _is_ascii_digit(character)
			and character != 95
		):
			return "Level ID must match [a-z][a-z0-9_]*."

	if _is_windows_reserved_file_name(level_id):
		return "Level ID must not be a reserved Windows file name."

	return ""


static func _is_windows_reserved_file_name(value: String) -> bool:
	if value in ["con", "prn", "aux", "nul"]:
		return true
	if value.length() != 4:
		return false

	var prefix := value.left(3)
	var digit := value.unicode_at(3)
	return (
		(prefix == "com" or prefix == "lpt")
		and digit >= 49
		and digit <= 57
	)


static func _is_ascii_lower(character: int) -> bool:
	return character >= 97 and character <= 122


static func _is_ascii_digit(character: int) -> bool:
	return character >= 48 and character <= 57


static func _success(
	data: Variant,
	path: String = "",
	warnings: Array[String] = [],
	recoveries: Array[Dictionary] = []
) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"errors": [] as Array[String],
		"warnings": warnings,
		"recoveries": recoveries,
		"path": path,
	}


static func _failure(
	errors: Array,
	path: String = ""
) -> Dictionary:
	var messages: Array[String] = []
	for error: Variant in errors:
		messages.append(str(error))
	return {
		"ok": false,
		"data": {},
		"errors": messages,
		"warnings": [] as Array[String],
		"recoveries": [] as Array[Dictionary],
		"path": path,
	}


static func _merge_recovery_metadata(
	result: Dictionary,
	recovery_result: Dictionary
) -> Dictionary:
	var merged := result.duplicate(true)
	var warnings: Array[String] = []
	for warning: Variant in result.get("warnings", []):
		warnings.append(str(warning))
	for warning: Variant in recovery_result.get("warnings", []):
		warnings.append(str(warning))

	var recoveries: Array[Dictionary] = []
	for recovery: Dictionary in result.get("recoveries", []):
		recoveries.append(recovery.duplicate(true))
	for recovery: Dictionary in recovery_result.get("recoveries", []):
		recoveries.append(recovery.duplicate(true))

	merged["warnings"] = warnings
	merged["recoveries"] = recoveries
	return merged


static func _directory_failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"exists": false,
		"directory": null,
		"errors": [message] as Array[String],
		"warnings": [] as Array[String],
		"recoveries": [] as Array[Dictionary],
	}

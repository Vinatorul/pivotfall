class_name CampaignDataValidator
extends RefCounted

## Validates campaign data and returns a deterministic, storage-safe manifest.
##
## The campaign is a trusted project resource, but its paths still use a
## deliberately narrow allowlist. Public storage APIs expose stable IDs and
## never accept these paths from the editor or user levels.

const SCHEMA_VERSION := 1
const FINAL_BEHAVIOR_RESTART_FINAL_LEVEL := "restart_final_level"

const MAX_CAMPAIGN_ID_LENGTH := 64
const MAX_LEVEL_ID_LENGTH := 64
const MAX_CATALOG_TITLE_LENGTH := 80
const MAX_UI_TEXT_LENGTH := 160
const MAX_LEVELS := 64
const MAX_SAFE_FLOAT_INTEGER := 9_007_199_254_740_991.0
const LEVEL_PATH_PREFIX := "res://levels/"
const LEVEL_PATH_SUFFIX := ".json"

const ROOT_KEYS := [
	"schema_version",
	"campaign_id",
	"advance_message",
	"final_behavior",
	"levels",
]
const LEVEL_KEYS := [
	"level_id",
	"path",
	"catalog_title",
]


static func validate_json(source: String) -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK:
		return _failure(
			[
				"Invalid campaign JSON at line %d: %s."
				% [
					parser.get_error_line(),
					parser.get_error_message(),
				]
			]
		)

	return validate_and_normalize(parser.data)


static func validate_and_normalize(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("Campaign data must be a dictionary.")
		return _failure(errors)

	var root: Dictionary = raw
	_reject_unknown_keys(root, ROOT_KEYS, "root", errors)

	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"campaign_id": "",
		"advance_message": "",
		"final_behavior": "",
		"levels": [],
	}

	if _require_key(root, "schema_version", "root", errors):
		var schema_version: Variant = _read_integer(
			root["schema_version"],
			"root.schema_version",
			errors
		)
		if schema_version != null:
			if schema_version != SCHEMA_VERSION:
				errors.append(
					"root.schema_version must be %d; got %d."
					% [SCHEMA_VERSION, schema_version]
				)
			else:
				normalized["schema_version"] = schema_version

	if _require_key(root, "campaign_id", "root", errors):
		var campaign_id := _read_stable_id(
			root["campaign_id"],
			"root.campaign_id",
			MAX_CAMPAIGN_ID_LENGTH,
			errors
		)
		if not campaign_id.is_empty():
			if _is_windows_reserved_file_name(campaign_id):
				errors.append(
					(
						"root.campaign_id must not be a reserved "
						+ "Windows file name."
					)
				)
			else:
				normalized["campaign_id"] = campaign_id

	if _require_key(root, "advance_message", "root", errors):
		var advance_message: Variant = _read_text(
			root["advance_message"],
			"root.advance_message",
			1,
			MAX_UI_TEXT_LENGTH,
			errors
		)
		if advance_message != null:
			normalized["advance_message"] = advance_message

	if _require_key(root, "final_behavior", "root", errors):
		var final_behavior := _read_final_behavior(
			root["final_behavior"],
			errors
		)
		if not final_behavior.is_empty():
			normalized["final_behavior"] = final_behavior

	var normalized_levels: Array[Dictionary] = []
	var declared_level_ids := {}
	var declared_paths := {}
	if _require_key(root, "levels", "root", errors):
		if typeof(root["levels"]) != TYPE_ARRAY:
			errors.append("root.levels must be an array.")
		else:
			var levels: Array = root["levels"]
			if levels.is_empty():
				errors.append(
					"root.levels must contain at least one level."
				)
			if levels.size() > MAX_LEVELS:
				errors.append(
					"root.levels may contain at most %d levels."
					% MAX_LEVELS
				)

			var level_count_to_validate := mini(
				levels.size(),
				MAX_LEVELS
			)
			for index in level_count_to_validate:
				var level_result := _validate_level_entry(
					levels[index],
					index,
					declared_level_ids,
					declared_paths,
					errors
				)
				if bool(level_result["ok"]):
					normalized_levels.append(level_result["data"])

	normalized["levels"] = normalized_levels
	if not errors.is_empty():
		return _failure(errors)

	return {
		"ok": true,
		"data": normalized,
		"errors": errors,
		"warnings": [] as Array[String],
	}


static func _validate_level_entry(
	raw: Variant,
	index: int,
	known_ids: Dictionary,
	known_paths: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var entry_path := "root.levels[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s must be a dictionary." % entry_path)
		return {"ok": false, "data": {}}

	var entry: Dictionary = raw
	var error_count_before := errors.size()
	_reject_unknown_keys(entry, LEVEL_KEYS, entry_path, errors)

	var level_id := ""
	if _require_key(entry, "level_id", entry_path, errors):
		level_id = _read_stable_id(
			entry["level_id"],
			"%s.level_id" % entry_path,
			MAX_LEVEL_ID_LENGTH,
			errors
		)
		if not level_id.is_empty():
			if _is_windows_reserved_file_name(level_id):
				errors.append(
					(
						"%s.level_id must not be a reserved Windows "
						+ "file name."
					)
					% entry_path
				)
			elif known_ids.has(level_id):
				errors.append(
					(
						"%s.level_id duplicates '%s' from "
						+ "root.levels[%d]."
					)
					% [entry_path, level_id, known_ids[level_id]]
				)
			else:
				known_ids[level_id] = index

	var level_path := ""
	if _require_key(entry, "path", entry_path, errors):
		level_path = _read_level_path(
			entry["path"],
			"%s.path" % entry_path,
			errors
		)
		if not level_path.is_empty():
			if known_paths.has(level_path):
				errors.append(
					(
						"%s.path duplicates '%s' from "
						+ "root.levels[%d]."
					)
					% [entry_path, level_path, known_paths[level_path]]
				)
			else:
				known_paths[level_path] = index

	var catalog_title: Variant = null
	if _require_key(entry, "catalog_title", entry_path, errors):
		catalog_title = _read_text(
			entry["catalog_title"],
			"%s.catalog_title" % entry_path,
			1,
			MAX_CATALOG_TITLE_LENGTH,
			errors
		)

	if errors.size() != error_count_before:
		return {"ok": false, "data": {}}

	return {
		"ok": true,
		"data": {
			"level_id": level_id,
			"path": level_path,
			"catalog_title": catalog_title,
		},
	}


static func _read_final_behavior(
	raw: Variant,
	errors: Array[String]
) -> String:
	if typeof(raw) != TYPE_STRING:
		errors.append("root.final_behavior must be a string.")
		return ""

	var value := String(raw)
	if value != FINAL_BEHAVIOR_RESTART_FINAL_LEVEL:
		errors.append(
			(
				"root.final_behavior must be '%s'; got '%s'."
				% [FINAL_BEHAVIOR_RESTART_FINAL_LEVEL, value]
			)
		)
		return ""
	return value


static func _read_level_path(
	raw: Variant,
	path: String,
	errors: Array[String]
) -> String:
	if typeof(raw) != TYPE_STRING:
		errors.append("%s must be a string." % path)
		return ""

	var value := String(raw)
	if (
		not value.begins_with(LEVEL_PATH_PREFIX)
		or not value.ends_with(LEVEL_PATH_SUFFIX)
	):
		errors.append(
			(
				"%s must match "
				+ "res://levels/[a-z][a-z0-9_]*.json."
			)
			% path
		)
		return ""

	var stem_length := (
		value.length()
		- LEVEL_PATH_PREFIX.length()
		- LEVEL_PATH_SUFFIX.length()
	)
	if stem_length < 1 or stem_length > MAX_LEVEL_ID_LENGTH:
		errors.append(
			(
				"%s must match "
				+ "res://levels/[a-z][a-z0-9_]*.json."
			)
			% path
		)
		return ""

	var stem := value.substr(
		LEVEL_PATH_PREFIX.length(),
		stem_length
	)
	if (
		not _is_stable_id(stem)
		or _is_windows_reserved_file_name(stem)
	):
		errors.append(
			(
				"%s must match "
				+ "res://levels/[a-z][a-z0-9_]*.json."
			)
			% path
		)
		return ""

	return value


static func _read_integer(
	raw: Variant,
	path: String,
	errors: Array[String]
) -> Variant:
	var raw_type := typeof(raw)
	if raw_type != TYPE_INT and raw_type != TYPE_FLOAT:
		errors.append("%s must be an integer." % path)
		return null

	if raw_type == TYPE_INT:
		return int(raw)

	var number := float(raw)
	if (
		not is_finite(number)
		or number != floorf(number)
		or absf(number) > MAX_SAFE_FLOAT_INTEGER
	):
		errors.append(
			"%s must be a finite, exactly representable integer."
			% path
		)
		return null
	return int(number)


static func _read_stable_id(
	raw: Variant,
	path: String,
	maximum_length: int,
	errors: Array[String]
) -> String:
	if typeof(raw) != TYPE_STRING:
		errors.append("%s must be a string." % path)
		return ""

	var value := String(raw)
	if value.is_empty() or value.length() > maximum_length:
		errors.append(
			"%s must contain 1 to %d characters."
			% [path, maximum_length]
		)
		return ""
	if not _is_stable_id(value):
		errors.append("%s must match [a-z][a-z0-9_]*." % path)
		return ""
	return value


static func _read_text(
	raw: Variant,
	path: String,
	minimum_length: int,
	maximum_length: int,
	errors: Array[String]
) -> Variant:
	if typeof(raw) != TYPE_STRING:
		errors.append("%s must be a string." % path)
		return null

	var value := String(raw).strip_edges()
	if value.length() < minimum_length or value.length() > maximum_length:
		errors.append(
			"%s must contain %d to %d characters after trimming."
			% [path, minimum_length, maximum_length]
		)
		return null
	return value


static func _is_stable_id(value: String) -> bool:
	if value.is_empty():
		return false

	var first := value.unicode_at(0)
	if not _is_ascii_lower(first):
		return false

	for index in range(1, value.length()):
		var character := value.unicode_at(index)
		if (
			not _is_ascii_lower(character)
			and not _is_ascii_digit(character)
			and character != 95
		):
			return false
	return true


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


static func _require_key(
	value: Dictionary,
	key: String,
	path: String,
	errors: Array[String]
) -> bool:
	if value.has(key):
		return true
	errors.append("%s is missing required key '%s'." % [path, key])
	return false


static func _reject_unknown_keys(
	value: Dictionary,
	allowed_keys: Array,
	path: String,
	errors: Array[String]
) -> void:
	var unknown_keys: Array[String] = []
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING:
			unknown_keys.append(str(key))
		elif not allowed_keys.has(key):
			unknown_keys.append(String(key))

	unknown_keys.sort()
	for key: String in unknown_keys:
		errors.append("%s has unknown key '%s'." % [path, key])


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"errors": errors,
		"warnings": [] as Array[String],
	}

class_name CampaignStorage
extends RefCounted

## Resolves the read-only built-in campaign without consulting user storage.
##
## Every level is decoded and validated before a successful result is exposed.
## A missing or invalid level therefore invalidates the complete campaign
## instead of yielding a partially playable sequence.

const CAMPAIGN_DATA_CODEC := preload(
	"res://scripts/campaign/campaign_data_codec.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)

const BUILTIN_CAMPAIGN_PATH := "res://campaign.json"
const BUILTIN_CAMPAIGN_ID := "main"


static func list_builtin_levels() -> Array[Dictionary]:
	var campaign_result := load_builtin_campaign()
	var levels: Array[Dictionary] = []
	if not bool(campaign_result["ok"]):
		return levels

	for entry: Dictionary in campaign_result["entries"]:
		levels.append(
			{
				"id": entry["id"],
				"path": entry["path"],
				"title": entry["title"],
			}
		)
	return levels


static func load_builtin_level(level_id: String) -> Dictionary:
	var campaign_result := load_builtin_campaign()
	if not bool(campaign_result["ok"]):
		return _level_failure(
			campaign_result["errors"],
			BUILTIN_CAMPAIGN_PATH
		)

	for entry: Dictionary in campaign_result["entries"]:
		if entry["id"] == level_id:
			return _level_success(
				(entry["data"] as Dictionary).duplicate(true),
				entry["path"]
			)

	return _level_failure(
		[
			(
				"Built-in level '%s' does not exist in campaign '%s'."
				% [level_id, BUILTIN_CAMPAIGN_ID]
			)
		]
	)


static func load_builtin_campaign() -> Dictionary:
	var loaded: Dictionary = CAMPAIGN_DATA_CODEC.load_file(
		BUILTIN_CAMPAIGN_PATH
	)
	if not bool(loaded["ok"]):
		return _campaign_failure(
			loaded["errors"],
			BUILTIN_CAMPAIGN_PATH
		)

	var campaign_data: Dictionary = loaded["data"]
	if campaign_data["campaign_id"] != BUILTIN_CAMPAIGN_ID:
		return _campaign_failure(
			[
				(
					"Campaign ID '%s' does not match expected ID '%s'."
					% [
						campaign_data["campaign_id"],
						BUILTIN_CAMPAIGN_ID,
					]
				)
			],
			BUILTIN_CAMPAIGN_PATH
		)

	var resolved := resolve_campaign(campaign_data)
	resolved["path"] = BUILTIN_CAMPAIGN_PATH
	return resolved


static func resolve_campaign(raw: Variant) -> Dictionary:
	var encoded: Dictionary = CAMPAIGN_DATA_CODEC.encode(raw)
	if not bool(encoded["ok"]):
		return _campaign_failure(encoded["errors"])

	var campaign_data: Dictionary = encoded["data"]
	var entries: Array[Dictionary] = []
	var errors: Array[String] = []
	var warnings: Array[String] = []

	for warning: Variant in encoded.get("warnings", []):
		warnings.append(str(warning))

	var levels: Array = campaign_data["levels"]
	for index in levels.size():
		var definition: Dictionary = levels[index]
		var level_path: String = definition["path"]
		var loaded: Dictionary = LEVEL_DATA_CODEC.load_file(level_path)
		if not bool(loaded["ok"]):
			for error: Variant in loaded.get("errors", []):
				errors.append(
					(
						"root.levels[%d].path '%s': %s"
						% [index, level_path, error]
					)
				)
			continue

		var level_data: Dictionary = loaded["data"]
		var expected_level_id: String = definition["level_id"]
		var actual_level_id := str(
			level_data.get("level_id", "")
		)
		if actual_level_id != expected_level_id:
			errors.append(
				(
					"root.levels[%d].level_id '%s' does not match "
					+ "loaded level ID '%s'."
				)
				% [index, expected_level_id, actual_level_id]
			)
			continue

		for warning: Variant in loaded.get("warnings", []):
			warnings.append(
				(
					"root.levels[%d] ('%s'): %s"
					% [index, expected_level_id, warning]
				)
			)

		entries.append(
			{
				"id": expected_level_id,
				"path": level_path,
				"title": definition["catalog_title"],
				"data": level_data,
			}
		)

	if not errors.is_empty():
		return _campaign_failure(errors)

	return _campaign_success(
		campaign_data,
		entries,
		warnings
	)


static func _campaign_success(
	data: Dictionary,
	entries: Array[Dictionary],
	warnings: Array[String]
) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"entries": entries,
		"errors": [] as Array[String],
		"warnings": warnings,
		"path": "",
	}


static func _campaign_failure(
	errors: Array,
	path: String = ""
) -> Dictionary:
	var messages: Array[String] = []
	for error: Variant in errors:
		messages.append(str(error))
	return {
		"ok": false,
		"data": {},
		"entries": [] as Array[Dictionary],
		"errors": messages,
		"warnings": [] as Array[String],
		"path": path,
	}


static func _level_success(
	data: Dictionary,
	path: String
) -> Dictionary:
	return {
		"ok": true,
		"data": data,
		"errors": [] as Array[String],
		"warnings": [] as Array[String],
		"recoveries": [] as Array[Dictionary],
		"path": path,
	}


static func _level_failure(
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

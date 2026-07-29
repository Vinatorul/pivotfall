class_name LevelDataCodec
extends RefCounted

const MAX_FILE_BYTES := 262_144
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)


static func load_file(path: String) -> Dictionary:
	if path.is_empty():
		return _failure(["Level path is empty."])
	if not FileAccess.file_exists(path):
		return _failure(["Level file does not exist: %s." % path])

	var file := FileAccess.open(path, FileAccess.READ)
	if not is_instance_valid(file):
		return _failure(
			[
				"Could not open level file '%s' (error %d)."
				% [path, FileAccess.get_open_error()]
			]
		)
	if file.get_length() > MAX_FILE_BYTES:
		return _failure(
			[
				"Level file exceeds the %d byte limit."
				% MAX_FILE_BYTES
			]
		)

	return decode_text(file.get_as_text())


static func decode_text(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure(
			[
				"Level JSON exceeds the %d byte limit."
				% MAX_FILE_BYTES
			]
		)

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return _failure(
			[
				"Invalid level JSON at line %d: %s."
				% [json.get_error_line(), json.get_error_message()]
			]
		)

	return LEVEL_DATA_VALIDATOR.validate_and_normalize(json.data)


static func encode(data: Variant) -> Dictionary:
	var validation := LEVEL_DATA_VALIDATOR.validate_and_normalize(data)
	if not bool(validation["ok"]):
		return validation

	var text := JSON.stringify(
		validation["data"],
		"\t",
		true,
		false
	) + "\n"
	return {
		"ok": true,
		"data": validation["data"],
		"errors": [] as Array[String],
		"text": text,
	}


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"errors": errors,
		"text": "",
	}

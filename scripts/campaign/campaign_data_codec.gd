class_name CampaignDataCodec
extends RefCounted

const MAX_FILE_BYTES := 65_536
const CAMPAIGN_DATA_VALIDATOR := preload(
	"res://scripts/campaign/campaign_data_validator.gd"
)


static func load_file(path: String) -> Dictionary:
	if path.is_empty():
		return _failure(["Campaign path is empty."])
	if not FileAccess.file_exists(path):
		return _failure(
			["Campaign file does not exist: %s." % path]
		)

	var file := FileAccess.open(path, FileAccess.READ)
	if not is_instance_valid(file):
		return _failure(
			[
				"Could not open campaign file '%s' (error %d)."
				% [path, FileAccess.get_open_error()]
			]
		)
	if file.get_length() > MAX_FILE_BYTES:
		return _failure(
			[
				"Campaign file exceeds the %d byte limit."
				% MAX_FILE_BYTES
			]
		)

	return decode_text(file.get_as_text())


static func decode_text(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure(
			[
				"Campaign JSON exceeds the %d byte limit."
				% MAX_FILE_BYTES
			]
		)

	var parser := JSON.new()
	var parse_error := parser.parse(text)
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

	return CAMPAIGN_DATA_VALIDATOR.validate_and_normalize(
		parser.data
	)


static func encode(data: Variant) -> Dictionary:
	var validation: Dictionary = (
		CAMPAIGN_DATA_VALIDATOR.validate_and_normalize(data)
	)
	if not bool(validation["ok"]):
		return validation

	var text := JSON.stringify(
		validation["data"],
		"\t",
		true,
		false
	) + "\n"
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure(
			[
				"Encoded campaign JSON exceeds the %d byte limit."
				% MAX_FILE_BYTES
			]
		)

	return {
		"ok": true,
		"data": validation["data"],
		"errors": [] as Array[String],
		"warnings": validation.get("warnings", []),
		"text": text,
	}


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"errors": errors,
		"warnings": [] as Array[String],
		"text": "",
	}

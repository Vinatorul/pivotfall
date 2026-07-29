class_name LevelDraft
extends RefCounted

signal changed

const MAX_HISTORY := 100
const MAX_OBJECT_ID_LENGTH := 64
const ROOT_EDITABLE_KEYS := [
	"level_id",
	"title",
	"objective",
	"clear_message",
]

var _data: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _clean_signature := ""


func replace(data: Dictionary, mark_clean := true) -> void:
	_data = data.duplicate(true)
	_undo_stack.clear()
	_redo_stack.clear()
	_clean_signature = _signature(_data) if mark_clean else "__unsaved__"
	changed.emit()


func to_dictionary() -> Dictionary:
	return _data.duplicate(true)


func find_object(object_id: String) -> Dictionary:
	var index := _find_object_index(object_id)
	if index < 0:
		return {}
	return (_data["objects"][index] as Dictionary).duplicate(true)


func find_first_object_of_type(object_type: String) -> Dictionary:
	for object: Dictionary in _data.get("objects", []):
		if object.get("type", "") == object_type:
			return object.duplicate(true)
	return {}


func set_root_value(key: String, value: Variant) -> bool:
	if key not in ROOT_EDITABLE_KEYS:
		return false

	var next := _data.duplicate(true)
	next[key] = value
	return _apply(next)


func add_object(definition: Dictionary) -> bool:
	if definition.is_empty():
		return false

	var object_id: String = definition.get("id", "")
	if object_id.is_empty() or _find_object_index(object_id) >= 0:
		return false

	var next := _data.duplicate(true)
	var objects: Array = next.get("objects", [])
	objects.append(definition.duplicate(true))
	next["objects"] = objects
	return _apply(next)


func update_object(object_id: String, values: Dictionary) -> bool:
	var index := _find_object_index(object_id)
	if index < 0:
		return false

	var next := _data.duplicate(true)
	var object: Dictionary = next["objects"][index]
	for key: Variant in values:
		if key in ["id", "type"]:
			continue
		object[key] = values[key]
	next["objects"][index] = object
	return _apply(next)


func remove_object(object_id: String) -> bool:
	var index := _find_object_index(object_id)
	if index < 0:
		return false

	var next := _data.duplicate(true)
	next["objects"].remove_at(index)
	return _apply(next)


func undo() -> bool:
	if _undo_stack.is_empty():
		return false

	_redo_stack.append(_data.duplicate(true))
	_data = _undo_stack.pop_back()
	changed.emit()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false

	_undo_stack.append(_data.duplicate(true))
	_data = _redo_stack.pop_back()
	changed.emit()
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func is_dirty() -> bool:
	return _signature(_data) != _clean_signature


func mark_saved() -> void:
	_clean_signature = _signature(_data)
	changed.emit()


func make_unique_id(prefix: String) -> String:
	var safe_prefix := _sanitize_prefix(prefix).left(
		MAX_OBJECT_ID_LENGTH
	).trim_suffix("_")
	if safe_prefix.is_empty():
		safe_prefix = "object"
	if _find_object_index(safe_prefix) < 0:
		return safe_prefix

	var suffix := 2
	while suffix <= 10_000:
		var suffix_text := "_%d" % suffix
		var candidate := (
			safe_prefix.left(
				MAX_OBJECT_ID_LENGTH - suffix_text.length()
			).trim_suffix("_")
			+ suffix_text
		)
		if _find_object_index(candidate) < 0:
			return candidate
		suffix += 1

	var fallback_suffix := "_%d" % Time.get_ticks_msec()
	return (
		safe_prefix.left(
			MAX_OBJECT_ID_LENGTH - fallback_suffix.length()
		).trim_suffix("_")
		+ fallback_suffix
	)


func _apply(next: Dictionary) -> bool:
	if _signature(next) == _signature(_data):
		return false

	_undo_stack.append(_data.duplicate(true))
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_data = next
	changed.emit()
	return true


func _find_object_index(object_id: String) -> int:
	var objects: Array = _data.get("objects", [])
	for index in objects.size():
		var object: Dictionary = objects[index]
		if object.get("id", "") == object_id:
			return index
	return -1


func _sanitize_prefix(prefix: String) -> String:
	var normalized := prefix.to_lower()
	var result := ""
	for index in normalized.length():
		var character := normalized.unicode_at(index)
		if (
			(character >= 97 and character <= 122)
			or (character >= 48 and character <= 57 and not result.is_empty())
			or (character == 95 and not result.is_empty())
		):
			result += String.chr(character)
		elif not result.is_empty() and not result.ends_with("_"):
			result += "_"

	result = result.trim_suffix("_")
	return result if not result.is_empty() else "object"


func _signature(value: Dictionary) -> String:
	return JSON.stringify(value, "", true, false)

class_name LevelDataValidator
extends RefCounted

## Validates untrusted level data and returns a canonical dictionary for LevelBuilder.
##
## Public results always have the shape:
##     {
##         "ok": bool,
##         "data": Dictionary,
##         "errors": Array[String],
##         "warnings": Array[String],
##     }
## Invalid input never exposes partially normalized data through `data`.

const SCHEMA_VERSION := 1

const DEFAULT_OBJECTIVE := ""
const DEFAULT_CLEAR_MESSAGE := "АРЕНА ПРОЙДЕНА  /  ПЕРЕЗАПУСК..."
const DEFAULT_PATROL_DIRECTION := -1
const DEFAULT_PATROL_SPEED := 85.0

const MAX_LEVEL_ID_LENGTH := 64
const MAX_OBJECT_ID_LENGTH := 64
const MAX_TITLE_LENGTH := 80
const MAX_UI_TEXT_LENGTH := 160
const CANVAS_WIDTH := 960
const CANVAS_HEIGHT := 540
const PLAYFIELD_LEFT := 32
const PLAYFIELD_TOP := 32
const PLAYFIELD_RIGHT := 928
const PLAYFIELD_BOTTOM := 540
const MAX_GRID_SIZE := 512
const MAX_OBJECTS := 512
const MAX_PATROL_SPEED := 1000.0
const MAX_SAFE_FLOAT_INTEGER := 9_007_199_254_740_991.0
const MAX_SUPPORT_WARNING_GAP := 64.0
const MIN_SHOVE_RUNWAY := 48.0
const TOGGLE_PLATFORM_HEIGHT := 20
const MIN_TOGGLE_PLATFORM_WIDTH := 20
const HINGE_RADIUS := 18
const ACTOR_HALF_EXTENTS := {
	"player_spawn": Vector2i(14, 20),
	"patrol_enemy": Vector2i(15, 18),
	"shove_enemy": Vector2i(16, 19),
}

const ROOT_KEYS := [
	"schema_version",
	"level_id",
	"title",
	"objective",
	"clear_message",
	"canvas",
	"objects",
]
const CANVAS_KEYS := ["width", "height", "grid_size"]
const SOLID_RECT_KEYS := ["id", "type", "rect"]
const PLAYER_SPAWN_KEYS := ["id", "type", "position"]
const PATROL_ENEMY_KEYS := [
	"id",
	"type",
	"position",
	"direction",
	"speed",
]
const SHOVE_ENEMY_KEYS := ["id", "type", "position", "direction"]
const TOGGLE_PLATFORM_KEYS := [
	"id",
	"type",
	"rect",
	"starts_active",
]
const HINGE_KEYS := ["id", "type", "position", "target_id"]
const SUPPORTED_TYPES := [
	"solid_rect",
	"player_spawn",
	"patrol_enemy",
	"shove_enemy",
	"toggle_platform",
	"hinge",
]
const ENEMY_TYPES := ["patrol_enemy", "shove_enemy"]


## Parses JSON text, then applies the same validation as dictionary input.
static func validate_json(source: String) -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK:
		return _failure([
			"Invalid JSON at line %d: %s."
			% [parser.get_error_line(), parser.get_error_message()]
		])

	return validate_and_normalize(parser.data)


## Validates a dictionary-like Variant and returns canonical, builder-safe data.
static func validate_and_normalize(raw: Variant) -> Dictionary:
	var errors: Array[String] = []
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("Level data must be a dictionary.")
		return _failure(errors)

	var root: Dictionary = raw
	_reject_unknown_keys(root, ROOT_KEYS, "root", errors)

	var normalized := {
		"schema_version": SCHEMA_VERSION,
		"level_id": "",
		"title": "",
		"objective": DEFAULT_OBJECTIVE,
		"clear_message": DEFAULT_CLEAR_MESSAGE,
		"canvas": {},
		"objects": [],
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

	if _require_key(root, "level_id", "root", errors):
		var level_id := _read_stable_id(
			root["level_id"],
			"root.level_id",
			MAX_LEVEL_ID_LENGTH,
			errors
		)
		if not level_id.is_empty():
			if _is_windows_reserved_file_name(level_id):
				errors.append(
					(
						"root.level_id must not be a reserved Windows "
						+ "file name."
					)
				)
			else:
				normalized["level_id"] = level_id

	if _require_key(root, "title", "root", errors):
		var title: Variant = _read_text(
			root["title"],
			"root.title",
			1,
			MAX_TITLE_LENGTH,
			errors
		)
		if title != null:
			normalized["title"] = title

	if root.has("objective"):
		var objective: Variant = _read_text(
			root["objective"],
			"root.objective",
			0,
			MAX_UI_TEXT_LENGTH,
			errors
		)
		if objective != null:
			normalized["objective"] = objective

	if root.has("clear_message"):
		var clear_message: Variant = _read_text(
			root["clear_message"],
			"root.clear_message",
			1,
			MAX_UI_TEXT_LENGTH,
			errors
		)
		if clear_message != null:
			normalized["clear_message"] = clear_message

	var canvas_size := Vector2i.ZERO
	if _require_key(root, "canvas", "root", errors):
		var canvas_result := _validate_canvas(root["canvas"], errors)
		if canvas_result["ok"]:
			normalized["canvas"] = canvas_result["data"]
			canvas_size = Vector2i(
				canvas_result["data"]["width"],
				canvas_result["data"]["height"]
			)

	var normalized_objects: Array[Dictionary] = []
	var player_count := 0
	var enemy_count := 0
	var declared_object_ids := {}
	if _require_key(root, "objects", "root", errors):
		if typeof(root["objects"]) != TYPE_ARRAY:
			errors.append("root.objects must be an array.")
		else:
			var objects: Array = root["objects"]
			if objects.size() > MAX_OBJECTS:
				errors.append(
					"root.objects may contain at most %d objects."
					% MAX_OBJECTS
				)

			var object_count_to_validate := mini(
				objects.size(),
				MAX_OBJECTS
			)
			for index in object_count_to_validate:
				var object_result := _validate_object(
					objects[index],
					index,
					canvas_size,
					declared_object_ids,
					errors
				)
				if not object_result["ok"]:
					continue

				var normalized_object: Dictionary = object_result["data"]
				normalized_objects.append(normalized_object)
				if normalized_object["type"] == "player_spawn":
					player_count += 1
				if ENEMY_TYPES.has(normalized_object["type"]):
					enemy_count += 1

	if player_count != 1:
		errors.append(
			"root.objects must contain exactly one player_spawn; found %d."
			% player_count
		)
	if enemy_count < 1:
		errors.append(
			"root.objects must contain at least one enemy."
		)

	_validate_links(
		normalized_objects,
		declared_object_ids,
		errors
	)
	_validate_actor_placements(normalized_objects, errors)
	normalized["objects"] = normalized_objects
	if not errors.is_empty():
		return _failure(errors)

	return {
		"ok": true,
		"data": normalized,
		"errors": errors,
		"warnings": _collect_warnings(normalized_objects),
	}


static func _validate_canvas(raw: Variant, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("root.canvas must be a dictionary.")
		return {"ok": false, "data": {}}

	var canvas: Dictionary = raw
	_reject_unknown_keys(canvas, CANVAS_KEYS, "root.canvas", errors)
	var error_count_before := errors.size()
	var width: Variant = null
	var height: Variant = null
	var grid_size: Variant = null

	if _require_key(canvas, "width", "root.canvas", errors):
		width = _read_integer(
			canvas["width"],
			"root.canvas.width",
			errors,
			1,
			CANVAS_WIDTH
		)
	if _require_key(canvas, "height", "root.canvas", errors):
		height = _read_integer(
			canvas["height"],
			"root.canvas.height",
			errors,
			1,
			CANVAS_HEIGHT
		)
	if _require_key(canvas, "grid_size", "root.canvas", errors):
		grid_size = _read_integer(
			canvas["grid_size"],
			"root.canvas.grid_size",
			errors,
			1,
			MAX_GRID_SIZE
		)

	if width != null and width != CANVAS_WIDTH:
		errors.append(
			"root.canvas.width must be %d for schema version %d."
			% [CANVAS_WIDTH, SCHEMA_VERSION]
		)
	if height != null and height != CANVAS_HEIGHT:
		errors.append(
			"root.canvas.height must be %d for schema version %d."
			% [CANVAS_HEIGHT, SCHEMA_VERSION]
		)
	if (
		width != null
		and height != null
		and grid_size != null
		and grid_size > mini(width, height)
	):
		errors.append(
			"root.canvas.grid_size must not exceed the canvas dimensions."
		)

	if errors.size() != error_count_before:
		return {"ok": false, "data": {}}

	return {
		"ok": true,
		"data": {
			"width": width,
			"height": height,
			"grid_size": grid_size,
		},
	}


static func _validate_object(
	raw: Variant,
	index: int,
	canvas_size: Vector2i,
	known_ids: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var path := "root.objects[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s must be a dictionary." % path)
		return {"ok": false, "data": {}}

	var object: Dictionary = raw
	var error_count_before := errors.size()
	var object_id := ""
	if _require_key(object, "id", path, errors):
		object_id = _read_stable_id(
			object["id"],
			"%s.id" % path,
			MAX_OBJECT_ID_LENGTH,
			errors
		)
		if not object_id.is_empty():
			if known_ids.has(object_id):
				errors.append(
					"%s.id duplicates '%s' from root.objects[%d]."
					% [path, object_id, known_ids[object_id]]
				)
			else:
				known_ids[object_id] = index

	var object_type := ""
	if _require_key(object, "type", path, errors):
		if typeof(object["type"]) != TYPE_STRING:
			errors.append("%s.type must be a string." % path)
		else:
			object_type = String(object["type"])
			if not SUPPORTED_TYPES.has(object_type):
				errors.append(
					"%s.type '%s' is not supported."
					% [path, object_type]
				)

	match object_type:
		"solid_rect":
			_reject_unknown_keys(object, SOLID_RECT_KEYS, path, errors)
			var rect: Variant = null
			if _require_key(object, "rect", path, errors):
				rect = _read_int_array(
					object["rect"],
					"%s.rect" % path,
					4,
					errors
				)
				if rect != null:
					_validate_rect_bounds(rect, canvas_size, path, errors)

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"rect": rect,
				},
			}

		"player_spawn":
			_reject_unknown_keys(object, PLAYER_SPAWN_KEYS, path, errors)
			var position: Variant = null
			if _require_key(object, "position", path, errors):
				position = _read_int_array(
					object["position"],
					"%s.position" % path,
					2,
					errors
				)
				if position != null:
					_validate_point_bounds(
						position,
						canvas_size,
						"%s.position" % path,
						errors
					)

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"position": position,
				},
			}

		"patrol_enemy":
			_reject_unknown_keys(object, PATROL_ENEMY_KEYS, path, errors)
			var position: Variant = null
			var direction: Variant = DEFAULT_PATROL_DIRECTION
			var speed: Variant = DEFAULT_PATROL_SPEED
			if _require_key(object, "position", path, errors):
				position = _read_int_array(
					object["position"],
					"%s.position" % path,
					2,
					errors
				)
				if position != null:
					_validate_point_bounds(
						position,
						canvas_size,
						"%s.position" % path,
						errors
					)

			if object.has("direction"):
				direction = _read_integer(
					object["direction"],
					"%s.direction" % path,
					errors
				)
				if direction != null and direction != -1 and direction != 1:
					errors.append(
						"%s.direction must be -1 or 1." % path
					)

			if object.has("speed"):
				speed = _read_finite_number(
					object["speed"],
					"%s.speed" % path,
					errors,
					0.0,
					MAX_PATROL_SPEED
				)

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"position": position,
					"direction": direction,
					"speed": speed,
				},
			}

		"shove_enemy":
			_reject_unknown_keys(object, SHOVE_ENEMY_KEYS, path, errors)
			var position: Variant = null
			var direction: Variant = DEFAULT_PATROL_DIRECTION
			if _require_key(object, "position", path, errors):
				position = _read_int_array(
					object["position"],
					"%s.position" % path,
					2,
					errors
				)
				if position != null:
					_validate_point_bounds(
						position,
						canvas_size,
						"%s.position" % path,
						errors
					)

			if object.has("direction"):
				direction = _read_integer(
					object["direction"],
					"%s.direction" % path,
					errors
				)
				if direction != null and direction != -1 and direction != 1:
					errors.append(
						"%s.direction must be -1 or 1." % path
					)

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"position": position,
					"direction": direction,
				},
			}

		"toggle_platform":
			_reject_unknown_keys(
				object,
				TOGGLE_PLATFORM_KEYS,
				path,
				errors
			)
			var rect: Variant = null
			var starts_active := true
			if _require_key(object, "rect", path, errors):
				rect = _read_int_array(
					object["rect"],
					"%s.rect" % path,
					4,
					errors
				)
				if rect != null:
					_validate_rect_bounds(rect, canvas_size, path, errors)
					_validate_toggle_platform_playfield_bounds(
						rect,
						object_id,
						errors
					)
					if rect[2] < MIN_TOGGLE_PLATFORM_WIDTH:
						errors.append(
							"%s.rect width must be at least %d."
							% [path, MIN_TOGGLE_PLATFORM_WIDTH]
						)
					if rect[3] != TOGGLE_PLATFORM_HEIGHT:
						errors.append(
							"%s.rect height must be exactly %d."
							% [path, TOGGLE_PLATFORM_HEIGHT]
						)

			if object.has("starts_active"):
				var active_result: Variant = _read_boolean(
					object["starts_active"],
					"%s.starts_active" % path,
					errors
				)
				if active_result != null:
					starts_active = active_result

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"rect": rect,
					"starts_active": starts_active,
				},
			}

		"hinge":
			_reject_unknown_keys(object, HINGE_KEYS, path, errors)
			var position: Variant = null
			var target_id := ""
			if _require_key(object, "position", path, errors):
				position = _read_int_array(
					object["position"],
					"%s.position" % path,
					2,
					errors
				)
				if position != null:
					_validate_point_bounds(
						position,
						canvas_size,
						"%s.position" % path,
						errors
					)
					_validate_hinge_playfield_bounds(
						position,
						object_id,
						errors
					)

			if _require_key(object, "target_id", path, errors):
				target_id = _read_stable_id(
					object["target_id"],
					"%s.target_id" % path,
					MAX_OBJECT_ID_LENGTH,
					errors
				)

			if errors.size() != error_count_before:
				return {"ok": false, "data": {}}
			return {
				"ok": true,
				"data": {
					"id": object_id,
					"type": object_type,
					"position": position,
					"target_id": target_id,
				},
			}

	return {"ok": false, "data": {}}


static func _validate_rect_bounds(
	rect: Array,
	canvas_size: Vector2i,
	path: String,
	errors: Array[String]
) -> void:
	var x: int = rect[0]
	var y: int = rect[1]
	var width: int = rect[2]
	var height: int = rect[3]

	if width <= 0 or height <= 0:
		errors.append("%s.rect width and height must be greater than zero." % path)
		return

	if canvas_size == Vector2i.ZERO:
		return

	if (
		x < 0
		or y < 0
		or x > canvas_size.x
		or y > canvas_size.y
		or width > canvas_size.x
		or height > canvas_size.y
		or x + width > canvas_size.x
		or y + height > canvas_size.y
	):
		errors.append(
			"%s.rect must fit inside the %dx%d canvas."
			% [path, canvas_size.x, canvas_size.y]
		)


static func _validate_point_bounds(
	point: Array,
	canvas_size: Vector2i,
	path: String,
	errors: Array[String]
) -> void:
	if canvas_size == Vector2i.ZERO:
		return

	var x: int = point[0]
	var y: int = point[1]
	if x < 0 or y < 0 or x >= canvas_size.x or y >= canvas_size.y:
		errors.append(
			"%s must be inside the %dx%d canvas."
			% [path, canvas_size.x, canvas_size.y]
		)


static func _validate_hinge_playfield_bounds(
	point: Array,
	object_id: String,
	errors: Array[String]
) -> void:
	var x: int = point[0]
	var y: int = point[1]
	if (
		x - HINGE_RADIUS < PLAYFIELD_LEFT
		or y - HINGE_RADIUS < PLAYFIELD_TOP
		or x + HINGE_RADIUS > PLAYFIELD_RIGHT
		or y + HINGE_RADIUS > PLAYFIELD_BOTTOM
	):
		errors.append(
			(
				"Object '%s' collision bounds must fit inside "
				+ "the runtime playfield."
			)
			% object_id
		)


static func _validate_toggle_platform_playfield_bounds(
	rect: Array,
	object_id: String,
	errors: Array[String]
) -> void:
	var x: int = rect[0]
	var y: int = rect[1]
	var width: int = rect[2]
	var height: int = rect[3]
	if (
		x < PLAYFIELD_LEFT
		or y < PLAYFIELD_TOP
		or x + width > PLAYFIELD_RIGHT
		or y + height > PLAYFIELD_BOTTOM
	):
		errors.append(
			(
				"Object '%s' bounds must fit inside "
				+ "the runtime playfield."
			)
			% object_id
		)


static func _validate_links(
	objects: Array[Dictionary],
	declared_object_ids: Dictionary,
	errors: Array[String]
) -> void:
	var objects_by_id := {}
	for object: Dictionary in objects:
		objects_by_id[object["id"]] = object

	for object: Dictionary in objects:
		if object["type"] != "hinge":
			continue

		var object_id: String = object["id"]
		var target_id: String = object["target_id"]
		if target_id == object_id:
			errors.append(
				"Hinge '%s' must not target itself." % object_id
			)
			continue
		if not objects_by_id.has(target_id):
			if not declared_object_ids.has(target_id):
				errors.append(
					"Hinge '%s' targets missing object '%s'."
					% [object_id, target_id]
				)
			continue

		var target: Dictionary = objects_by_id[target_id]
		if target["type"] != "toggle_platform":
			errors.append(
				(
					"Hinge '%s' target '%s' must be a "
					+ "toggle_platform; got '%s'."
				)
				% [object_id, target_id, target["type"]]
			)


static func _validate_actor_placements(
	objects: Array[Dictionary],
	errors: Array[String]
) -> void:
	var solids: Array[Dictionary] = []
	for object: Dictionary in objects:
		if (
			object["type"] == "solid_rect"
			or (
				object["type"] == "toggle_platform"
				and bool(object["starts_active"])
			)
		):
			solids.append(object)

	for object: Dictionary in objects:
		var object_type: String = object["type"]
		if not ACTOR_HALF_EXTENTS.has(object_type):
			continue

		var position_values: Array = object["position"]
		var origin := Vector2(
			float(position_values[0]),
			float(position_values[1])
		)
		var half_extents := Vector2(
			ACTOR_HALF_EXTENTS[object_type]
		)
		var actor_rect := Rect2(
			origin - half_extents,
			half_extents * 2.0
		)
		if (
			actor_rect.position.x < PLAYFIELD_LEFT
			or actor_rect.position.y < PLAYFIELD_TOP
			or actor_rect.end.x > PLAYFIELD_RIGHT
			or actor_rect.end.y > PLAYFIELD_BOTTOM
		):
			errors.append(
				(
					"Object '%s' collision bounds must fit inside "
					+ "the runtime playfield."
				)
				% object["id"]
			)

		for solid: Dictionary in solids:
			var rect_values: Array = solid["rect"]
			var rect := Rect2(
				float(rect_values[0]),
				float(rect_values[1]),
				float(rect_values[2]),
				float(rect_values[3])
			)
			if _rects_overlap_strictly(actor_rect, rect):
				errors.append(
					(
						"Object '%s' collision bounds overlap "
						+ "%s '%s'."
					)
					% [object["id"], solid["type"], solid["id"]]
				)


static func _rects_overlap_strictly(first: Rect2, second: Rect2) -> bool:
	return (
		first.position.x < second.end.x
		and first.end.x > second.position.x
		and first.position.y < second.end.y
		and first.end.y > second.position.y
	)


static func _collect_warnings(
	objects: Array[Dictionary]
) -> Array[String]:
	var warnings: Array[String] = []
	var solids: Array[Rect2] = []
	var targeted_platforms := {}
	for object: Dictionary in objects:
		if object["type"] == "hinge":
			targeted_platforms[object["target_id"]] = true
			continue
		if (
			object["type"] != "solid_rect"
			and not (
				object["type"] == "toggle_platform"
				and bool(object["starts_active"])
			)
		):
			continue
		var values: Array = object["rect"]
		solids.append(
			Rect2(
				float(values[0]),
				float(values[1]),
				float(values[2]),
				float(values[3])
			)
		)

	for object: Dictionary in objects:
		var object_type: String = object["type"]
		if not ACTOR_HALF_EXTENTS.has(object_type):
			continue

		var values: Array = object["position"]
		var origin := Vector2(float(values[0]), float(values[1]))
		var half_extents := Vector2(ACTOR_HALF_EXTENTS[object_type])
		var actor_left := origin.x - half_extents.x
		var actor_right := origin.x + half_extents.x
		var actor_bottom := origin.y + half_extents.y
		var has_nearby_support := false
		var shove_runway := 0.0
		for solid: Rect2 in solids:
			if (
				solid.position.y >= actor_bottom
				and solid.position.y
				<= actor_bottom + MAX_SUPPORT_WARNING_GAP
				and solid.position.x < actor_right
				and solid.end.x > actor_left
			):
				has_nearby_support = true
				if object_type == "shove_enemy":
					var direction := float(object["direction"])
					var available := (
						solid.end.x - actor_right
						if direction > 0.0
						else actor_left - solid.position.x
					)
					shove_runway = maxf(shove_runway, available)

		if not has_nearby_support:
			warnings.append(
				"Object '%s' has no solid support near its spawn."
				% object["id"]
			)
		elif (
			object_type == "shove_enemy"
			and shove_runway < MIN_SHOVE_RUNWAY
		):
			warnings.append(
				(
					"Shove enemy '%s' has less than %d px of floor "
					+ "in its initial direction."
				)
				% [object["id"], int(MIN_SHOVE_RUNWAY)]
			)

		if (
			object_type == "patrol_enemy"
			and is_zero_approx(float(object["speed"]))
		):
			warnings.append(
				"Patrol '%s' has zero speed." % object["id"]
			)

	for object: Dictionary in objects:
		if (
			object["type"] == "toggle_platform"
			and not targeted_platforms.has(object["id"])
		):
			warnings.append(
				"Toggle platform '%s' has no controlling hinge."
				% object["id"]
			)

	return warnings


static func _read_boolean(
	raw: Variant,
	path: String,
	errors: Array[String]
) -> Variant:
	if typeof(raw) != TYPE_BOOL:
		errors.append("%s must be a boolean." % path)
		return null
	return bool(raw)


static func _read_int_array(
	raw: Variant,
	path: String,
	expected_size: int,
	errors: Array[String]
) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s must be an array of %d integers." % [path, expected_size])
		return null

	var values: Array = raw
	if values.size() != expected_size:
		errors.append(
			"%s must contain exactly %d integers." % [path, expected_size]
		)
		return null

	var normalized: Array[int] = []
	for index in expected_size:
		var value: Variant = _read_integer(
			values[index],
			"%s[%d]" % [path, index],
			errors
		)
		if value == null:
			return null
		normalized.append(value)

	return normalized


static func _read_integer(
	raw: Variant,
	path: String,
	errors: Array[String],
	minimum: Variant = null,
	maximum: Variant = null
) -> Variant:
	var raw_type := typeof(raw)
	if raw_type != TYPE_INT and raw_type != TYPE_FLOAT:
		errors.append("%s must be an integer." % path)
		return null

	var value: int
	if raw_type == TYPE_INT:
		value = int(raw)
	else:
		var number := float(raw)
		if (
			not is_finite(number)
			or number != floorf(number)
			or absf(number) > MAX_SAFE_FLOAT_INTEGER
		):
			errors.append("%s must be a finite, exactly representable integer." % path)
			return null
		value = int(number)
	if minimum != null and value < int(minimum):
		errors.append("%s must be at least %d." % [path, minimum])
		return null
	if maximum != null and value > int(maximum):
		errors.append("%s must be at most %d." % [path, maximum])
		return null

	return value


static func _read_finite_number(
	raw: Variant,
	path: String,
	errors: Array[String],
	minimum: float,
	maximum: float
) -> Variant:
	var raw_type := typeof(raw)
	if raw_type != TYPE_INT and raw_type != TYPE_FLOAT:
		errors.append("%s must be a number." % path)
		return null

	var value := float(raw)
	if not is_finite(value):
		errors.append("%s must be finite." % path)
		return null
	if value < minimum or value > maximum:
		errors.append(
			"%s must be between %s and %s."
			% [path, minimum, maximum]
		)
		return null

	return value


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
			"%s must contain 1 to %d characters." % [path, maximum_length]
		)
		return ""
	if not _is_stable_id(value):
		errors.append(
			"%s must match [a-z][a-z0-9_]*." % path
		)
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
	for key in value.keys():
		if typeof(key) != TYPE_STRING:
			unknown_keys.append(str(key))
		elif not allowed_keys.has(key):
			unknown_keys.append(String(key))

	unknown_keys.sort()
	for key in unknown_keys:
		errors.append("%s has unknown key '%s'." % [path, key])


static func _failure(errors: Array[String]) -> Dictionary:
	return {
		"ok": false,
		"data": {},
		"errors": errors,
		"warnings": [] as Array[String],
	}

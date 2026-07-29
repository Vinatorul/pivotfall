class_name LevelEditorCanvas
extends Control

signal selection_requested(object_id: String)
signal placement_requested(object_type: String, payload: Variant)
signal move_requested(object_id: String, payload: Variant)
signal nudge_requested(direction: Vector2i, fine: bool)
signal link_target_requested(target_id: String)
signal link_cancel_requested

const LOGICAL_SIZE := Vector2(960.0, 540.0)
const DEFAULT_GRID_SIZE := 20
const DEFAULT_SOLID_SIZE := Vector2i(120, 20)
const DEFAULT_TOGGLE_SIZE := Vector2i(160, 20)
const MIN_TOGGLE_WIDTH := 20
const PIT_TOP := 496.0
const FIXED_BORDER_SIZE := 32.0
const DRAG_THRESHOLD := 4.0
const TOP_EDGE_HEIGHT := 6.0
const HINGE_HALF_EXTENTS := Vector2(18.0, 18.0)

const TOOL_SELECT := "select"
const TOOL_SOLID_RECT := "solid_rect"
const TOOL_PLAYER_SPAWN := "player_spawn"
const TOOL_PATROL_ENEMY := "patrol_enemy"
const TOOL_TOGGLE_PLATFORM := "toggle_platform"
const TOOL_HINGE := "hinge"
const SUPPORTED_TOOLS := [
	TOOL_SELECT,
	TOOL_SOLID_RECT,
	TOOL_PLAYER_SPAWN,
	TOOL_PATROL_ENEMY,
	TOOL_TOGGLE_PLATFORM,
	TOOL_HINGE,
]
const RECT_OBJECT_TYPES := [
	TOOL_SOLID_RECT,
	TOOL_TOGGLE_PLATFORM,
]

const ACTOR_HALF_EXTENTS := {
	TOOL_PLAYER_SPAWN: Vector2(14.0, 20.0),
	TOOL_PATROL_ENEMY: Vector2(15.0, 18.0),
}

const COLOR_OUTSIDE := Color(0.035, 0.047, 0.082, 1.0)
const COLOR_BACKGROUND := Color(0.055, 0.071, 0.125, 1.0)
const COLOR_BACKDROP := Color(0.075, 0.098, 0.165, 1.0)
const COLOR_PIT := Color(0.02, 0.024, 0.043, 1.0)
const COLOR_GRID := Color(0.392, 0.455, 0.584, 0.13)
const COLOR_GRID_MAJOR := Color(0.392, 0.455, 0.584, 0.25)
const COLOR_FIXED_GEOMETRY := Color(0.157, 0.2, 0.286, 1.0)
const COLOR_SOLID := Color(0.235, 0.302, 0.416, 1.0)
const COLOR_SOLID_EDGE := Color(0.392, 0.455, 0.584, 1.0)
const COLOR_PLAYER := Color(0.251, 0.878, 0.816, 1.0)
const COLOR_PLAYER_FACE := Color(0.071, 0.204, 0.251, 1.0)
const COLOR_PATROL := Color(0.973, 0.58, 0.267, 1.0)
const COLOR_PATROL_FACE := Color(0.302, 0.125, 0.098, 1.0)
const COLOR_TOGGLE_ACTIVE := Color(0.278, 0.345, 0.459, 1.0)
const COLOR_TOGGLE_INACTIVE := Color(0.278, 0.345, 0.459, 0.2)
const COLOR_TOGGLE_EDGE := Color(0.439, 0.827, 0.816, 0.9)
const COLOR_HINGE_OUTER := Color(0.925, 0.58, 0.267, 1.0)
const COLOR_HINGE_INNER := Color(0.302, 0.125, 0.098, 1.0)
const COLOR_LINK := Color(0.439, 0.827, 0.816, 0.38)
const COLOR_LINK_SELECTED := Color(0.439, 0.878, 0.816, 0.95)
const COLOR_LINK_BROKEN := Color(0.925, 0.365, 0.231, 0.95)
const COLOR_SELECTION := Color(0.439, 0.827, 0.816, 1.0)
const COLOR_GHOST := Color(1.0, 0.82, 0.36, 0.44)
const COLOR_GHOST_OUTLINE := Color(1.0, 0.82, 0.36, 1.0)
const COLOR_CANVAS_BORDER := Color(0.439, 0.502, 0.616, 0.9)

var _document: Dictionary = {}
var _selected_id := ""
var _tool := TOOL_SELECT
var _link_source_id := ""
var _link_cursor_logical := Vector2.ZERO
var _link_hover_id := ""

var _drag_active := false
var _drag_moved := false
var _drag_kind := ""
var _drag_object_id := ""
var _drag_object_type := ""
var _drag_press_local := Vector2.ZERO
var _drag_start_logical := Vector2.ZERO
var _drag_current_logical := Vector2.ZERO
var _drag_original_payload: Variant = null
var _drag_preview_payload: Variant = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_document(data: Dictionary) -> void:
	_document = data.duplicate(true)
	_cancel_drag()
	queue_redraw()


func set_selected_id(object_id: String) -> void:
	_selected_id = object_id
	_cancel_drag()
	queue_redraw()


func set_tool(tool: String) -> void:
	if not SUPPORTED_TOOLS.has(tool):
		push_warning("Unsupported level editor canvas tool: %s." % tool)
		return

	_tool = tool
	_cancel_drag()
	mouse_default_cursor_shape = (
		Control.CURSOR_ARROW
		if _tool == TOOL_SELECT
		else Control.CURSOR_CROSS
	)
	queue_redraw()


func set_link_source(object_id: String) -> void:
	_link_source_id = object_id
	_link_hover_id = ""
	var source := _find_object(object_id)
	if not source.is_empty():
		_link_cursor_logical = _object_anchor(source)
	_cancel_drag()
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if not _link_source_id.is_empty()
		else (
			Control.CURSOR_ARROW
			if _tool == TOOL_SELECT
			else Control.CURSOR_CROSS
		)
	)
	queue_redraw()


func get_link_source_id() -> String:
	return _link_source_id


func _on_mouse_exited() -> void:
	if _link_hover_id.is_empty():
		return
	_link_hover_id = ""
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_OUTSIDE)

	var view_rect := _canvas_view_rect()
	if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
		return

	draw_rect(view_rect, COLOR_BACKGROUND)
	_draw_backdrop(view_rect)
	_draw_grid(view_rect)
	_draw_fixed_geometry(view_rect)
	_draw_links(view_rect)

	for object_type: String in [
		TOOL_SOLID_RECT,
		TOOL_TOGGLE_PLATFORM,
		TOOL_PLAYER_SPAWN,
		TOOL_PATROL_ENEMY,
		TOOL_HINGE,
	]:
		for object: Variant in _objects():
			if (
				typeof(object) == TYPE_DICTIONARY
				and object.get("type", "") == object_type
			):
				_draw_object(object, view_rect, 1.0)

	_draw_selection(view_rect)
	_draw_link_target_hover(view_rect)
	_draw_drag_preview(view_rect)
	draw_rect(view_rect, COLOR_CANVAS_BORDER, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if (
			_event_key(key_event) == KEY_ESCAPE
			and not _link_source_id.is_empty()
		):
			link_cancel_requested.emit()
			accept_event()
			return
		var direction := Vector2i.ZERO
		match _event_key(key_event):
			KEY_LEFT:
				direction = Vector2i.LEFT
			KEY_RIGHT:
				direction = Vector2i.RIGHT
			KEY_UP:
				direction = Vector2i.UP
			KEY_DOWN:
				direction = Vector2i.DOWN
		if direction != Vector2i.ZERO:
			nudge_requested.emit(direction, key_event.shift_pressed)
			accept_event()
		return

	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index != MOUSE_BUTTON_LEFT:
			return

		if button_event.pressed:
			if not _canvas_view_rect().has_point(button_event.position):
				return
			if is_inside_tree():
				grab_focus()
			if not _link_source_id.is_empty():
				var logical_position := _local_to_logical(
					button_event.position,
					true
				)
				var target := _hit_test_type(
					logical_position,
					TOOL_TOGGLE_PLATFORM
				)
				link_target_requested.emit(
					str(target.get("id", ""))
				)
				accept_event()
				return
			_begin_primary_action(button_event.position)
			accept_event()
			return

		if _drag_active:
			_finish_primary_action(button_event.position)
			accept_event()
		return

	if event is InputEventMouseMotion and not _link_source_id.is_empty():
		var link_motion := event as InputEventMouseMotion
		_link_cursor_logical = _local_to_logical(
			link_motion.position,
			true
		)
		var target := _hit_test_type(
			_link_cursor_logical,
			TOOL_TOGGLE_PLATFORM
		)
		_link_hover_id = str(target.get("id", ""))
		queue_redraw()
		accept_event()
		return

	if event is InputEventMouseMotion and _drag_active:
		var motion_event := event as InputEventMouseMotion
		_update_drag(motion_event.position)
		accept_event()


func _begin_primary_action(local_position: Vector2) -> void:
	var logical_position := _local_to_logical(local_position, true)

	match _tool:
		TOOL_SELECT:
			var hit_object := _hit_test(logical_position)
			if hit_object.is_empty():
				selection_requested.emit("")
				return

			var object_id := str(hit_object.get("id", ""))
			selection_requested.emit(object_id)
			_begin_move_drag(hit_object, local_position, logical_position)

		TOOL_SOLID_RECT, TOOL_TOGGLE_PLATFORM:
			_drag_active = true
			_drag_kind = _tool
			_drag_press_local = local_position
			_drag_start_logical = _snap_logical_point(
				logical_position,
				false
			)
			_drag_current_logical = _drag_start_logical
			_drag_preview_payload = _default_rect(
				_drag_start_logical,
				_tool
			)
			queue_redraw()

		TOOL_PLAYER_SPAWN, TOOL_PATROL_ENEMY, TOOL_HINGE:
			var snapped_position := _snap_logical_point(
				logical_position,
				false
			)
			placement_requested.emit(
				_tool,
				_point_payload(snapped_position)
			)


func _begin_move_drag(
	object: Dictionary,
	local_position: Vector2,
	logical_position: Vector2
) -> void:
	var object_type := str(object.get("type", ""))
	var payload: Variant = _payload_for_object(object)
	if payload == null:
		return

	_drag_active = true
	_drag_kind = TOOL_SELECT
	_drag_object_id = str(object.get("id", ""))
	_drag_object_type = object_type
	_drag_press_local = local_position
	_drag_start_logical = logical_position
	_drag_current_logical = logical_position
	_drag_original_payload = payload
	_drag_preview_payload = _duplicate_payload(payload)
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	queue_redraw()


func _update_drag(local_position: Vector2) -> void:
	var view_rect := _canvas_view_rect()
	var clamped_local := local_position.clamp(
		view_rect.position,
		view_rect.end
	)
	_drag_current_logical = _local_to_logical(clamped_local, true)
	_drag_moved = (
		_drag_moved
		or local_position.distance_to(_drag_press_local) >= DRAG_THRESHOLD
	)

	if _drag_kind == TOOL_SOLID_RECT:
		var snapped_current := _snap_logical_point(
			_drag_current_logical,
			true
		)
		_drag_preview_payload = _solid_rect_from_drag(
			_drag_start_logical,
			snapped_current
		)
	elif _drag_kind == TOOL_TOGGLE_PLATFORM:
		var snapped_current := _snap_logical_point(
			_drag_current_logical,
			true
		)
		_drag_preview_payload = _toggle_rect_from_drag(
			_drag_start_logical,
			snapped_current
		)
	elif _drag_kind == TOOL_SELECT and _drag_moved:
		_drag_preview_payload = _moved_payload()

	queue_redraw()


func _finish_primary_action(local_position: Vector2) -> void:
	_update_drag(local_position)

	if RECT_OBJECT_TYPES.has(_drag_kind):
		var payload: Variant = _drag_preview_payload
		if not _drag_moved:
			payload = _default_rect(
				_drag_start_logical,
				_drag_kind
			)
		placement_requested.emit(_drag_kind, payload)
	elif (
		_drag_kind == TOOL_SELECT
		and _drag_moved
		and not _drag_object_id.is_empty()
	):
		move_requested.emit(
			_drag_object_id,
			_duplicate_payload(_drag_preview_payload)
		)

	_cancel_drag()
	queue_redraw()


func _cancel_drag() -> void:
	_drag_active = false
	_drag_moved = false
	_drag_kind = ""
	_drag_object_id = ""
	_drag_object_type = ""
	_drag_press_local = Vector2.ZERO
	_drag_start_logical = Vector2.ZERO
	_drag_current_logical = Vector2.ZERO
	_drag_original_payload = null
	_drag_preview_payload = null
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if not _link_source_id.is_empty()
		else (
			Control.CURSOR_ARROW
			if _tool == TOOL_SELECT
			else Control.CURSOR_CROSS
		)
	)


func _moved_payload() -> Variant:
	var raw_delta := _drag_current_logical - _drag_start_logical
	var snapped_delta := _snap_delta(raw_delta)

	if RECT_OBJECT_TYPES.has(_drag_object_type):
		if not _is_number_array(_drag_original_payload, 4):
			return null

		var original: Array = _drag_original_payload
		var width := float(original[2])
		var height := float(original[3])
		var position := Vector2(
			float(original[0]),
			float(original[1])
		) + snapped_delta
		position.x = clampf(position.x, 0.0, LOGICAL_SIZE.x - width)
		position.y = clampf(position.y, 0.0, LOGICAL_SIZE.y - height)
		return [
			_round_to_int(position.x),
			_round_to_int(position.y),
			_round_to_int(width),
			_round_to_int(height),
		]

	if (
		ACTOR_HALF_EXTENTS.has(_drag_object_type)
		or _drag_object_type == TOOL_HINGE
	):
		if not _is_number_array(_drag_original_payload, 2):
			return null

		var original: Array = _drag_original_payload
		var position := Vector2(
			float(original[0]),
			float(original[1])
		) + snapped_delta
		position.x = clampf(position.x, 0.0, LOGICAL_SIZE.x - 1.0)
		position.y = clampf(position.y, 0.0, LOGICAL_SIZE.y - 1.0)
		return _point_payload(position)

	return null


func _draw_backdrop(view_rect: Rect2) -> void:
	draw_rect(
		_logical_rect_to_local(
			Rect2(
				FIXED_BORDER_SIZE,
				FIXED_BORDER_SIZE,
				LOGICAL_SIZE.x - FIXED_BORDER_SIZE * 2.0,
				PIT_TOP - FIXED_BORDER_SIZE
			),
			view_rect
		),
		COLOR_BACKDROP
	)
	draw_rect(
		_logical_rect_to_local(
			Rect2(
				FIXED_BORDER_SIZE,
				PIT_TOP,
				LOGICAL_SIZE.x - FIXED_BORDER_SIZE * 2.0,
				LOGICAL_SIZE.y - PIT_TOP
			),
			view_rect
		),
		COLOR_PIT
	)


func _draw_grid(view_rect: Rect2) -> void:
	var grid_size := _grid_size()
	var canvas_scale := _canvas_scale()
	if grid_size <= 0 or canvas_scale <= 0.0:
		return

	var major_step := grid_size * 5
	var x := 0
	while x <= int(LOGICAL_SIZE.x):
		var color := (
			COLOR_GRID_MAJOR
			if x % major_step == 0
			else COLOR_GRID
		)
		var local_x := view_rect.position.x + float(x) * canvas_scale
		draw_line(
			Vector2(local_x, view_rect.position.y),
			Vector2(local_x, view_rect.end.y),
			color,
			1.0
		)
		x += grid_size

	var y := 0
	while y <= int(LOGICAL_SIZE.y):
		var color := (
			COLOR_GRID_MAJOR
			if y % major_step == 0
			else COLOR_GRID
		)
		var local_y := view_rect.position.y + float(y) * canvas_scale
		draw_line(
			Vector2(view_rect.position.x, local_y),
			Vector2(view_rect.end.x, local_y),
			color,
			1.0
		)
		y += grid_size


func _draw_fixed_geometry(view_rect: Rect2) -> void:
	var fixed_rects := [
		Rect2(0.0, 0.0, LOGICAL_SIZE.x, FIXED_BORDER_SIZE),
		Rect2(0.0, 0.0, FIXED_BORDER_SIZE, LOGICAL_SIZE.y),
		Rect2(
			LOGICAL_SIZE.x - FIXED_BORDER_SIZE,
			0.0,
			FIXED_BORDER_SIZE,
			LOGICAL_SIZE.y
		),
	]
	for rect: Rect2 in fixed_rects:
		draw_rect(
			_logical_rect_to_local(rect, view_rect),
			COLOR_FIXED_GEOMETRY
		)


func _draw_links(view_rect: Rect2) -> void:
	for object: Variant in _objects():
		if (
			typeof(object) != TYPE_DICTIONARY
			or object.get("type", "") != TOOL_HINGE
		):
			continue

		var source := object as Dictionary
		var source_position := _object_anchor(source)
		var target := _find_object(str(source.get("target_id", "")))
		var selected := str(source.get("id", "")) == _selected_id
		if (
			not target.is_empty()
			and target.get("type", "") == TOOL_TOGGLE_PLATFORM
		):
			var target_position := _object_anchor(target)
			var color := (
				COLOR_LINK_SELECTED if selected else COLOR_LINK
			)
			_draw_logical_link(
				source_position,
				target_position,
				color,
				3.0 if selected else 2.0,
				view_rect
			)
			continue

		var stub_direction := (
			Vector2.LEFT
			if source_position.x > LOGICAL_SIZE.x - 64.0
			else Vector2.RIGHT
		)
		var stub_end := source_position + stub_direction * 36.0
		_draw_logical_link(
			source_position,
			stub_end,
			COLOR_LINK_BROKEN,
			2.0,
			view_rect
		)
		var local_end := _logical_point_to_local(stub_end, view_rect)
		var cross_size := 5.0
		draw_line(
			local_end - Vector2(cross_size, cross_size),
			local_end + Vector2(cross_size, cross_size),
			COLOR_LINK_BROKEN,
			2.0
		)
		draw_line(
			local_end + Vector2(-cross_size, cross_size),
			local_end + Vector2(cross_size, -cross_size),
			COLOR_LINK_BROKEN,
			2.0
		)

	if _link_source_id.is_empty():
		return
	var link_source := _find_object(_link_source_id)
	if link_source.is_empty():
		return
	_draw_logical_link(
		_object_anchor(link_source),
		_link_cursor_logical,
		COLOR_LINK_SELECTED,
		3.0,
		view_rect
	)


func _draw_logical_link(
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float,
	view_rect: Rect2
) -> void:
	var local_from := _logical_point_to_local(from, view_rect)
	var local_to := _logical_point_to_local(to, view_rect)
	draw_line(local_from, local_to, color, width, true)
	draw_circle(local_to, 4.0, color)


func _draw_link_target_hover(view_rect: Rect2) -> void:
	if _link_hover_id.is_empty():
		return
	var target := _find_object(_link_hover_id)
	if target.is_empty():
		return
	var bounds := _bounds_for_object(target)
	if bounds.size == Vector2.ZERO:
		return
	draw_rect(
		_logical_rect_to_local(bounds, view_rect).grow(3.0),
		COLOR_LINK_SELECTED,
		false,
		3.0
	)


func _draw_object(
	object: Dictionary,
	view_rect: Rect2,
	alpha: float
) -> void:
	var object_type := str(object.get("type", ""))
	match object_type:
		TOOL_SOLID_RECT:
			var rect_values: Variant = object.get("rect")
			if not _is_number_array(rect_values, 4):
				return
			_draw_solid(rect_values, view_rect, alpha)

		TOOL_TOGGLE_PLATFORM:
			var rect_values: Variant = object.get("rect")
			if not _is_number_array(rect_values, 4):
				return
			_draw_toggle_platform(
				rect_values,
				bool(object.get("starts_active", true)),
				view_rect,
				alpha
			)

		TOOL_PLAYER_SPAWN, TOOL_PATROL_ENEMY:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			_draw_actor(
				object_type,
				position_values,
				view_rect,
				alpha,
				int(object.get("direction", 1))
			)

		TOOL_HINGE:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			_draw_hinge(position_values, view_rect, alpha)


func _draw_solid(
	rect_values: Array,
	view_rect: Rect2,
	alpha: float
) -> void:
	var logical_rect := _rect_from_payload(rect_values)
	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	draw_rect(local_rect, _with_alpha(COLOR_SOLID, alpha))

	var edge_height := minf(TOP_EDGE_HEIGHT, logical_rect.size.y)
	var logical_edge := Rect2(
		logical_rect.position,
		Vector2(logical_rect.size.x, edge_height)
	)
	draw_rect(
		_logical_rect_to_local(logical_edge, view_rect),
		_with_alpha(COLOR_SOLID_EDGE, alpha)
	)


func _draw_toggle_platform(
	rect_values: Array,
	starts_active: bool,
	view_rect: Rect2,
	alpha: float
) -> void:
	var logical_rect := _rect_from_payload(rect_values)
	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	var body_color := (
		COLOR_TOGGLE_ACTIVE
		if starts_active
		else COLOR_TOGGLE_INACTIVE
	)
	draw_rect(local_rect, _with_alpha(body_color, alpha))
	draw_rect(
		local_rect,
		_with_alpha(COLOR_TOGGLE_EDGE, alpha),
		false,
		2.0
	)
	var local_center := local_rect.get_center()
	var notch_half := minf(7.0, local_rect.size.y * 0.3)
	draw_line(
		local_center - Vector2(notch_half, 0.0),
		local_center + Vector2(notch_half, 0.0),
		_with_alpha(COLOR_TOGGLE_EDGE, alpha),
		2.0
	)
	if not starts_active:
		draw_line(
			local_center - Vector2(0.0, notch_half),
			local_center + Vector2(0.0, notch_half),
			_with_alpha(COLOR_TOGGLE_EDGE, alpha),
			2.0
		)


func _draw_hinge(
	position_values: Array,
	view_rect: Rect2,
	alpha: float
) -> void:
	var position := Vector2(
		float(position_values[0]),
		float(position_values[1])
	)
	var local_center := _logical_point_to_local(position, view_rect)
	var radius := HINGE_HALF_EXTENTS.x * _canvas_scale()
	var outer_points := PackedVector2Array(
		[
			local_center + Vector2(0.0, -radius),
			local_center + Vector2(radius, 0.0),
			local_center + Vector2(0.0, radius),
			local_center + Vector2(-radius, 0.0),
		]
	)
	draw_colored_polygon(
		outer_points,
		_with_alpha(COLOR_HINGE_OUTER, alpha)
	)
	var inner_radius := radius * 0.5
	var inner_points := PackedVector2Array(
		[
			local_center + Vector2(0.0, -inner_radius),
			local_center + Vector2(inner_radius, 0.0),
			local_center + Vector2(0.0, inner_radius),
			local_center + Vector2(-inner_radius, 0.0),
		]
	)
	draw_colored_polygon(
		inner_points,
		_with_alpha(COLOR_HINGE_INNER, alpha)
	)


func _draw_actor(
	object_type: String,
	position_values: Array,
	view_rect: Rect2,
	alpha: float,
	direction: int = 1
) -> void:
	var half_extents: Vector2 = ACTOR_HALF_EXTENTS[object_type]
	var position := Vector2(
		float(position_values[0]),
		float(position_values[1])
	)
	var logical_rect := Rect2(
		position - half_extents,
		half_extents * 2.0
	)
	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	var body_color := (
		COLOR_PLAYER
		if object_type == TOOL_PLAYER_SPAWN
		else COLOR_PATROL
	)
	var face_color := (
		COLOR_PLAYER_FACE
		if object_type == TOOL_PLAYER_SPAWN
		else COLOR_PATROL_FACE
	)
	draw_rect(local_rect, _with_alpha(body_color, alpha))

	var face_offset := (
		0.0
		if object_type == TOOL_PATROL_ENEMY and direction < 0
		else 0.58
	)
	var face_rect := Rect2(
		Vector2(
			local_rect.position.x + local_rect.size.x * face_offset,
			local_rect.position.y + local_rect.size.y * 0.25
		),
		Vector2(
			local_rect.size.x * 0.42,
			local_rect.size.y * 0.45
		)
	)
	draw_rect(face_rect, _with_alpha(face_color, alpha))


func _draw_selection(view_rect: Rect2) -> void:
	if _selected_id.is_empty():
		return

	var object := _find_object(_selected_id)
	if object.is_empty():
		return

	var logical_rect := _bounds_for_object(object)
	if logical_rect.size == Vector2.ZERO:
		return

	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	draw_rect(local_rect.grow(2.0), COLOR_SELECTION, false, 2.0)

	var handle_size := Vector2(5.0, 5.0)
	for corner: Vector2 in [
		local_rect.position,
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y),
	]:
		draw_rect(
			Rect2(corner - handle_size * 0.5, handle_size),
			COLOR_SELECTION
		)


func _draw_drag_preview(view_rect: Rect2) -> void:
	if not _drag_active or _drag_preview_payload == null:
		return

	var logical_rect := Rect2()
	if (
		RECT_OBJECT_TYPES.has(_drag_kind)
		and _is_number_array(_drag_preview_payload, 4)
	):
		logical_rect = _rect_from_payload(_drag_preview_payload)
		if _drag_kind == TOOL_TOGGLE_PLATFORM:
			_draw_toggle_platform(
				_drag_preview_payload,
				true,
				view_rect,
				COLOR_GHOST.a
			)
		else:
			_draw_solid(
				_drag_preview_payload,
				view_rect,
				COLOR_GHOST.a
			)
	elif (
		_drag_kind == TOOL_SELECT
		and _drag_moved
		and _is_number_array(_drag_preview_payload, 2)
		and (
			ACTOR_HALF_EXTENTS.has(_drag_object_type)
			or _drag_object_type == TOOL_HINGE
		)
	):
		var position_values: Array = _drag_preview_payload
		var position := Vector2(
			float(position_values[0]),
			float(position_values[1])
		)
		var half_extents := (
			HINGE_HALF_EXTENTS
			if _drag_object_type == TOOL_HINGE
			else Vector2(ACTOR_HALF_EXTENTS[_drag_object_type])
		)
		logical_rect = Rect2(
			position - half_extents,
			half_extents * 2.0
		)
		if _drag_object_type == TOOL_HINGE:
			_draw_hinge(
				position_values,
				view_rect,
				COLOR_GHOST.a
			)
		else:
			_draw_actor(
				_drag_object_type,
				position_values,
				view_rect,
				COLOR_GHOST.a,
				int(
					_find_object(_drag_object_id).get(
						"direction",
						1
					)
				)
			)
	elif (
		_drag_kind == TOOL_SELECT
		and _drag_moved
		and _is_number_array(_drag_preview_payload, 4)
	):
		logical_rect = _rect_from_payload(_drag_preview_payload)
		if _drag_object_type == TOOL_TOGGLE_PLATFORM:
			_draw_toggle_platform(
				_drag_preview_payload,
				bool(
					_find_object(_drag_object_id).get(
						"starts_active",
						true
					)
				),
				view_rect,
				COLOR_GHOST.a
			)
		else:
			_draw_solid(
				_drag_preview_payload,
				view_rect,
				COLOR_GHOST.a
			)

	if logical_rect.size != Vector2.ZERO:
		draw_rect(
			_logical_rect_to_local(logical_rect, view_rect).grow(1.0),
			COLOR_GHOST_OUTLINE,
			false,
			2.0
		)


func _hit_test(logical_position: Vector2) -> Dictionary:
	var objects := _objects()
	for object_type: String in [
		TOOL_HINGE,
		TOOL_PATROL_ENEMY,
		TOOL_PLAYER_SPAWN,
		TOOL_TOGGLE_PLATFORM,
		TOOL_SOLID_RECT,
	]:
		for index in range(objects.size() - 1, -1, -1):
			var object: Variant = objects[index]
			if (
				typeof(object) != TYPE_DICTIONARY
				or object.get("type", "") != object_type
			):
				continue

			var bounds := _bounds_for_object(object)
			if (
				bounds.size != Vector2.ZERO
				and bounds.grow(4.0).has_point(logical_position)
			):
				return object

	return {}


func _hit_test_type(
	logical_position: Vector2,
	object_type: String
) -> Dictionary:
	var objects := _objects()
	for index in range(objects.size() - 1, -1, -1):
		var object: Variant = objects[index]
		if (
			typeof(object) != TYPE_DICTIONARY
			or object.get("type", "") != object_type
		):
			continue
		var bounds := _bounds_for_object(object)
		if (
			bounds.size != Vector2.ZERO
			and bounds.grow(4.0).has_point(logical_position)
		):
			return object
	return {}


func _bounds_for_object(object: Dictionary) -> Rect2:
	var object_type := str(object.get("type", ""))
	if RECT_OBJECT_TYPES.has(object_type):
		var rect_values: Variant = object.get("rect")
		if _is_number_array(rect_values, 4):
			return _rect_from_payload(rect_values)
		return Rect2()

	if ACTOR_HALF_EXTENTS.has(object_type):
		var position_values: Variant = object.get("position")
		if not _is_number_array(position_values, 2):
			return Rect2()

		var position := Vector2(
			float(position_values[0]),
			float(position_values[1])
		)
		var half_extents: Vector2 = ACTOR_HALF_EXTENTS[object_type]
		return Rect2(position - half_extents, half_extents * 2.0)

	if object_type == TOOL_HINGE:
		var position_values: Variant = object.get("position")
		if not _is_number_array(position_values, 2):
			return Rect2()
		var position := Vector2(
			float(position_values[0]),
			float(position_values[1])
		)
		return Rect2(
			position - HINGE_HALF_EXTENTS,
			HINGE_HALF_EXTENTS * 2.0
		)

	return Rect2()


func _find_object(object_id: String) -> Dictionary:
	for object: Variant in _objects():
		if (
			typeof(object) == TYPE_DICTIONARY
			and str(object.get("id", "")) == object_id
		):
			return object
	return {}


func _payload_for_object(object: Dictionary) -> Variant:
	match str(object.get("type", "")):
		TOOL_SOLID_RECT, TOOL_TOGGLE_PLATFORM:
			var rect_values: Variant = object.get("rect")
			if _is_number_array(rect_values, 4):
				return _duplicate_payload(rect_values)
		TOOL_PLAYER_SPAWN, TOOL_PATROL_ENEMY, TOOL_HINGE:
			var position_values: Variant = object.get("position")
			if _is_number_array(position_values, 2):
				return _duplicate_payload(position_values)
	return null


func _solid_rect_from_drag(
	start: Vector2,
	current: Vector2
) -> Array:
	var grid_size := float(_grid_size())
	var end := current
	if is_equal_approx(end.x, start.x):
		end.x += grid_size
	if is_equal_approx(end.y, start.y):
		end.y += grid_size

	end.x = clampf(end.x, 0.0, LOGICAL_SIZE.x)
	end.y = clampf(end.y, 0.0, LOGICAL_SIZE.y)

	var left := minf(start.x, end.x)
	var top := minf(start.y, end.y)
	var right := maxf(start.x, end.x)
	var bottom := maxf(start.y, end.y)

	if right - left < grid_size:
		if left + grid_size <= LOGICAL_SIZE.x:
			right = left + grid_size
		else:
			left = maxf(0.0, right - grid_size)
	if bottom - top < grid_size:
		if top + grid_size <= LOGICAL_SIZE.y:
			bottom = top + grid_size
		else:
			top = maxf(0.0, bottom - grid_size)

	return [
		_round_to_int(left),
		_round_to_int(top),
		_round_to_int(right - left),
		_round_to_int(bottom - top),
	]


func _toggle_rect_from_drag(
	start: Vector2,
	current: Vector2
) -> Array:
	var grid_size := float(_grid_size())
	var minimum_width := maxf(
		grid_size,
		float(MIN_TOGGLE_WIDTH)
	)
	var end_x := current.x
	if is_equal_approx(end_x, start.x):
		end_x += grid_size
	end_x = clampf(end_x, 0.0, LOGICAL_SIZE.x)

	var left := minf(start.x, end_x)
	var right := maxf(start.x, end_x)
	if right - left < minimum_width:
		if left + minimum_width <= LOGICAL_SIZE.x:
			right = left + minimum_width
		else:
			left = maxf(0.0, right - minimum_width)

	var top := clampf(
		start.y,
		0.0,
		LOGICAL_SIZE.y - float(DEFAULT_TOGGLE_SIZE.y)
	)
	return [
		_round_to_int(left),
		_round_to_int(top),
		_round_to_int(right - left),
		DEFAULT_TOGGLE_SIZE.y,
	]


func _default_rect(start: Vector2, object_type: String) -> Array:
	var grid_size := _grid_size()
	if object_type == TOOL_TOGGLE_PLATFORM:
		var toggle_width := mini(
			DEFAULT_TOGGLE_SIZE.x,
			int(LOGICAL_SIZE.x)
		)
		var toggle_height := DEFAULT_TOGGLE_SIZE.y
		var toggle_left := mini(
			_round_to_int(start.x),
			int(LOGICAL_SIZE.x) - toggle_width
		)
		var toggle_top := mini(
			_round_to_int(start.y),
			int(LOGICAL_SIZE.y) - toggle_height
		)
		return [
			maxi(toggle_left, 0),
			maxi(toggle_top, 0),
			toggle_width,
			toggle_height,
		]

	var width := mini(
		maxi(DEFAULT_SOLID_SIZE.x, grid_size),
		int(LOGICAL_SIZE.x)
	)
	var height := mini(
		maxi(DEFAULT_SOLID_SIZE.y, grid_size),
		int(LOGICAL_SIZE.y)
	)
	var left := mini(_round_to_int(start.x), int(LOGICAL_SIZE.x) - width)
	var top := mini(_round_to_int(start.y), int(LOGICAL_SIZE.y) - height)
	return [maxi(left, 0), maxi(top, 0), width, height]


func _object_anchor(object: Dictionary) -> Vector2:
	var object_type := str(object.get("type", ""))
	if RECT_OBJECT_TYPES.has(object_type):
		var rect_values: Variant = object.get("rect")
		if _is_number_array(rect_values, 4):
			return _rect_from_payload(rect_values).get_center()
		return Vector2.ZERO

	var position_values: Variant = object.get("position")
	if _is_number_array(position_values, 2):
		return Vector2(
			float(position_values[0]),
			float(position_values[1])
		)
	return Vector2.ZERO


func _snap_logical_point(
	point: Vector2,
	allow_canvas_end: bool
) -> Vector2:
	var grid_size := float(_grid_size())
	var snapped := Vector2(
		roundf(point.x / grid_size) * grid_size,
		roundf(point.y / grid_size) * grid_size
	)
	var maximum := LOGICAL_SIZE
	if not allow_canvas_end:
		maximum = Vector2(
			floorf((LOGICAL_SIZE.x - 1.0) / grid_size) * grid_size,
			floorf((LOGICAL_SIZE.y - 1.0) / grid_size) * grid_size
		)
	return snapped.clamp(Vector2.ZERO, maximum)


func _snap_delta(delta: Vector2) -> Vector2:
	var grid_size := float(_grid_size())
	return Vector2(
		roundf(delta.x / grid_size) * grid_size,
		roundf(delta.y / grid_size) * grid_size
	)


func _grid_size() -> int:
	var canvas: Variant = _document.get("canvas", {})
	if typeof(canvas) != TYPE_DICTIONARY:
		return DEFAULT_GRID_SIZE

	var value: Variant = canvas.get("grid_size", DEFAULT_GRID_SIZE)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return DEFAULT_GRID_SIZE

	var numeric_value := float(value)
	if not is_finite(numeric_value) or numeric_value < 1.0:
		return DEFAULT_GRID_SIZE

	return clampi(
		int(roundf(numeric_value)),
		1,
		int(minf(LOGICAL_SIZE.x, LOGICAL_SIZE.y))
	)


func _objects() -> Array:
	var objects: Variant = _document.get("objects", [])
	return objects if typeof(objects) == TYPE_ARRAY else []


func _canvas_scale() -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return 0.0
	return minf(size.x / LOGICAL_SIZE.x, size.y / LOGICAL_SIZE.y)


func _canvas_view_rect() -> Rect2:
	var canvas_scale := _canvas_scale()
	var drawn_size := LOGICAL_SIZE * canvas_scale
	return Rect2((size - drawn_size) * 0.5, drawn_size)


func _local_to_logical(
	local_position: Vector2,
	clamp_to_canvas: bool
) -> Vector2:
	var view_rect := _canvas_view_rect()
	var canvas_scale := _canvas_scale()
	if canvas_scale <= 0.0:
		return Vector2.ZERO

	var logical_position := (
		(local_position - view_rect.position) / canvas_scale
	)
	if clamp_to_canvas:
		logical_position = logical_position.clamp(
			Vector2.ZERO,
			LOGICAL_SIZE
		)
	return logical_position


func _logical_rect_to_local(
	logical_rect: Rect2,
	view_rect: Rect2
) -> Rect2:
	var canvas_scale := _canvas_scale()
	return Rect2(
		view_rect.position + logical_rect.position * canvas_scale,
		logical_rect.size * canvas_scale
	)


func _logical_point_to_local(
	logical_point: Vector2,
	view_rect: Rect2
) -> Vector2:
	return (
		view_rect.position
		+ logical_point * _canvas_scale()
	)


func _rect_from_payload(payload: Array) -> Rect2:
	return Rect2(
		float(payload[0]),
		float(payload[1]),
		float(payload[2]),
		float(payload[3])
	)


func _point_payload(point: Vector2) -> Array:
	return [_round_to_int(point.x), _round_to_int(point.y)]


func _duplicate_payload(payload: Variant) -> Variant:
	if payload is Array or payload is Dictionary:
		return payload.duplicate(true)
	return payload


func _is_number_array(value: Variant, expected_size: int) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false

	var values: Array = value
	if values.size() != expected_size:
		return false

	for item: Variant in values:
		if typeof(item) != TYPE_INT and typeof(item) != TYPE_FLOAT:
			return false
		if not is_finite(float(item)):
			return false
	return true


func _round_to_int(value: float) -> int:
	return int(roundf(value))


func _with_alpha(color: Color, alpha_multiplier: float) -> Color:
	return Color(
		color.r,
		color.g,
		color.b,
		color.a * alpha_multiplier
	)


func _event_key(event: InputEventKey) -> Key:
	return (
		event.physical_keycode
		if event.physical_keycode != 0
		else event.keycode
	)

class_name LevelEditorCanvas
extends Control

signal selection_requested(object_id: String)
signal placement_requested(object_type: String, payload: Variant)
signal move_requested(object_id: String, payload: Variant)
signal nudge_requested(direction: Vector2i, fine: bool)
signal link_target_requested(target_id: String)
signal link_cancel_requested

const LEVEL_BEHAVIOR_PRESETS := preload(
	"res://scripts/levels/level_behavior_presets.gd"
)

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
const SHOOTER_GUN_PIVOT_OFFSET := Vector2(0.0, -4.0)
const SHOOTER_MUZZLE_LENGTH := 28.0
const SHOOTER_LINE_LENGTH := 900.0
const SHOOTER_PROJECTILE_RADIUS := 5.0
const CATAPULT_SIZE := Vector2(180.0, 20.0)
const CATAPULT_LAUNCH_AREA_OFFSET := Vector2(0.0, -58.0)
const CATAPULT_LAUNCH_AREA_SIZE := Vector2(180.0, 52.0)
const CATAPULT_LAUNCH_ORIGIN_OFFSET := Vector2(90.0, -32.0)
const CATAPULT_SWING_ANGLE_DEGREES := -55.0
const CATAPULT_PREVIEW_GRAVITY := 1500.0
const CATAPULT_PREVIEW_ENEMY_DRAG := 420.0
const CATAPULT_PREVIEW_PLAYER_DRAG := 520.0
const CATAPULT_PREVIEW_DURATION := 0.18
const CATAPULT_PREVIEW_SEGMENTS := 12
const CATAPULT_PIVOT_RADIUS := 14.0
const CATAPULT_MIN_POSITION := Vector2(32.0, 94.0)
const CATAPULT_MAX_POSITION := Vector2(748.0, 530.0)
const VERTICAL_PLATFORM_SIZE := Vector2(80.0, 20.0)
const VERTICAL_PLATFORM_TRAVEL_OFFSET := Vector2(0.0, 136.0)
const VERTICAL_PLATFORM_STOP_RADIUS := 8.0
const VERTICAL_PLATFORM_TRACK_WIDTH := 4.0
const VERTICAL_PLATFORM_MIN_POSITION := Vector2(72.0, 82.0)
const VERTICAL_PLATFORM_MAX_POSITION := Vector2(888.0, 394.0)
const VERTICAL_PLATFORM_PASSENGER_MAX_GAP := 64.0
const VERTICAL_PLATFORM_PASSENGER_ALPHA := 0.42

const TOOL_SELECT := "select"
const TOOL_SOLID_RECT := "solid_rect"
const TOOL_PLAYER_SPAWN := "player_spawn"
const TOOL_PATROL_ENEMY := "patrol_enemy"
const TOOL_SHOVE_ENEMY := "shove_enemy"
const TOOL_SHOOTER_ENEMY := "shooter_enemy"
const TOOL_CATAPULT_PLATFORM := "catapult_platform"
const TOOL_VERTICAL_PLATFORM := "vertical_platform"
const TOOL_TOGGLE_PLATFORM := "toggle_platform"
const TOOL_HINGE := "hinge"
const SUPPORTED_TOOLS := [
	TOOL_SELECT,
	TOOL_SOLID_RECT,
	TOOL_PLAYER_SPAWN,
	TOOL_PATROL_ENEMY,
	TOOL_SHOVE_ENEMY,
	TOOL_SHOOTER_ENEMY,
	TOOL_CATAPULT_PLATFORM,
	TOOL_VERTICAL_PLATFORM,
	TOOL_TOGGLE_PLATFORM,
	TOOL_HINGE,
]
const RECT_OBJECT_TYPES := [
	TOOL_SOLID_RECT,
	TOOL_TOGGLE_PLATFORM,
]
const ACTOR_OBJECT_TYPES := [
	TOOL_PLAYER_SPAWN,
	TOOL_PATROL_ENEMY,
	TOOL_SHOVE_ENEMY,
	TOOL_SHOOTER_ENEMY,
]
const POINT_OBJECT_TYPES := [
	TOOL_PLAYER_SPAWN,
	TOOL_PATROL_ENEMY,
	TOOL_SHOVE_ENEMY,
	TOOL_SHOOTER_ENEMY,
	TOOL_CATAPULT_PLATFORM,
	TOOL_VERTICAL_PLATFORM,
	TOOL_HINGE,
]
const DRAW_ORDER := [
	TOOL_SOLID_RECT,
	TOOL_TOGGLE_PLATFORM,
	TOOL_VERTICAL_PLATFORM,
	TOOL_CATAPULT_PLATFORM,
	TOOL_PLAYER_SPAWN,
	TOOL_PATROL_ENEMY,
	TOOL_SHOVE_ENEMY,
	TOOL_SHOOTER_ENEMY,
	TOOL_HINGE,
]
const HIT_ORDER := [
	TOOL_HINGE,
	TOOL_SHOOTER_ENEMY,
	TOOL_SHOVE_ENEMY,
	TOOL_PATROL_ENEMY,
	TOOL_PLAYER_SPAWN,
	TOOL_CATAPULT_PLATFORM,
	TOOL_TOGGLE_PLATFORM,
	TOOL_VERTICAL_PLATFORM,
	TOOL_SOLID_RECT,
]
const HINGE_TARGET_TYPES := [
	TOOL_TOGGLE_PLATFORM,
	TOOL_CATAPULT_PLATFORM,
	TOOL_VERTICAL_PLATFORM,
]

const ACTOR_HALF_EXTENTS := {
	TOOL_PLAYER_SPAWN: Vector2(14.0, 20.0),
	TOOL_PATROL_ENEMY: Vector2(15.0, 18.0),
	TOOL_SHOVE_ENEMY: Vector2(16.0, 19.0),
	TOOL_SHOOTER_ENEMY: Vector2(17.0, 19.0),
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
const COLOR_ONE_WAY_SOLID := Color(0.267, 0.365, 0.498, 1.0)
const COLOR_ONE_WAY_EDGE := Color(0.439, 0.827, 0.816, 0.9)
const COLOR_PLAYER := Color(0.251, 0.878, 0.816, 1.0)
const COLOR_PLAYER_FACE := Color(0.071, 0.204, 0.251, 1.0)
const COLOR_PATROL := Color(0.973, 0.58, 0.267, 1.0)
const COLOR_PATROL_FACE := Color(0.302, 0.125, 0.098, 1.0)
const COLOR_SHOVE := Color(0.929, 0.31, 0.337, 1.0)
const COLOR_SHOVE_FACE := Color(0.286, 0.071, 0.118, 1.0)
const COLOR_SHOVE_RANGE := Color(0.929, 0.31, 0.337, 0.1)
const COLOR_SHOVE_RANGE_EDGE := Color(0.929, 0.31, 0.337, 0.52)
const COLOR_SHOOTER := Color(0.718, 0.376, 0.925, 1.0)
const COLOR_SHOOTER_FACE := Color(0.204, 0.075, 0.333, 1.0)
const COLOR_SHOOTER_GUN := Color(1.0, 0.58, 0.267, 1.0)
const COLOR_SHOOTER_LINE := Color(1.0, 0.255, 0.31, 0.72)
const COLOR_SHOOTER_CORRIDOR := Color(1.0, 0.255, 0.31, 0.08)
const COLOR_SHOOTER_OUT_OF_RANGE := Color(0.439, 0.502, 0.616, 0.55)
const COLOR_CATAPULT := Color(0.278, 0.345, 0.459, 1.0)
const COLOR_CATAPULT_EDGE := Color(0.392, 0.455, 0.584, 1.0)
const COLOR_CATAPULT_ACCENT := Color(0.439, 0.827, 0.816, 0.85)
const COLOR_CATAPULT_WARNING := Color(0.925, 0.58, 0.267, 0.65)
const COLOR_CATAPULT_ZONE := Color(0.925, 0.58, 0.267, 0.1)
const COLOR_CATAPULT_TARGET := Color(1.0, 0.82, 0.36, 0.85)
const COLOR_VERTICAL_PLATFORM := Color(0.278, 0.345, 0.459, 1.0)
const COLOR_VERTICAL_EDGE := Color(0.392, 0.455, 0.584, 1.0)
const COLOR_VERTICAL_ACCENT := Color(0.439, 0.827, 0.816, 0.85)
const COLOR_VERTICAL_TRACK := Color(0.235, 0.302, 0.416, 0.85)
const COLOR_VERTICAL_ZONE := Color(0.439, 0.827, 0.816, 0.08)
const COLOR_VERTICAL_TARGET_FILL := Color(0.925, 0.58, 0.267, 0.14)
const COLOR_VERTICAL_TARGET := Color(0.925, 0.58, 0.267, 0.65)
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

	for object_type: String in DRAW_ORDER:
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
				var target := _hit_test_hinge_target(
					logical_position
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
		var target := _hit_test_hinge_target(
			_link_cursor_logical
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

		TOOL_PLAYER_SPAWN, \
		TOOL_PATROL_ENEMY, \
		TOOL_SHOVE_ENEMY, \
		TOOL_SHOOTER_ENEMY, \
		TOOL_CATAPULT_PLATFORM, \
		TOOL_VERTICAL_PLATFORM, \
		TOOL_HINGE:
			var snapped_position := _snap_logical_point(
				logical_position,
				false
			)
			if _tool == TOOL_CATAPULT_PLATFORM:
				snapped_position = clamp_catapult_position(
					snapped_position
				)
			elif _tool == TOOL_VERTICAL_PLATFORM:
				snapped_position = clamp_vertical_platform_position(
					snapped_position
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
		or _drag_object_type == TOOL_CATAPULT_PLATFORM
		or _drag_object_type == TOOL_VERTICAL_PLATFORM
		or _drag_object_type == TOOL_HINGE
	):
		if not _is_number_array(_drag_original_payload, 2):
			return null

		var original: Array = _drag_original_payload
		var position := Vector2(
			float(original[0]),
			float(original[1])
		) + snapped_delta
		if _drag_object_type == TOOL_CATAPULT_PLATFORM:
			position = clamp_catapult_position(position)
		elif _drag_object_type == TOOL_VERTICAL_PLATFORM:
			position = clamp_vertical_platform_position(position)
		else:
			position.x = clampf(
				position.x,
				0.0,
				LOGICAL_SIZE.x - 1.0
			)
			position.y = clampf(
				position.y,
				0.0,
				LOGICAL_SIZE.y - 1.0
			)
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
			and _is_hinge_target_type(
				str(target.get("type", ""))
			)
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
			_draw_solid(
				rect_values,
				view_rect,
				alpha,
				bool(object.get("one_way", false))
			)

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

		TOOL_VERTICAL_PLATFORM:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			var object_id := str(object.get("id", ""))
			var moving_this_platform := (
				_drag_kind == TOOL_SELECT
				and _drag_moved
				and _drag_object_id == object_id
			)
			_draw_vertical_platform(
				position_values,
				view_rect,
				alpha,
				object_id == _selected_id
				and not moving_this_platform,
				object_id
			)

		TOOL_CATAPULT_PLATFORM:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			var object_id := str(object.get("id", ""))
			var moving_this_catapult := (
				_drag_kind == TOOL_SELECT
				and _drag_moved
				and _drag_object_id == object_id
			)
			_draw_catapult(
				position_values,
				view_rect,
				alpha,
				object_id == _selected_id
				and not moving_this_catapult,
				_behavior_preset(object)
			)

		TOOL_PLAYER_SPAWN, TOOL_PATROL_ENEMY, TOOL_SHOVE_ENEMY, TOOL_SHOOTER_ENEMY:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			if (
				object_type == TOOL_SHOVE_ENEMY
				and str(object.get("id", "")) == _selected_id
			):
				_draw_shove_detection(
					position_values,
					view_rect,
					alpha,
					_behavior_preset(object)
				)
			var direction := int(
				object.get(
					"direction",
					-1 if object_type == TOOL_SHOVE_ENEMY else 1
				)
			)
			var shooter_aim_direction := Vector2.LEFT
			if object_type == TOOL_SHOOTER_ENEMY:
				var shooter_preview := _shooter_preview(position_values)
				shooter_aim_direction = shooter_preview.get(
					"direction",
					Vector2.LEFT
				)
				direction = (
					-1 if shooter_aim_direction.x < 0.0 else 1
				)
				var object_id := str(object.get("id", ""))
				var moving_this_shooter := (
					_drag_kind == TOOL_SELECT
					and _drag_moved
					and _drag_object_id == object_id
				)
				if (
					object_id == _selected_id
					and not moving_this_shooter
				):
					_draw_shooter_aim(
						shooter_preview,
						view_rect,
						alpha
					)
			_draw_actor(
				object_type,
				position_values,
				view_rect,
				alpha,
				direction
			)
			if object_type == TOOL_SHOOTER_ENEMY:
				_draw_shooter_barrel(
					position_values,
					shooter_aim_direction,
					view_rect,
					alpha
				)

		TOOL_HINGE:
			var position_values: Variant = object.get("position")
			if not _is_number_array(position_values, 2):
				return
			_draw_hinge(position_values, view_rect, alpha)


func _draw_solid(
	rect_values: Array,
	view_rect: Rect2,
	alpha: float,
	one_way := false
) -> void:
	var logical_rect := _rect_from_payload(rect_values)
	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	var body_color := (
		COLOR_ONE_WAY_SOLID if one_way else COLOR_SOLID
	)
	var edge_color := (
		COLOR_ONE_WAY_EDGE if one_way else COLOR_SOLID_EDGE
	)
	draw_rect(local_rect, _with_alpha(body_color, alpha))

	var edge_height := minf(TOP_EDGE_HEIGHT, logical_rect.size.y)
	var logical_edge := Rect2(
		logical_rect.position,
		Vector2(logical_rect.size.x, edge_height)
	)
	draw_rect(
		_logical_rect_to_local(logical_edge, view_rect),
		_with_alpha(edge_color, alpha)
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


func _draw_vertical_platform(
	position_values: Array,
	view_rect: Rect2,
	alpha: float,
	show_preview: bool,
	object_id: String = ""
) -> void:
	var position := _point_from_payload(position_values)
	var upper_rect := vertical_platform_upper_rect(position)
	var lower_rect := vertical_platform_lower_rect(position)
	var lower_position := position + VERTICAL_PLATFORM_TRAVEL_OFFSET

	if show_preview:
		var corridor := vertical_platform_corridor_rect(position)
		var local_corridor := _logical_rect_to_local(
			corridor,
			view_rect
		)
		draw_rect(
			local_corridor,
			_with_alpha(COLOR_VERTICAL_ZONE, alpha)
		)
		draw_rect(
			local_corridor,
			_with_alpha(COLOR_VERTICAL_TARGET, alpha),
			false,
			1.5
		)

	var local_position := _logical_point_to_local(position, view_rect)
	var local_lower_position := _logical_point_to_local(
		lower_position,
		view_rect
	)
	draw_line(
		local_position,
		local_lower_position,
		_with_alpha(COLOR_VERTICAL_TRACK, alpha),
		VERTICAL_PLATFORM_TRACK_WIDTH * _canvas_scale(),
		true
	)

	_draw_vertical_stop(position, view_rect, alpha)
	_draw_vertical_stop(lower_position, view_rect, alpha)

	if show_preview:
		_draw_vertical_platform_body(
			lower_rect,
			view_rect,
			alpha,
			true
		)
		_draw_vertical_direction_arrow(
			position,
			lower_position,
			view_rect,
			alpha
		)

	_draw_vertical_platform_body(
		upper_rect,
		view_rect,
		alpha,
		false
	)
	if show_preview:
		_draw_vertical_passenger_preview(
			position,
			object_id,
			view_rect,
			alpha
		)


func _draw_vertical_platform_body(
	logical_rect: Rect2,
	view_rect: Rect2,
	alpha: float,
	is_target: bool
) -> void:
	var local_rect := _logical_rect_to_local(logical_rect, view_rect)
	var body_color := (
		COLOR_VERTICAL_TARGET_FILL
		if is_target
		else COLOR_VERTICAL_PLATFORM
	)
	var edge_color := (
		COLOR_VERTICAL_TARGET
		if is_target
		else COLOR_VERTICAL_EDGE
	)
	draw_rect(local_rect, _with_alpha(body_color, alpha))
	var edge_rect := Rect2(
		logical_rect.position,
		Vector2(logical_rect.size.x, 5.0)
	)
	draw_rect(
		_logical_rect_to_local(edge_rect, view_rect),
		_with_alpha(edge_color, alpha)
	)
	draw_rect(
		local_rect,
		_with_alpha(
			COLOR_VERTICAL_TARGET
			if is_target
			else COLOR_VERTICAL_ACCENT,
			alpha
		),
		false,
		2.0
	)

	if is_target:
		return
	var center := logical_rect.get_center()
	var port_radius := 6.0 * _canvas_scale()
	var local_center := _logical_point_to_local(center, view_rect)
	draw_colored_polygon(
		PackedVector2Array(
			[
				local_center + Vector2(0.0, -port_radius),
				local_center + Vector2(port_radius, 0.0),
				local_center + Vector2(0.0, port_radius),
				local_center + Vector2(-port_radius, 0.0),
			]
		),
		_with_alpha(COLOR_VERTICAL_ACCENT, alpha)
	)


func _draw_vertical_stop(
	position: Vector2,
	view_rect: Rect2,
	alpha: float
) -> void:
	var local_center := _logical_point_to_local(position, view_rect)
	var radius := VERTICAL_PLATFORM_STOP_RADIUS * _canvas_scale()
	var points := PackedVector2Array(
		[
			local_center + Vector2(0.0, -radius),
			local_center + Vector2(radius, 0.0),
			local_center + Vector2(0.0, radius),
			local_center + Vector2(-radius, 0.0),
		]
	)
	draw_colored_polygon(
		points,
		_with_alpha(COLOR_VERTICAL_ACCENT, alpha)
	)
	var inner_radius := radius * 0.375
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
		_with_alpha(COLOR_BACKDROP, alpha)
	)


func _draw_vertical_direction_arrow(
	upper_position: Vector2,
	lower_position: Vector2,
	view_rect: Rect2,
	alpha: float
) -> void:
	var arrow_center := upper_position.lerp(lower_position, 0.5)
	var arrow_tip := arrow_center + Vector2(0.0, 13.0)
	var arrow_left := arrow_center + Vector2(-6.0, 5.0)
	var arrow_right := arrow_center + Vector2(6.0, 5.0)
	draw_colored_polygon(
		_logical_points_to_local(
			PackedVector2Array(
				[arrow_tip, arrow_left, arrow_right]
			),
			view_rect
		),
		_with_alpha(COLOR_VERTICAL_TARGET, alpha)
	)


func _draw_vertical_passenger_preview(
	position: Vector2,
	platform_id: String,
	view_rect: Rect2,
	alpha: float
) -> void:
	var passengers := _vertical_platform_passengers(
		position,
		platform_id
	)
	if passengers.is_empty():
		return

	var destination_blockers := (
		_vertical_platform_destination_blockers(
			position,
			platform_id
		)
	)
	var destination_player: Variant = _resting_actor_position(
		TOOL_PLAYER_SPAWN,
		_player_spawn_position(),
		destination_blockers
	)
	for passenger: Dictionary in passengers:
		if passenger.get("type", "") != TOOL_PLAYER_SPAWN:
			continue
		destination_player = _vertical_platform_passenger_destination(
			passenger,
			position
		)
		break

	var preview_alpha := alpha * VERTICAL_PLATFORM_PASSENGER_ALPHA
	for passenger: Dictionary in passengers:
		var source_bounds := _bounds_for_object(passenger)
		draw_rect(
			_logical_rect_to_local(
				source_bounds,
				view_rect
			).grow(2.0),
			_with_alpha(COLOR_VERTICAL_TARGET, alpha),
			false,
			2.0
		)

		var object_type := str(passenger.get("type", ""))
		var destination := _vertical_platform_passenger_destination(
			passenger,
			position
		)
		var destination_values := [
			destination.x,
			destination.y,
		]
		var direction := int(
			passenger.get(
				"direction",
				-1 if object_type == TOOL_SHOVE_ENEMY else 1
			)
		)
		var shooter_direction := Vector2.LEFT
		if (
			object_type == TOOL_SHOOTER_ENEMY
			and typeof(destination_player) == TYPE_VECTOR2
		):
			var shooter_preview := shooter_aim_preview(
				destination,
				destination_player,
				destination_blockers
			)
			shooter_direction = shooter_preview.get(
				"direction",
				Vector2.LEFT
			)
			direction = (
				-1 if shooter_direction.x < 0.0 else 1
			)
			_draw_shooter_aim(
				shooter_preview,
				view_rect,
				preview_alpha
			)

		_draw_actor(
			object_type,
			destination_values,
			view_rect,
			preview_alpha,
			direction
		)
		if object_type == TOOL_SHOOTER_ENEMY:
			_draw_shooter_barrel(
				destination_values,
				shooter_direction,
				view_rect,
				preview_alpha
			)


func _vertical_platform_passengers(
	position: Vector2,
	platform_id: String
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var upper_rect := vertical_platform_upper_rect(position)
	var other_supports := _initial_collision_rects()
	for object: Variant in _objects():
		if (
			typeof(object) != TYPE_DICTIONARY
			or not ACTOR_OBJECT_TYPES.has(
				str(object.get("type", ""))
			)
		):
			continue

		var actor: Dictionary = object
		var actor_bounds := _bounds_for_object(actor)
		if not _rects_overlap_horizontally(
			actor_bounds,
			upper_rect
		):
			continue
		var gap := upper_rect.position.y - actor_bounds.end.y
		if (
			gap < 0.0
			or gap > VERTICAL_PLATFORM_PASSENGER_MAX_GAP
		):
			continue

		var has_closer_support := false
		for support: Dictionary in other_supports:
			if str(support.get("id", "")) == platform_id:
				continue
			var support_rect: Rect2 = support.get(
				"rect",
				Rect2()
			)
			if (
				support_rect.size == Vector2.ZERO
				or not _rects_overlap_horizontally(
					actor_bounds,
					support_rect
				)
			):
				continue
			if (
				support_rect.position.y >= actor_bounds.end.y
				and support_rect.position.y
				< upper_rect.position.y
			):
				has_closer_support = true
				break
		if not has_closer_support:
			result.append(actor)
	return result


func _vertical_platform_passenger_destination(
	actor: Dictionary,
	platform_position: Vector2
) -> Vector2:
	var object_type := str(actor.get("type", ""))
	var half_extents: Vector2 = ACTOR_HALF_EXTENTS.get(
		object_type,
		Vector2.ZERO
	)
	var source_position := _object_anchor(actor)
	return Vector2(
		source_position.x,
		vertical_platform_lower_rect(
			platform_position
		).position.y - half_extents.y
	)


func _vertical_platform_destination_blockers(
	position: Vector2,
	platform_id: String
) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var replaced_platform := false
	for blocker: Dictionary in _initial_collision_rects():
		if str(blocker.get("id", "")) == platform_id:
			blockers.append(
				{
					"id": platform_id,
					"rect": vertical_platform_lower_rect(
						position
					),
				}
			)
			replaced_platform = true
		else:
			blockers.append(blocker)
	if not replaced_platform:
		blockers.append(
			{
				"id": platform_id,
				"rect": vertical_platform_lower_rect(position),
			}
		)
	return blockers


static func _resting_actor_position(
	object_type: String,
	source_position: Variant,
	blockers: Array[Dictionary]
) -> Variant:
	if (
		typeof(source_position) != TYPE_VECTOR2
		or not ACTOR_HALF_EXTENTS.has(object_type)
	):
		return source_position

	var position: Vector2 = source_position
	var half_extents: Vector2 = ACTOR_HALF_EXTENTS[object_type]
	var actor_bounds := Rect2(
		position - half_extents,
		half_extents * 2.0
	)
	var nearest_support_y := INF
	for blocker: Dictionary in blockers:
		var support: Rect2 = blocker.get("rect", Rect2())
		if (
			support.size == Vector2.ZERO
			or not _rects_overlap_horizontally(
				actor_bounds,
				support
			)
			or support.position.y < actor_bounds.end.y
		):
			continue
		nearest_support_y = minf(
			nearest_support_y,
			support.position.y
		)

	if is_inf(nearest_support_y):
		return position
	return Vector2(
		position.x,
		nearest_support_y - half_extents.y
	)


static func _rects_overlap_horizontally(
	first: Rect2,
	second: Rect2
) -> bool:
	return (
		first.position.x < second.end.x
		and first.end.x > second.position.x
	)


static func vertical_platform_upper_rect(position: Vector2) -> Rect2:
	return Rect2(
		position - VERTICAL_PLATFORM_SIZE * 0.5,
		VERTICAL_PLATFORM_SIZE
	)


static func vertical_platform_lower_rect(position: Vector2) -> Rect2:
	return vertical_platform_upper_rect(
		position + VERTICAL_PLATFORM_TRAVEL_OFFSET
	)


static func vertical_platform_corridor_rect(position: Vector2) -> Rect2:
	return vertical_platform_upper_rect(position).merge(
		vertical_platform_lower_rect(position)
	)


static func vertical_platform_passenger_clearance_rect(
	position: Vector2
) -> Rect2:
	var corridor := vertical_platform_corridor_rect(position)
	var passenger_height: float = (
		ACTOR_HALF_EXTENTS[TOOL_PLAYER_SPAWN].y * 2.0
	)
	return Rect2(
		corridor.position - Vector2(0.0, passenger_height),
		corridor.size + Vector2(0.0, passenger_height)
	)


static func clamp_vertical_platform_position(
	position: Vector2
) -> Vector2:
	return position.clamp(
		VERTICAL_PLATFORM_MIN_POSITION,
		VERTICAL_PLATFORM_MAX_POSITION
	)


func _draw_catapult(
	position_values: Array,
	view_rect: Rect2,
	alpha: float,
	show_preview: bool,
	behavior_preset: String = LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
) -> void:
	var position := _point_from_payload(position_values)
	var rest_rect := catapult_rest_rect(position)
	var local_rest := _logical_rect_to_local(rest_rect, view_rect)
	draw_rect(
		local_rest,
		_with_alpha(COLOR_CATAPULT, alpha)
	)
	var edge_rect := Rect2(
		rest_rect.position,
		Vector2(rest_rect.size.x, 5.0)
	)
	draw_rect(
		_logical_rect_to_local(edge_rect, view_rect),
		_with_alpha(COLOR_CATAPULT_EDGE, alpha)
	)
	draw_rect(
		local_rest,
		_with_alpha(COLOR_CATAPULT_ACCENT, alpha),
		false,
		2.0
	)

	var local_pivot := _logical_point_to_local(position, view_rect)
	var pivot_radius := CATAPULT_PIVOT_RADIUS * _canvas_scale()
	var pivot_points := PackedVector2Array(
		[
			local_pivot + Vector2(0.0, -pivot_radius),
			local_pivot + Vector2(pivot_radius, 0.0),
			local_pivot + Vector2(0.0, pivot_radius),
			local_pivot + Vector2(-pivot_radius, 0.0),
		]
	)
	draw_colored_polygon(
		pivot_points,
		_with_alpha(COLOR_CATAPULT_ACCENT, alpha)
	)
	var inner_radius := pivot_radius * 0.5
	var inner_points := PackedVector2Array(
		[
			local_pivot + Vector2(0.0, -inner_radius),
			local_pivot + Vector2(inner_radius, 0.0),
			local_pivot + Vector2(0.0, inner_radius),
			local_pivot + Vector2(-inner_radius, 0.0),
		]
	)
	draw_colored_polygon(
		inner_points,
		_with_alpha(COLOR_BACKDROP, alpha)
	)

	var guide_points := catapult_guide_points(
		position,
		behavior_preset
	)
	draw_polyline(
		_logical_points_to_local(guide_points, view_rect),
		_with_alpha(COLOR_CATAPULT_ACCENT, alpha),
		2.0,
		true
	)
	var arrow := catapult_guide_arrow_polygon(
		guide_points
	)
	draw_colored_polygon(
		_logical_points_to_local(arrow, view_rect),
		_with_alpha(COLOR_CATAPULT_ACCENT, alpha)
	)

	if show_preview:
		_draw_catapult_preview(
			position,
			view_rect,
			alpha,
			behavior_preset
		)


func _draw_catapult_preview(
	position: Vector2,
	view_rect: Rect2,
	alpha: float,
	behavior_preset: String
) -> void:
	var launch_area := catapult_launch_area_rect(position)
	var local_launch_area := _logical_rect_to_local(
		launch_area,
		view_rect
	)
	draw_rect(
		local_launch_area,
		_with_alpha(COLOR_CATAPULT_ZONE, alpha)
	)
	draw_rect(
		local_launch_area,
		_with_alpha(COLOR_CATAPULT_WARNING, alpha),
		false,
		1.5
	)

	var swing_points := catapult_swing_polygon(position)
	var closed_swing := swing_points.duplicate()
	closed_swing.append(swing_points[0])
	draw_polyline(
		_logical_points_to_local(closed_swing, view_rect),
		_with_alpha(COLOR_CATAPULT_WARNING, alpha),
		2.0,
		true
	)

	var preview_targets: Array[Dictionary] = []
	for object: Variant in _objects():
		if (
			typeof(object) != TYPE_DICTIONARY
			or not ACTOR_OBJECT_TYPES.has(
				str(object.get("type", ""))
			)
		):
			continue
		var bounds := _bounds_for_object(object)
		if not bounds.intersects(launch_area):
			continue
		draw_rect(
			_logical_rect_to_local(bounds, view_rect).grow(2.0),
			_with_alpha(COLOR_CATAPULT_TARGET, alpha),
			false,
			2.0
		)
		preview_targets.append(
			{
				"origin": _object_anchor(object),
				"drag": (
					CATAPULT_PREVIEW_PLAYER_DRAG
					if object.get("type", "") == TOOL_PLAYER_SPAWN
					else CATAPULT_PREVIEW_ENEMY_DRAG
				),
			}
		)

	if preview_targets.is_empty():
		preview_targets.append(
			{
				"origin": position + CATAPULT_LAUNCH_ORIGIN_OFFSET,
				"drag": CATAPULT_PREVIEW_ENEMY_DRAG,
			}
		)
	for target: Dictionary in preview_targets:
		var origin: Vector2 = target["origin"]
		_draw_catapult_trajectory(
			catapult_trajectory_points(
				origin,
				float(target["drag"]),
				behavior_preset
			),
			view_rect,
			alpha
		)


func _draw_catapult_trajectory(
	points: PackedVector2Array,
	view_rect: Rect2,
	alpha: float
) -> void:
	var local_points := _logical_points_to_local(points, view_rect)
	for index in local_points.size() - 1:
		if index % 2 != 0:
			continue
		draw_line(
			local_points[index],
			local_points[index + 1],
			_with_alpha(COLOR_CATAPULT_TARGET, alpha),
			2.0,
			true
		)
	if not local_points.is_empty():
		draw_circle(
			local_points[local_points.size() - 1],
			4.0,
			_with_alpha(COLOR_CATAPULT_TARGET, alpha)
		)


static func catapult_rest_rect(position: Vector2) -> Rect2:
	return Rect2(
		position + Vector2(0.0, -CATAPULT_SIZE.y * 0.5),
		CATAPULT_SIZE
	)


static func catapult_launch_area_rect(position: Vector2) -> Rect2:
	return Rect2(
		position + CATAPULT_LAUNCH_AREA_OFFSET,
		CATAPULT_LAUNCH_AREA_SIZE
	)


static func catapult_swing_polygon(
	position: Vector2
) -> PackedVector2Array:
	var rotation := deg_to_rad(CATAPULT_SWING_ANGLE_DEGREES)
	var points := PackedVector2Array()
	for local_point: Vector2 in [
		Vector2(0.0, -10.0),
		Vector2(180.0, -10.0),
		Vector2(180.0, 10.0),
		Vector2(0.0, 10.0),
	]:
		points.append(position + local_point.rotated(rotation))
	return points


static func catapult_guide_points(
	position: Vector2,
	behavior_preset: String = LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
) -> PackedVector2Array:
	var trajectory := catapult_trajectory_points(
		position + CATAPULT_LAUNCH_ORIGIN_OFFSET,
		CATAPULT_PREVIEW_ENEMY_DRAG,
		behavior_preset
	)
	if trajectory.is_empty():
		return PackedVector2Array()

	var midpoint_index := floori(
		float(trajectory.size() - 1) * 0.5
	)
	return PackedVector2Array(
		[
			trajectory[0],
			trajectory[midpoint_index],
			trajectory[trajectory.size() - 1],
		]
	)


static func catapult_guide_arrow_polygon(
	guide_points: PackedVector2Array
) -> PackedVector2Array:
	if guide_points.size() < 2:
		return PackedVector2Array()

	var tip := guide_points[guide_points.size() - 1]
	var direction := (
		tip - guide_points[guide_points.size() - 2]
	).normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var perpendicular := Vector2(-direction.y, direction.x)
	return PackedVector2Array(
		[
			tip,
			tip - direction * 14.0 + perpendicular * 6.0,
			tip - direction * 14.0 - perpendicular * 6.0,
		]
	)


static func catapult_trajectory_points(
	origin: Vector2,
	horizontal_drag: float = CATAPULT_PREVIEW_ENEMY_DRAG,
	behavior_preset: String = LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var launch_impulse: Vector2 = (
		LEVEL_BEHAVIOR_PRESETS.catapult_launch_impulse(
			behavior_preset
		)
	)
	for index in CATAPULT_PREVIEW_SEGMENTS + 1:
		var time := (
			CATAPULT_PREVIEW_DURATION
			* float(index)
			/ float(CATAPULT_PREVIEW_SEGMENTS)
		)
		points.append(
			origin
			+ Vector2(
				(
					launch_impulse.x * time
					- 0.5 * horizontal_drag * time * time
				),
				launch_impulse.y * time
			)
			+ Vector2(
				0.0,
				0.5
				* CATAPULT_PREVIEW_GRAVITY
				* time
				* time
			)
		)
	return points


static func clamp_catapult_position(position: Vector2) -> Vector2:
	return position.clamp(
		CATAPULT_MIN_POSITION,
		CATAPULT_MAX_POSITION
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
	if not ACTOR_OBJECT_TYPES.has(object_type):
		return
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
	var body_color := COLOR_PATROL
	var face_color := COLOR_PATROL_FACE
	match object_type:
		TOOL_PLAYER_SPAWN:
			body_color = COLOR_PLAYER
			face_color = COLOR_PLAYER_FACE
		TOOL_SHOVE_ENEMY:
			body_color = COLOR_SHOVE
			face_color = COLOR_SHOVE_FACE
		TOOL_SHOOTER_ENEMY:
			body_color = COLOR_SHOOTER
			face_color = COLOR_SHOOTER_FACE
	draw_rect(local_rect, _with_alpha(body_color, alpha))

	var face_offset := (
		0.0
		if object_type != TOOL_PLAYER_SPAWN and direction < 0
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
	if (
		object_type != TOOL_PLAYER_SPAWN
		and object_type != TOOL_SHOOTER_ENEMY
	):
		var facing := -1.0 if direction < 0 else 1.0
		var logical_tip := position + Vector2(
			facing * (half_extents.x + 9.0),
			0.0
		)
		var local_tip := _logical_point_to_local(logical_tip, view_rect)
		var chevron_size := 4.0
		draw_colored_polygon(
			PackedVector2Array(
				[
					local_tip + Vector2(facing * chevron_size, 0.0),
					local_tip + Vector2(-facing * chevron_size, -chevron_size),
					local_tip + Vector2(-facing * chevron_size, chevron_size),
				]
			),
			_with_alpha(body_color, alpha)
		)


func _draw_shove_detection(
	position_values: Array,
	view_rect: Rect2,
	alpha: float,
	behavior_preset: String = LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
) -> void:
	var position := Vector2(
		float(position_values[0]),
		float(position_values[1])
	)
	var local_rect := _logical_rect_to_local(
		shove_detection_rect(position, behavior_preset),
		view_rect
	)
	draw_rect(
		local_rect,
		_with_alpha(COLOR_SHOVE_RANGE, alpha)
	)
	draw_rect(
		local_rect,
		_with_alpha(COLOR_SHOVE_RANGE_EDGE, alpha),
		false,
		1.5
	)


static func shove_detection_rect(
	position: Vector2,
	behavior_preset: String = LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
) -> Rect2:
	var half_size: Vector2 = (
		LEVEL_BEHAVIOR_PRESETS.shove_detection_half_size(
			behavior_preset
		)
	)
	return Rect2(
		position - half_size,
		half_size * 2.0
	)


func _draw_shooter_barrel(
	position_values: Array,
	aim_direction: Vector2,
	view_rect: Rect2,
	alpha: float
) -> void:
	var position := Vector2(
		float(position_values[0]),
		float(position_values[1])
	)
	var direction := (
		aim_direction.normalized()
		if aim_direction.length_squared() > 0.001
		else Vector2.LEFT
	)
	var pivot := position + SHOOTER_GUN_PIVOT_OFFSET
	draw_line(
		_logical_point_to_local(pivot + direction * 7.0, view_rect),
		_logical_point_to_local(
			pivot + direction * SHOOTER_MUZZLE_LENGTH,
			view_rect
		),
		_with_alpha(COLOR_SHOOTER_GUN, alpha),
		5.0,
		true
	)


func _draw_shooter_aim(
	preview: Dictionary,
	view_rect: Rect2,
	alpha: float
) -> void:
	if not bool(preview.get("has_target", false)):
		return

	var muzzle: Vector2 = preview["muzzle"]
	var line_end: Vector2 = preview["line_end"]
	var in_range := bool(preview["in_range"])
	var center_color := (
		COLOR_SHOOTER_LINE
		if in_range
		else COLOR_SHOOTER_OUT_OF_RANGE
	)
	var local_muzzle := _logical_point_to_local(muzzle, view_rect)
	var local_end := _logical_point_to_local(line_end, view_rect)
	if in_range:
		draw_line(
			local_muzzle,
			local_end,
			_with_alpha(COLOR_SHOOTER_CORRIDOR, alpha),
			SHOOTER_PROJECTILE_RADIUS * 2.0 * _canvas_scale(),
			true
		)
		draw_line(
			local_muzzle,
			local_end,
			_with_alpha(center_color, alpha),
			2.0,
			true
		)
	else:
		draw_dashed_line(
			local_muzzle,
			local_end,
			_with_alpha(center_color, alpha),
			1.5,
			6.0
		)

	var marker_size := 5.0
	draw_line(
		local_end - Vector2(marker_size, marker_size),
		local_end + Vector2(marker_size, marker_size),
		_with_alpha(center_color, alpha),
		2.0
	)
	draw_line(
		local_end + Vector2(-marker_size, marker_size),
		local_end + Vector2(marker_size, -marker_size),
		_with_alpha(center_color, alpha),
		2.0
	)


func _shooter_preview(position_values: Array) -> Dictionary:
	var shooter_position := Vector2(
		float(position_values[0]),
		float(position_values[1])
	)
	var player_position: Variant = _player_spawn_position()
	if player_position == null:
		return {
			"has_target": false,
			"direction": Vector2.LEFT,
		}
	return shooter_aim_preview(
		shooter_position,
		player_position,
		_shooter_blockers()
	)


func _player_spawn_position() -> Variant:
	for object: Variant in _objects():
		if (
			typeof(object) == TYPE_DICTIONARY
			and object.get("type", "") == TOOL_PLAYER_SPAWN
		):
			var values: Variant = object.get("position")
			if _is_number_array(values, 2):
				return Vector2(float(values[0]), float(values[1]))
	return null


func _shooter_blockers() -> Array[Dictionary]:
	return _initial_collision_rects()


func _initial_collision_rects() -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	for object: Variant in _objects():
		if typeof(object) != TYPE_DICTIONARY:
			continue
		var object_type := str(object.get("type", ""))
		var blocker_rect := Rect2()
		if object_type == TOOL_SOLID_RECT:
			var values: Variant = object.get("rect")
			if _is_number_array(values, 4):
				blocker_rect = _rect_from_payload(values)
		elif (
				object_type == TOOL_TOGGLE_PLATFORM
				and bool(object.get("starts_active", true))
		):
			var values: Variant = object.get("rect")
			if _is_number_array(values, 4):
				blocker_rect = _rect_from_payload(values)
		elif object_type == TOOL_CATAPULT_PLATFORM:
			var position_values: Variant = object.get("position")
			if _is_number_array(position_values, 2):
				blocker_rect = catapult_rest_rect(
					_point_from_payload(position_values)
				)
		elif object_type == TOOL_VERTICAL_PLATFORM:
			var position_values: Variant = object.get("position")
			if _is_number_array(position_values, 2):
				blocker_rect = vertical_platform_upper_rect(
					_point_from_payload(position_values)
				)
		if blocker_rect.size == Vector2.ZERO:
			continue
		blockers.append(
			{
				"id": str(object.get("id", "")),
				"rect": blocker_rect,
			}
		)
	return blockers


static func shooter_aim_preview(
	shooter_position: Vector2,
	player_position: Vector2,
	blockers: Array[Dictionary]
) -> Dictionary:
	var pivot := shooter_position + SHOOTER_GUN_PIVOT_OFFSET
	var target_offset := player_position - pivot
	var direction := (
		target_offset.normalized()
		if target_offset.length_squared() > 0.001
		else Vector2.LEFT
	)
	var muzzle := pivot + direction * SHOOTER_MUZZLE_LENGTH
	var center_distance := shooter_position.distance_to(player_position)
	var in_range := center_distance <= SHOOTER_LINE_LENGTH
	var aim_distance := minf(
		muzzle.distance_to(player_position),
		SHOOTER_LINE_LENGTH
	)
	var unclipped_end := muzzle + direction * aim_distance
	var line_end := unclipped_end
	var blocker_id := ""
	var nearest_t := 1.0
	if in_range:
		var lateral_direction := direction.orthogonal()
		var lateral_offsets: Array[float] = [
			-SHOOTER_PROJECTILE_RADIUS,
			0.0,
			SHOOTER_PROJECTILE_RADIUS,
		]
		for blocker: Dictionary in blockers:
			var rect: Rect2 = blocker.get("rect", Rect2())
			for lateral_offset: float in lateral_offsets:
				var ray_offset := (
					lateral_direction * lateral_offset
				)
				var hit_t := _segment_rect_hit_t(
					muzzle + ray_offset,
					unclipped_end + ray_offset,
					rect
				)
				if hit_t < 0.0 or hit_t >= nearest_t:
					continue
				nearest_t = hit_t
				line_end = muzzle.lerp(unclipped_end, hit_t)
				blocker_id = str(blocker.get("id", ""))

	return {
		"has_target": true,
		"in_range": in_range,
		"direction": direction,
		"pivot": pivot,
		"muzzle": muzzle,
		"unclipped_end": unclipped_end,
		"line_end": line_end,
		"blocker_id": blocker_id,
	}


static func _segment_rect_hit_t(
	segment_start: Vector2,
	segment_end: Vector2,
	rect: Rect2
) -> float:
	var delta := segment_end - segment_start
	var t_enter := 0.0
	var t_exit := 1.0
	for axis in 2:
		var origin := segment_start[axis]
		var direction := delta[axis]
		var minimum := rect.position[axis]
		var maximum := rect.end[axis]
		if is_zero_approx(direction):
			if origin < minimum or origin > maximum:
				return -1.0
			continue
		var first := (minimum - origin) / direction
		var second := (maximum - origin) / direction
		if first > second:
			var swap := first
			first = second
			second = swap
		t_enter = maxf(t_enter, first)
		t_exit = minf(t_exit, second)
		if t_enter > t_exit:
			return -1.0
	return t_enter


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
				COLOR_GHOST.a,
				false
			)
	elif (
		_drag_kind == TOOL_SELECT
		and _drag_moved
		and _is_number_array(_drag_preview_payload, 2)
		and (
			ACTOR_HALF_EXTENTS.has(_drag_object_type)
			or _drag_object_type == TOOL_CATAPULT_PLATFORM
			or _drag_object_type == TOOL_VERTICAL_PLATFORM
			or _drag_object_type == TOOL_HINGE
		)
	):
		var position_values: Array = _drag_preview_payload
		var position := _point_from_payload(position_values)
		if _drag_object_type == TOOL_CATAPULT_PLATFORM:
			var dragged_object := _find_object(_drag_object_id)
			var pivot_bounds := Rect2(
				position - Vector2.ONE * CATAPULT_PIVOT_RADIUS,
				Vector2.ONE * CATAPULT_PIVOT_RADIUS * 2.0
			)
			logical_rect = catapult_rest_rect(position).merge(
				pivot_bounds
			)
			_draw_catapult(
				position_values,
				view_rect,
				COLOR_GHOST.a,
				true,
				_behavior_preset(dragged_object)
			)
		elif _drag_object_type == TOOL_VERTICAL_PLATFORM:
			logical_rect = vertical_platform_corridor_rect(position)
			_draw_vertical_platform(
				position_values,
				view_rect,
				COLOR_GHOST.a,
				true,
				_drag_object_id
			)
		elif _drag_object_type == TOOL_HINGE:
			logical_rect = Rect2(
				position - HINGE_HALF_EXTENTS,
				HINGE_HALF_EXTENTS * 2.0
			)
			_draw_hinge(
				position_values,
				view_rect,
				COLOR_GHOST.a
			)
		else:
			var half_extents := Vector2(
				ACTOR_HALF_EXTENTS[_drag_object_type]
			)
			logical_rect = Rect2(
				position - half_extents,
				half_extents * 2.0
			)
			if _drag_object_type == TOOL_SHOVE_ENEMY:
				var dragged_object := _find_object(_drag_object_id)
				_draw_shove_detection(
					position_values,
					view_rect,
					COLOR_GHOST.a,
					_behavior_preset(dragged_object)
				)
			var actor_direction := int(
				_find_object(_drag_object_id).get(
					"direction",
					1
				)
			)
			var shooter_aim_direction := Vector2.LEFT
			if _drag_object_type == TOOL_SHOOTER_ENEMY:
				var shooter_preview := _shooter_preview(position_values)
				shooter_aim_direction = shooter_preview.get(
					"direction",
					Vector2.LEFT
				)
				actor_direction = (
					-1
					if shooter_aim_direction.x < 0.0
					else 1
				)
				_draw_shooter_aim(
					shooter_preview,
					view_rect,
					COLOR_GHOST.a
				)
			_draw_actor(
				_drag_object_type,
				position_values,
				view_rect,
				COLOR_GHOST.a,
				actor_direction
			)
			if _drag_object_type == TOOL_SHOOTER_ENEMY:
				_draw_shooter_barrel(
					position_values,
					shooter_aim_direction,
					view_rect,
					COLOR_GHOST.a
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
			var dragged_object := _find_object(_drag_object_id)
			_draw_solid(
				_drag_preview_payload,
				view_rect,
				COLOR_GHOST.a,
				bool(dragged_object.get("one_way", false))
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
	for object_type: String in HIT_ORDER:
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


func _hit_test_hinge_target(
	logical_position: Vector2
) -> Dictionary:
	var objects := _objects()
	for object_type: String in HIT_ORDER:
		if not HINGE_TARGET_TYPES.has(object_type):
			continue
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


func _is_hinge_target_type(object_type: String) -> bool:
	return HINGE_TARGET_TYPES.has(object_type)


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

	if object_type == TOOL_CATAPULT_PLATFORM:
		var position_values: Variant = object.get("position")
		if not _is_number_array(position_values, 2):
			return Rect2()
		var position := _point_from_payload(position_values)
		var pivot_bounds := Rect2(
			position - Vector2.ONE * CATAPULT_PIVOT_RADIUS,
			Vector2.ONE * CATAPULT_PIVOT_RADIUS * 2.0
		)
		return catapult_rest_rect(position).merge(pivot_bounds)

	if object_type == TOOL_VERTICAL_PLATFORM:
		var position_values: Variant = object.get("position")
		if not _is_number_array(position_values, 2):
			return Rect2()
		return vertical_platform_corridor_rect(
			_point_from_payload(position_values)
		)

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


static func _behavior_preset(object: Dictionary) -> String:
	return str(
		object.get(
			"behavior_preset",
			LEVEL_BEHAVIOR_PRESETS.STANDARD_PRESET
		)
	)


func _payload_for_object(object: Dictionary) -> Variant:
	var object_type := str(object.get("type", ""))
	match object_type:
		TOOL_SOLID_RECT, TOOL_TOGGLE_PLATFORM:
			var rect_values: Variant = object.get("rect")
			if _is_number_array(rect_values, 4):
				return _duplicate_payload(rect_values)
	if POINT_OBJECT_TYPES.has(object_type):
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


func _logical_points_to_local(
	logical_points: PackedVector2Array,
	view_rect: Rect2
) -> PackedVector2Array:
	var local_points := PackedVector2Array()
	for point: Vector2 in logical_points:
		local_points.append(
			_logical_point_to_local(point, view_rect)
		)
	return local_points


func _rect_from_payload(payload: Array) -> Rect2:
	return Rect2(
		float(payload[0]),
		float(payload[1]),
		float(payload[2]),
		float(payload[3])
	)


func _point_from_payload(payload: Array) -> Vector2:
	return Vector2(float(payload[0]), float(payload[1]))


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

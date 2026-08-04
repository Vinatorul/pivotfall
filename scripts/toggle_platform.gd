class_name TogglePlatform
extends StaticBody2D

const MECHANISM_WARNING_PULSE := preload(
	"res://scripts/effects/mechanism_warning_pulse.gd"
)

signal toggled(is_active: bool)
signal toggle_blocked()
signal toggle_completed(is_active: bool)
signal bodies_ejected(count: int)

const ACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const ACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const INACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 0.12)
const INACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 0.28)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.8)
const BLOCKED_COLOR := Color(0.961, 0.306, 0.267, 0.92)
const DEFAULT_SIZE := Vector2(160.0, 20.0)
const TOP_EDGE_HEIGHT := 5.0
const EJECTION_CLEARANCE := 2.0
const EJECTION_HORIZONTAL_IMPULSE := 300.0
const EJECTION_VERTICAL_IMPULSE := -110.0
const MAX_EJECTION_BODIES := 512

@export var starts_active := true
@export var transition_time := 0.18
@export var blocked_feedback_time := 0.12

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_visual: Polygon2D = $Body
@onready var edge_visual: Polygon2D = $TopEdge
@onready var outline: Line2D = $Outline

var is_active := true
var is_transitioning := false
var pending_active := true
var platform_size := DEFAULT_SIZE
var is_vertical_wall := false
var warning_pulse := MECHANISM_WARNING_PULSE.new()


func _ready() -> void:
	_apply_geometry()
	collision_shape.one_way_collision = not is_vertical_wall
	warning_pulse.bind(outline)
	is_active = starts_active
	pending_active = is_active
	collision_shape.disabled = not is_active
	_apply_state_visual()


func _process(delta: float) -> void:
	warning_pulse.advance(delta)


func configure(
	rect: Rect2,
	active: bool,
	vertical_wall := false
) -> void:
	if is_inside_tree():
		push_error(
			"TogglePlatform must be configured before entering the tree."
		)
		return

	position = rect.get_center()
	platform_size = rect.size
	starts_active = active
	is_vertical_wall = vertical_wall


func request_toggle() -> bool:
	if is_transitioning:
		return false

	is_transitioning = true
	pending_active = not is_active
	_apply_warning_visual()
	warning_pulse.begin(transition_time)
	get_tree().create_timer(
		transition_time,
		false,
		is_vertical_wall
	).timeout.connect(
		_finish_toggle
	)
	return true


func _finish_toggle() -> void:
	warning_pulse.finish()
	if pending_active and is_vertical_wall:
		var ejection_plan := _build_ejection_plan()
		if not bool(ejection_plan.get("ok", false)):
			_begin_blocked_feedback()
			return
		_apply_ejection_plan(ejection_plan["entries"])
	is_active = pending_active
	collision_shape.set_deferred("disabled", not is_active)
	is_transitioning = false
	_apply_state_visual()
	toggled.emit(is_active)
	toggle_completed.emit(is_active)


func _build_ejection_plan() -> Dictionary:
	var entries: Array[Dictionary] = []
	for body: CharacterBody2D in _overlapping_character_bodies():
		var motion := _find_ejection_motion(body)
		if motion.is_zero_approx():
			return {
				"ok": false,
				"entries": [] as Array[Dictionary],
			}
		entries.append(
			{
				"body": body,
				"motion": motion,
			}
		)
	return {
		"ok": true,
		"entries": entries,
	}


func _overlapping_character_bodies() -> Array[CharacterBody2D]:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var bodies: Array[CharacterBody2D] = []
	var seen_ids := {}
	var intersections := get_world_2d().direct_space_state.intersect_shape(
		query,
		MAX_EJECTION_BODIES
	)
	for intersection: Dictionary in intersections:
		var body := intersection.get("collider") as CharacterBody2D
		if not is_instance_valid(body):
			continue
		var instance_id := body.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		bodies.append(body)
	return bodies


func _find_ejection_motion(body: CharacterBody2D) -> Vector2:
	var preferred_direction := _preferred_ejection_direction(body)
	for direction: float in [
		preferred_direction,
		-preferred_direction,
	]:
		var motion := _ejection_motion(body, direction)
		if not body.test_move(body.global_transform, motion):
			return motion
	return Vector2.ZERO


func _preferred_ejection_direction(body: CharacterBody2D) -> float:
	var center_offset := (
		body.global_position.x
		- collision_shape.global_position.x
	)
	if absf(center_offset) > 0.5:
		return signf(center_offset)
	if absf(body.velocity.x) > 0.01:
		return signf(body.velocity.x)
	return 1.0


func _ejection_motion(
	body: CharacterBody2D,
	direction: float
) -> Vector2:
	var wall_half_width := (
		platform_size.x
		* absf(global_scale.x)
		* 0.5
	)
	var target_x := (
		collision_shape.global_position.x
		+ direction
		* (
			wall_half_width
			+ _body_half_width(body)
			+ EJECTION_CLEARANCE
		)
	)
	return Vector2(target_x - body.global_position.x, 0.0)


func _body_half_width(body: CharacterBody2D) -> float:
	var half_width := 1.0
	for child: Node in body.get_children():
		var body_shape := child as CollisionShape2D
		if (
			not is_instance_valid(body_shape)
			or body_shape.disabled
		):
			continue
		if not is_instance_valid(body_shape.shape):
			continue
		var shape_bounds := body_shape.shape.get_rect()
		var shape_half_width := maxf(
			absf(shape_bounds.position.x),
			absf(shape_bounds.end.x)
		)
		var center_offset := absf(
			body_shape.global_position.x
			- body.global_position.x
		)
		half_width = maxf(
			half_width,
			center_offset
			+ shape_half_width
			* absf(body_shape.global_scale.x)
		)
	return half_width


func _apply_ejection_plan(entries: Array[Dictionary]) -> void:
	for entry: Dictionary in entries:
		var body := entry.get("body") as CharacterBody2D
		var motion: Vector2 = entry.get("motion", Vector2.ZERO)
		if not is_instance_valid(body) or motion.is_zero_approx():
			continue
		body.move_and_collide(motion)
		var direction := signf(motion.x)
		var impulse := Vector2(
			direction * EJECTION_HORIZONTAL_IMPULSE,
			EJECTION_VERTICAL_IMPULSE
		)
		if body.has_method("receive_impulse"):
			body.call("receive_impulse", impulse)
		else:
			body.velocity = impulse
	if not entries.is_empty():
		bodies_ejected.emit(entries.size())


func _begin_blocked_feedback() -> void:
	pending_active = is_active
	body_visual.color = BLOCKED_COLOR
	edge_visual.color = BLOCKED_COLOR
	outline.default_color = BLOCKED_COLOR
	warning_pulse.begin(blocked_feedback_time)
	get_tree().create_timer(
		blocked_feedback_time,
		false
	).timeout.connect(_finish_blocked_feedback)


func _finish_blocked_feedback() -> void:
	warning_pulse.finish()
	is_transitioning = false
	_apply_state_visual()
	toggle_blocked.emit()
	toggle_completed.emit(is_active)


func _apply_state_visual() -> void:
	body_visual.color = ACTIVE_BODY_COLOR if is_active else INACTIVE_BODY_COLOR
	edge_visual.color = ACTIVE_EDGE_COLOR if is_active else INACTIVE_EDGE_COLOR
	outline.default_color = Color(OUTLINE_COLOR, 0.0 if is_active else 0.85)


func _apply_warning_visual() -> void:
	body_visual.color = WARNING_COLOR
	edge_visual.color = WARNING_COLOR
	outline.default_color = WARNING_COLOR


func _apply_geometry() -> void:
	var half_size := platform_size * 0.5
	body_visual.polygon = PackedVector2Array(
		[
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		]
	)
	if is_vertical_wall:
		var edge_right := minf(
			-half_size.x + TOP_EDGE_HEIGHT,
			half_size.x
		)
		edge_visual.polygon = PackedVector2Array(
			[
				Vector2(-half_size.x, -half_size.y),
				Vector2(edge_right, -half_size.y),
				Vector2(edge_right, half_size.y),
				Vector2(-half_size.x, half_size.y),
			]
		)
	else:
		var edge_bottom := minf(
			-half_size.y + TOP_EDGE_HEIGHT,
			half_size.y
		)
		edge_visual.polygon = PackedVector2Array(
			[
				Vector2(-half_size.x, -half_size.y),
				Vector2(half_size.x, -half_size.y),
				Vector2(half_size.x, edge_bottom),
				Vector2(-half_size.x, edge_bottom),
			]
		)
	outline.points = PackedVector2Array(
		[
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		]
	)
	var shape := RectangleShape2D.new()
	shape.size = platform_size
	collision_shape.shape = shape

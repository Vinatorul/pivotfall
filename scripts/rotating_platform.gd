class_name RotatingPlatform
extends StaticBody2D

signal toggled(is_horizontal: bool)

const HORIZONTAL_ROTATION := 0.0
const VERTICAL_ROTATION := -PI / 2.0
const BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.9)

@export var starts_horizontal := true
@export var warning_time := 0.3
@export var rotation_time := 0.38
@export var clearance_time := 0.12
@export var evacuation_horizontal_impulse := 850.0
@export var evacuation_vertical_impulse := -260.0
@export_range(-1.0, 1.0, 2.0) var bridge_safe_direction := -1.0
@export_range(-1.0, 1.0, 2.0) var wall_safe_direction := 1.0

@onready var visual_pivot: Node2D = $VisualPivot
@onready var body_visual: Polygon2D = $VisualPivot/Body
@onready var edge_visual: Polygon2D = $VisualPivot/TopEdge
@onready var outline: Line2D = $VisualPivot/Outline
@onready var target_preview: Node2D = $TargetPreview
@onready var horizontal_collision: CollisionShape2D = $HorizontalCollision
@onready var vertical_collision: CollisionShape2D = $VerticalCollision
@onready var horizontal_clearance_area: Area2D = $HorizontalClearanceArea
@onready var vertical_clearance_area: Area2D = $VerticalClearanceArea
@onready var horizontal_target_area: Area2D = $HorizontalTargetArea
@onready var vertical_target_area: Area2D = $VerticalTargetArea
@onready var safe_left: Marker2D = $SafeLeft
@onready var safe_right: Marker2D = $SafeRight

var is_horizontal := true
var pending_horizontal := true
var is_transitioning := false


func _ready() -> void:
	is_horizontal = starts_horizontal
	pending_horizontal = is_horizontal
	visual_pivot.rotation = _rotation_for(is_horizontal)
	horizontal_collision.disabled = not is_horizontal
	vertical_collision.disabled = is_horizontal
	target_preview.visible = false
	_apply_idle_visual()


func request_toggle() -> bool:
	if is_transitioning:
		return false

	is_transitioning = true
	pending_horizontal = not is_horizontal
	_apply_warning_visual()
	_run_transition()
	return true


func _run_transition() -> void:
	await get_tree().create_timer(warning_time).timeout
	if not is_inside_tree():
		return

	_evacuate_bodies(_get_affected_bodies())
	horizontal_collision.set_deferred("disabled", true)
	vertical_collision.set_deferred("disabled", true)
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	var rotation_tween := create_tween()
	rotation_tween.set_trans(Tween.TRANS_SINE)
	rotation_tween.set_ease(Tween.EASE_IN_OUT)
	rotation_tween.tween_property(
		visual_pivot,
		"rotation",
		_rotation_for(pending_horizontal),
		rotation_time
	)
	await rotation_tween.finished
	if not is_inside_tree():
		return

	for _attempt in 2:
		var target_bodies := _get_target_bodies()
		if target_bodies.is_empty():
			break

		_evacuate_bodies(target_bodies)
		await get_tree().create_timer(clearance_time).timeout
		if not is_inside_tree():
			return

	var trapped_bodies := _get_target_bodies()
	if not trapped_bodies.is_empty():
		_relocate_bodies_to_safety(trapped_bodies)
		await get_tree().physics_frame
		if not is_inside_tree():
			return

	horizontal_collision.set_deferred("disabled", not pending_horizontal)
	vertical_collision.set_deferred("disabled", pending_horizontal)
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	is_horizontal = pending_horizontal
	is_transitioning = false
	target_preview.visible = false
	_apply_idle_visual()
	toggled.emit(is_horizontal)


func _get_affected_bodies() -> Array[Node2D]:
	var affected_bodies: Dictionary[int, Node2D] = {}

	for area: Area2D in [
		horizontal_clearance_area,
		vertical_clearance_area,
	]:
		for body: Node2D in area.get_overlapping_bodies():
			if body.has_method("receive_impulse"):
				affected_bodies[body.get_instance_id()] = body

	var bodies: Array[Node2D] = []
	bodies.assign(affected_bodies.values())
	return bodies


func _get_target_bodies() -> Array[Node2D]:
	var target_area := (
		horizontal_target_area
		if pending_horizontal
		else vertical_target_area
	)
	var bodies: Array[Node2D] = []

	for body: Node2D in target_area.get_overlapping_bodies():
		if body.has_method("receive_impulse"):
			bodies.append(body)

	return bodies


func _evacuate_bodies(bodies: Array[Node2D]) -> void:
	var push_direction := _safe_direction_for_target()

	for body: Node2D in bodies:
		body.call(
			"receive_impulse",
			Vector2(
				push_direction * evacuation_horizontal_impulse,
				evacuation_vertical_impulse
			)
		)


func _relocate_bodies_to_safety(bodies: Array[Node2D]) -> void:
	var safe_marker := (
		safe_left
		if _safe_direction_for_target() < 0.0
		else safe_right
	)

	for body: Node2D in bodies:
		body.global_position = safe_marker.global_position

		if body is CharacterBody2D:
			body.velocity = Vector2.ZERO


func _safe_direction_for_target() -> float:
	return bridge_safe_direction if pending_horizontal else wall_safe_direction


func _rotation_for(horizontal: bool) -> float:
	return HORIZONTAL_ROTATION if horizontal else VERTICAL_ROTATION


func _apply_idle_visual() -> void:
	body_visual.color = BODY_COLOR
	edge_visual.color = EDGE_COLOR
	outline.default_color = OUTLINE_COLOR


func _apply_warning_visual() -> void:
	body_visual.color = WARNING_COLOR
	edge_visual.color = WARNING_COLOR
	outline.default_color = WARNING_COLOR
	target_preview.rotation = _rotation_for(pending_horizontal)
	target_preview.visible = true

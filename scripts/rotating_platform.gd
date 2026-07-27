class_name RotatingPlatform
extends StaticBody2D

signal toggled(is_ready: bool)

const BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.9)

@export var warning_time := 0.3
@export var swing_out_time := 0.18
@export var swing_hold_time := 0.08
@export var return_time := 0.28
@export var clearance_time := 0.1
@export var clearance_attempts := 2
@export var swing_angle_degrees := 55.0
@export_range(-1.0, 1.0, 2.0) var launch_direction := 1.0
@export var launch_impulse := Vector2(700.0, -280.0)
@export var clearance_impulse := Vector2(420.0, -360.0)

@onready var visual_pivot: Node2D = $VisualPivot
@onready var body_visual: Polygon2D = $VisualPivot/Body
@onready var edge_visual: Polygon2D = $VisualPivot/TopEdge
@onready var outline: Line2D = $VisualPivot/Outline
@onready var target_preview: Node2D = $TargetPreview
@onready var launch_guide: Line2D = $LaunchGuide
@onready var arrow_head: Polygon2D = $ArrowHead
@onready var rest_collision: CollisionShape2D = $RestCollision
@onready var launch_area: Area2D = $LaunchArea
@onready var rest_target_area: Area2D = $RestTargetArea
@onready var safe_above: Marker2D = $SafeAbove

var is_transitioning := false


func _ready() -> void:
	visual_pivot.rotation = 0.0
	launch_guide.scale.x = launch_direction
	arrow_head.scale.x = launch_direction
	rest_collision.disabled = false
	target_preview.visible = false
	_apply_idle_visual()


func request_toggle() -> bool:
	if is_transitioning:
		return false

	is_transitioning = true
	_apply_warning_visual()
	_run_launch_cycle()
	return true


func _run_launch_cycle() -> void:
	await get_tree().create_timer(warning_time, false).timeout
	if not is_inside_tree():
		return

	_apply_impulse(_get_bodies_in(launch_area), _directed(launch_impulse))
	rest_collision.set_deferred("disabled", true)
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	var swing_tween := create_tween()
	swing_tween.set_trans(Tween.TRANS_BACK)
	swing_tween.set_ease(Tween.EASE_OUT)
	swing_tween.tween_property(
		visual_pivot,
		"rotation",
		deg_to_rad(-swing_angle_degrees * launch_direction),
		swing_out_time
	)
	await swing_tween.finished
	if not is_inside_tree():
		return

	await get_tree().create_timer(swing_hold_time, false).timeout
	if not is_inside_tree():
		return

	var return_tween := create_tween()
	return_tween.set_trans(Tween.TRANS_SINE)
	return_tween.set_ease(Tween.EASE_IN_OUT)
	return_tween.tween_property(
		visual_pivot,
		"rotation",
		0.0,
		return_time
	)
	await return_tween.finished
	if not is_inside_tree():
		return

	for _attempt in clearance_attempts:
		var blocking_bodies := _get_bodies_in(rest_target_area)
		if blocking_bodies.is_empty():
			break

		_apply_impulse(blocking_bodies, _directed(clearance_impulse))
		await get_tree().create_timer(clearance_time, false).timeout
		if not is_inside_tree():
			return

	var trapped_bodies := _get_bodies_in(rest_target_area)
	if not trapped_bodies.is_empty():
		for body: Node2D in trapped_bodies:
			body.global_position = safe_above.global_position
			if body is CharacterBody2D:
				body.velocity = Vector2.ZERO

		await get_tree().physics_frame
		if not is_inside_tree():
			return

	rest_collision.set_deferred("disabled", false)
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	is_transitioning = false
	target_preview.visible = false
	_apply_idle_visual()
	toggled.emit(true)


func _get_bodies_in(area: Area2D) -> Array[Node2D]:
	var bodies: Array[Node2D] = []

	for body: Node2D in area.get_overlapping_bodies():
		if body.has_method("receive_impulse"):
			bodies.append(body)

	return bodies


func _apply_impulse(bodies: Array[Node2D], impulse: Vector2) -> void:
	for body: Node2D in bodies:
		body.call("receive_impulse", impulse)


func _directed(impulse: Vector2) -> Vector2:
	return Vector2(absf(impulse.x) * launch_direction, impulse.y)


func _apply_idle_visual() -> void:
	body_visual.color = BODY_COLOR
	edge_visual.color = EDGE_COLOR
	outline.default_color = OUTLINE_COLOR


func _apply_warning_visual() -> void:
	body_visual.color = WARNING_COLOR
	edge_visual.color = WARNING_COLOR
	outline.default_color = WARNING_COLOR
	target_preview.rotation = deg_to_rad(
		-swing_angle_degrees * launch_direction
	)
	target_preview.visible = true

class_name TogglePlatform
extends StaticBody2D

signal toggled(is_active: bool)

const ACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const ACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const INACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 0.12)
const INACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 0.28)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.8)

@export var starts_active := true
@export var transition_time := 0.18

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var body_visual: Polygon2D = $Body
@onready var edge_visual: Polygon2D = $TopEdge
@onready var outline: Line2D = $Outline

var is_active := true
var is_transitioning := false
var pending_active := true


func _ready() -> void:
	is_active = starts_active
	pending_active = is_active
	collision_shape.disabled = not is_active
	_apply_state_visual()


func request_toggle() -> bool:
	if is_transitioning:
		return false

	is_transitioning = true
	pending_active = not is_active
	_apply_warning_visual()
	get_tree().create_timer(transition_time, false).timeout.connect(
		_finish_toggle
	)
	return true


func _finish_toggle() -> void:
	is_active = pending_active
	collision_shape.set_deferred("disabled", not is_active)
	is_transitioning = false
	_apply_state_visual()
	toggled.emit(is_active)


func _apply_state_visual() -> void:
	body_visual.color = ACTIVE_BODY_COLOR if is_active else INACTIVE_BODY_COLOR
	edge_visual.color = ACTIVE_EDGE_COLOR if is_active else INACTIVE_EDGE_COLOR
	outline.default_color = Color(OUTLINE_COLOR, 0.0 if is_active else 0.85)


func _apply_warning_visual() -> void:
	body_visual.color = WARNING_COLOR
	edge_visual.color = WARNING_COLOR
	outline.default_color = WARNING_COLOR

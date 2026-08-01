class_name VerticalPlatform
extends Node2D

const MECHANISM_WARNING_PULSE := preload(
	"res://scripts/effects/mechanism_warning_pulse.gd"
)

signal toggled(is_lowered: bool)

const BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.9)

@export var travel_offset := Vector2(0.0, 136.0)
@export var warning_time := 0.25
@export var travel_time := 1.0
@export var starts_lowered := false

@onready var track: Line2D = $Track
@onready var lower_stop: Node2D = $LowerStop
@onready var target_preview: Node2D = $TargetPreview
@onready var platform: AnimatableBody2D = $Platform
@onready var body_visual: Polygon2D = $Platform/Body
@onready var edge_visual: Polygon2D = $Platform/TopEdge
@onready var outline: Line2D = $Platform/Outline

var is_lowered := false
var is_transitioning := false
var is_moving := false
var pending_lowered := false
var movement_elapsed := 0.0
var movement_start := Vector2.ZERO
var movement_target := Vector2.ZERO
var warning_pulse := MECHANISM_WARNING_PULSE.new()


func _ready() -> void:
	warning_pulse.bind(outline)
	is_lowered = starts_lowered
	pending_lowered = is_lowered
	platform.position = travel_offset if is_lowered else Vector2.ZERO
	track.points = PackedVector2Array([Vector2.ZERO, travel_offset])
	lower_stop.position = travel_offset
	target_preview.visible = false
	_apply_idle_visual()


func _process(delta: float) -> void:
	warning_pulse.advance(delta)


func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	var effective_travel_time := maxf(travel_time, 0.001)
	movement_elapsed = minf(
		movement_elapsed + delta,
		effective_travel_time
	)
	var linear_progress := movement_elapsed / effective_travel_time
	var eased_progress := smoothstep(0.0, 1.0, linear_progress)
	platform.position = movement_start.lerp(
		movement_target,
		eased_progress
	)

	if linear_progress >= 1.0:
		_finish_travel()


func request_toggle() -> bool:
	if is_transitioning:
		return false

	is_transitioning = true
	pending_lowered = not is_lowered
	movement_target = (
		travel_offset
		if pending_lowered
		else Vector2.ZERO
	)
	target_preview.position = movement_target
	target_preview.visible = true
	_apply_warning_visual()
	warning_pulse.begin(warning_time)
	get_tree().create_timer(warning_time, false).timeout.connect(
		_begin_travel
	)
	return true


func _begin_travel() -> void:
	if not is_inside_tree():
		return

	warning_pulse.finish()
	movement_start = platform.position
	movement_elapsed = 0.0
	is_moving = true


func _finish_travel() -> void:
	platform.position = movement_target
	is_moving = false
	is_lowered = pending_lowered
	is_transitioning = false
	target_preview.visible = false
	_apply_idle_visual()
	toggled.emit(is_lowered)


func _apply_idle_visual() -> void:
	body_visual.color = BODY_COLOR
	edge_visual.color = EDGE_COLOR
	outline.default_color = OUTLINE_COLOR


func _apply_warning_visual() -> void:
	body_visual.color = WARNING_COLOR
	edge_visual.color = WARNING_COLOR
	outline.default_color = WARNING_COLOR

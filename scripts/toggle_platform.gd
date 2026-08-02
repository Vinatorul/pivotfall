class_name TogglePlatform
extends StaticBody2D

const MECHANISM_WARNING_PULSE := preload(
	"res://scripts/effects/mechanism_warning_pulse.gd"
)

signal toggled(is_active: bool)

const ACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 1.0)
const ACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const INACTIVE_BODY_COLOR := Color(0.278, 0.345, 0.459, 0.12)
const INACTIVE_EDGE_COLOR := Color(0.392, 0.455, 0.584, 0.28)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.85)
const WARNING_COLOR := Color(0.925, 0.58, 0.267, 0.8)
const DEFAULT_SIZE := Vector2(160.0, 20.0)
const TOP_EDGE_HEIGHT := 5.0

@export var starts_active := true
@export var transition_time := 0.18

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
	get_tree().create_timer(transition_time, false).timeout.connect(
		_finish_toggle
	)
	return true


func _finish_toggle() -> void:
	warning_pulse.finish()
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

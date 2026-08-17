class_name SpikeTrap
extends Area2D

const DEFAULT_SIZE := Vector2(120.0, 20.0)
const TARGET_TOOTH_WIDTH := 20.0
const BASE_HEIGHT := 4.0
const SPIKE_COLOR := Color(0.961, 0.306, 0.267, 1.0)
const BASE_COLOR := Color(0.635, 0.18, 0.239, 1.0)

@onready var spikes_visual: Polygon2D = $Spikes
@onready var base_visual: Polygon2D = $Base
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var trap_size := DEFAULT_SIZE


func configure(rect: Rect2) -> void:
	if is_inside_tree():
		push_error("SpikeTrap must be configured before entering the tree.")
		return

	position = rect.get_center()
	trap_size = rect.size


func _ready() -> void:
	_apply_geometry()


func _apply_geometry() -> void:
	var half_size := trap_size * 0.5
	var tooth_count := maxi(
		int(round(trap_size.x / TARGET_TOOTH_WIDTH)),
		1
	)
	var tooth_width := trap_size.x / float(tooth_count)
	var spike_points := PackedVector2Array(
		[Vector2(-half_size.x, half_size.y)]
	)
	for tooth_index in tooth_count:
		var tooth_left := -half_size.x + float(tooth_index) * tooth_width
		spike_points.append(
			Vector2(tooth_left + tooth_width * 0.5, -half_size.y)
		)
		spike_points.append(Vector2(tooth_left + tooth_width, half_size.y))
	spikes_visual.polygon = spike_points
	spikes_visual.color = SPIKE_COLOR

	var base_top := half_size.y - minf(BASE_HEIGHT, trap_size.y)
	base_visual.polygon = PackedVector2Array(
		[
			Vector2(-half_size.x, base_top),
			Vector2(half_size.x, base_top),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		]
	)
	base_visual.color = BASE_COLOR

	var shape := RectangleShape2D.new()
	shape.size = trap_size
	collision_shape.shape = shape

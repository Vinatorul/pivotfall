class_name LevelSolidRect
extends StaticBody2D

const TOP_EDGE_HEIGHT := 6.0
const ONE_WAY_COLLISION_MARGIN := 4.0
const SOLID_BODY_COLOR := Color(0.235, 0.302, 0.416, 1.0)
const SOLID_EDGE_COLOR := Color(0.392, 0.455, 0.584, 1.0)
const ONE_WAY_BODY_COLOR := Color(0.267, 0.365, 0.498, 1.0)
const ONE_WAY_EDGE_COLOR := Color(0.439, 0.827, 0.816, 0.9)

var rect_size := Vector2.ZERO
var is_one_way := false


func configure(rect: Rect2, one_way := false) -> void:
	position = rect.get_center()
	rect_size = rect.size
	is_one_way = one_way


func _ready() -> void:
	var half_size := rect_size * 0.5
	var body_visual := $Body as Polygon2D
	var top_edge := $TopEdge as Polygon2D
	var collision_shape := $CollisionShape2D as CollisionShape2D
	var shape := RectangleShape2D.new()

	body_visual.color = (
		ONE_WAY_BODY_COLOR if is_one_way else SOLID_BODY_COLOR
	)
	top_edge.color = (
		ONE_WAY_EDGE_COLOR if is_one_way else SOLID_EDGE_COLOR
	)
	body_visual.polygon = PackedVector2Array(
		[
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		]
	)

	var edge_height := minf(TOP_EDGE_HEIGHT, rect_size.y)
	top_edge.polygon = PackedVector2Array(
		[
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y + edge_height),
			Vector2(-half_size.x, -half_size.y + edge_height),
		]
	)

	shape.size = rect_size
	collision_shape.shape = shape
	collision_shape.one_way_collision = is_one_way
	if is_one_way:
		collision_shape.one_way_collision_margin = (
			ONE_WAY_COLLISION_MARGIN
		)

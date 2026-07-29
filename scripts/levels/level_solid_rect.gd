class_name LevelSolidRect
extends StaticBody2D

const TOP_EDGE_HEIGHT := 6.0

var rect_size := Vector2.ZERO


func configure(rect: Rect2) -> void:
	position = rect.get_center()
	rect_size = rect.size


func _ready() -> void:
	var half_size := rect_size * 0.5
	var body_visual := $Body as Polygon2D
	var top_edge := $TopEdge as Polygon2D
	var collision_shape := $CollisionShape2D as CollisionShape2D
	var shape := RectangleShape2D.new()

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

class_name Hinge
extends Area2D

@export_node_path("TogglePlatform") var target_path: NodePath
@export var cooldown := 0.35

@onready var target: Node = get_node_or_null(target_path)
@onready var outer_visual: Polygon2D = $Outer
@onready var inner_visual: Polygon2D = $Inner

var is_ready := true


func receive_impulse(_impulse: Vector2) -> void:
	if (
		not is_ready
		or not is_instance_valid(target)
		or not target.has_method("request_toggle")
	):
		return

	if not bool(target.call("request_toggle")):
		return

	is_ready = false
	outer_visual.color = Color(1.0, 0.82, 0.49, 1.0)
	inner_visual.color = Color(1.0, 0.965, 0.835, 1.0)
	get_tree().create_timer(cooldown).timeout.connect(_unlock)


func _unlock() -> void:
	is_ready = true
	outer_visual.color = Color(0.925, 0.58, 0.267, 1.0)
	inner_visual.color = Color(0.302, 0.125, 0.098, 1.0)

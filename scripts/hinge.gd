class_name Hinge
extends Area2D

@export_node_path var target_path: NodePath
@export var cooldown := 0.35

@onready var outer_visual: Polygon2D = $Outer
@onready var inner_visual: Polygon2D = $Inner

var target: Node
var is_ready := true
var cooldown_finished := true
var target_finished := true


func _ready() -> void:
	if not is_instance_valid(target) and not target_path.is_empty():
		target = get_node_or_null(target_path)


func configure_target(target_node: Node) -> void:
	if is_inside_tree():
		push_error(
			"Hinge target must be configured before entering the tree."
		)
		return
	target = target_node


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
	cooldown_finished = false
	target_finished = not target.has_signal("toggled")
	outer_visual.color = Color(1.0, 0.82, 0.49, 1.0)
	inner_visual.color = Color(1.0, 0.965, 0.835, 1.0)

	if not target_finished:
		target.connect("toggled", _on_target_toggled, CONNECT_ONE_SHOT)

	get_tree().create_timer(cooldown, false).timeout.connect(
		_on_cooldown_finished
	)


func _on_cooldown_finished() -> void:
	cooldown_finished = true
	_try_unlock()


func _on_target_toggled(_is_active: bool) -> void:
	target_finished = true
	_try_unlock()


func _try_unlock() -> void:
	if cooldown_finished and target_finished:
		_unlock()


func _unlock() -> void:
	is_ready = true
	outer_visual.color = Color(0.925, 0.58, 0.267, 1.0)
	inner_visual.color = Color(0.302, 0.125, 0.098, 1.0)

class_name PressurePlate
extends Area2D

signal pressed_changed(is_pressed: bool)

const DEFAULT_SIZE := Vector2(80.0, 20.0)
const BASE_COLOR := Color(0.098, 0.145, 0.227, 1.0)
const RELEASED_COLOR := Color(0.314, 0.745, 0.698, 1.0)
const PRESSED_COLOR := Color(1.0, 0.82, 0.49, 1.0)
const OUTLINE_COLOR := Color(0.439, 0.827, 0.816, 0.9)

@onready var base_visual: Polygon2D = $Base
@onready var pad_visual: Polygon2D = $Pad
@onready var outline: Line2D = $Outline
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var target: TogglePlatform
var active_while_pressed := true
var is_pressed := false
var plate_size := DEFAULT_SIZE
var occupied_instance_ids := {}


func configure(rect: Rect2, active: bool) -> void:
	if is_inside_tree():
		push_error("PressurePlate must be configured before entering the tree.")
		return
	position = rect.get_center()
	plate_size = rect.size
	active_while_pressed = active


func configure_target(target_node: TogglePlatform) -> void:
	target = target_node
	if is_inside_tree():
		_sync_target_when_ready()


func occupant_count() -> int:
	return occupied_instance_ids.size()


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_geometry()
	_apply_pressed_visual()
	_sync_target_when_ready()


func _sync_target_when_ready() -> void:
	if not is_instance_valid(target):
		return
	if target.is_node_ready():
		_request_target_state()
		return
	if not target.ready.is_connected(_request_target_state):
		target.ready.connect(_request_target_state, CONNECT_ONE_SHOT)


func _on_body_entered(body: Node2D) -> void:
	if not _is_valid_occupant(body):
		return
	var instance_id := body.get_instance_id()
	if occupied_instance_ids.has(instance_id):
		return
	occupied_instance_ids[instance_id] = true
	_connect_tree_exit(body, instance_id)
	if occupied_instance_ids.size() == 1:
		_set_pressed(true)


func _on_body_exited(body: Node2D) -> void:
	_remove_occupant(body.get_instance_id())


func _connect_tree_exit(body: Node2D, instance_id: int) -> void:
	var callback := _on_occupant_tree_exiting.bind(instance_id)
	if not body.tree_exiting.is_connected(callback):
		body.tree_exiting.connect(callback, CONNECT_ONE_SHOT)


func _on_occupant_tree_exiting(instance_id: int) -> void:
	_remove_occupant(instance_id)


func _remove_occupant(instance_id: int) -> void:
	if not occupied_instance_ids.erase(instance_id):
		return
	if occupied_instance_ids.is_empty():
		_set_pressed(false)


func _set_pressed(pressed: bool) -> void:
	if is_pressed == pressed:
		return
	is_pressed = pressed
	_apply_pressed_visual()
	_request_target_state()
	pressed_changed.emit(is_pressed)


func _request_target_state() -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	var desired := active_while_pressed if is_pressed else not active_while_pressed
	target.request_active(desired)


func _is_valid_occupant(body: Node2D) -> bool:
	return body.is_in_group("player") or body.is_in_group("enemies")


func _apply_pressed_visual() -> void:
	if not is_instance_valid(pad_visual):
		return
	pad_visual.position.y = 4.0 if is_pressed else 0.0
	pad_visual.color = PRESSED_COLOR if is_pressed else RELEASED_COLOR


func _apply_geometry() -> void:
	var half_size := plate_size * 0.5
	base_visual.polygon = _rect_points(Rect2(-half_size, plate_size))
	var pad_rect := Rect2(
		Vector2(-half_size.x + 4.0, -half_size.y + 2.0),
		Vector2(maxf(plate_size.x - 8.0, 1.0), 8.0)
	)
	pad_visual.polygon = _rect_points(pad_rect)
	outline.points = base_visual.polygon
	var shape := RectangleShape2D.new()
	shape.size = plate_size
	collision_shape.shape = shape


func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]
	)

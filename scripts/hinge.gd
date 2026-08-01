class_name Hinge
extends Area2D

const READY_OUTER_COLOR := Color(0.925, 0.58, 0.267, 1.0)
const READY_INNER_COLOR := Color(0.302, 0.125, 0.098, 1.0)
const ACCEPTED_OUTER_COLOR := Color(1.0, 0.82, 0.49, 1.0)
const ACCEPTED_INNER_COLOR := Color(1.0, 0.965, 0.835, 1.0)

@export_node_path var target_path: NodePath
@export var cooldown := 0.35
@export var press_visual_time := 0.18
@export var press_twist_degrees := 12.0
@export var press_squash := 0.16
@export var locked_pulse_scale := 0.06
@export var locked_pulse_frequency := 3.2

@onready var outer_visual: Polygon2D = $Outer
@onready var inner_visual: Polygon2D = $Inner

var target: Node
var is_ready := true
var cooldown_finished := true
var target_finished := true
var press_visual_time_remaining := 0.0
var press_visual_direction := 1.0
var locked_visual_cycle := 0.0
var outer_base_position := Vector2.ZERO
var outer_base_rotation := 0.0
var outer_base_scale := Vector2.ONE
var inner_base_position := Vector2.ZERO
var inner_base_rotation := 0.0
var inner_base_scale := Vector2.ONE


func _ready() -> void:
	outer_base_position = outer_visual.position
	outer_base_rotation = outer_visual.rotation
	outer_base_scale = outer_visual.scale
	inner_base_position = inner_visual.position
	inner_base_rotation = inner_visual.rotation
	inner_base_scale = inner_visual.scale
	_apply_press_visual()

	if not is_instance_valid(target) and not target_path.is_empty():
		target = get_node_or_null(target_path)


func _process(delta: float) -> void:
	if press_visual_time_remaining > 0.0:
		press_visual_time_remaining = maxf(
			press_visual_time_remaining - delta,
			0.0
		)
	if not is_ready:
		locked_visual_cycle = fmod(
			locked_visual_cycle + delta * locked_pulse_frequency,
			1.0
		)
	_apply_press_visual()


func configure_target(target_node: Node) -> void:
	if is_inside_tree():
		push_error(
			"Hinge target must be configured before entering the tree."
		)
		return
	target = target_node


func receive_impulse(impulse: Vector2) -> void:
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
	outer_visual.color = ACCEPTED_OUTER_COLOR
	inner_visual.color = ACCEPTED_INNER_COLOR
	_start_press_visual(impulse)

	if not target_finished:
		target.connect("toggled", _on_target_toggled, CONNECT_ONE_SHOT)

	get_tree().create_timer(cooldown, false).timeout.connect(
		_on_cooldown_finished
	)


func _on_cooldown_finished() -> void:
	cooldown_finished = true
	press_visual_time_remaining = 0.0
	_apply_press_visual()
	_try_unlock()


func _on_target_toggled(_is_active: bool) -> void:
	target_finished = true
	_try_unlock()


func _try_unlock() -> void:
	if cooldown_finished and target_finished:
		_unlock()


func _unlock() -> void:
	is_ready = true
	outer_visual.color = READY_OUTER_COLOR
	inner_visual.color = READY_INNER_COLOR
	press_visual_time_remaining = 0.0
	locked_visual_cycle = 0.0
	_apply_press_visual()


func _start_press_visual(impulse: Vector2) -> void:
	press_visual_direction = signf(impulse.x)
	if is_zero_approx(press_visual_direction):
		press_visual_direction = 1.0
	press_visual_time_remaining = maxf(press_visual_time, 0.001)
	locked_visual_cycle = 0.0
	_apply_press_visual()


func _apply_press_visual() -> void:
	var press_strength := 0.0
	if press_visual_time_remaining > 0.0:
		var duration := maxf(press_visual_time, 0.001)
		var remaining_ratio := clampf(
			press_visual_time_remaining / duration,
			0.0,
			1.0
		)
		press_strength = smoothstep(0.0, 1.0, remaining_ratio)

	var pulse_strength := 0.0
	if not is_ready:
		pulse_strength = (
			0.5
			+ 0.5 * sin(locked_visual_cycle * TAU)
		) * locked_pulse_scale

	var twist := deg_to_rad(press_twist_degrees)
	outer_visual.position = outer_base_position + Vector2(
		press_visual_direction * 2.5 * press_strength,
		1.5 * press_strength
	)
	outer_visual.rotation = (
		outer_base_rotation
		+ twist * press_visual_direction * press_strength
	)
	outer_visual.scale = outer_base_scale * Vector2(
		1.0 + press_squash * press_strength,
		1.0 - press_squash * press_strength
	)
	inner_visual.position = inner_base_position + Vector2(
		press_visual_direction * press_strength,
		0.5 * press_strength
	)
	inner_visual.rotation = (
		inner_base_rotation
		- twist * 0.65 * press_visual_direction * press_strength
	)
	inner_visual.scale = inner_base_scale * Vector2(
		1.0 - press_squash * 0.5 * press_strength + pulse_strength,
		1.0 + press_squash * 0.5 * press_strength + pulse_strength
	)

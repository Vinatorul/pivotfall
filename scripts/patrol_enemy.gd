class_name PatrolEnemy
extends CharacterBody2D

@export var patrol_speed := 85.0
@export var knockback_lock_time := 0.28
@export var knockback_drag := 420.0
@export var maximum_fall_speed := 900.0

@onready var visual: Node2D = $Visual
@onready var edge_probe: RayCast2D = $EdgeProbe

var gravity: float = float(
	ProjectSettings.get_setting("physics/2d/default_gravity", 1500.0)
)
var patrol_direction := -1.0
var knockback_time_remaining := 0.0
var hit_flash_time_remaining := 0.0


func _ready() -> void:
	_sync_direction()


func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	if knockback_time_remaining > 0.0:
		knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	else:
		if is_on_floor() and not edge_probe.is_colliding():
			_turn_around()
		velocity.x = patrol_direction * patrol_speed

	move_and_slide()

	if is_on_wall():
		_turn_around()


func receive_impulse(impulse: Vector2) -> void:
	velocity = impulse
	knockback_time_remaining = knockback_lock_time
	hit_flash_time_remaining = 0.12

	if not is_zero_approx(impulse.x):
		patrol_direction = signf(impulse.x)
		_sync_direction()


func _turn_around() -> void:
	patrol_direction *= -1.0
	_sync_direction()


func _sync_direction() -> void:
	visual.scale.x = patrol_direction
	edge_probe.target_position.x = absf(edge_probe.target_position.x) * patrol_direction


func _update_hit_flash(delta: float) -> void:
	hit_flash_time_remaining = maxf(hit_flash_time_remaining - delta, 0.0)
	visual.modulate = (
		Color(1.0, 0.82, 0.62)
		if hit_flash_time_remaining > 0.0
		else Color.WHITE
	)

class_name PatrolEnemy
extends CharacterBody2D

@export var patrol_speed := 85.0
@export var knockback_lock_time := 0.28
@export var knockback_drag := 420.0
@export var maximum_fall_speed := 900.0

@export_category("Impact feedback")
@export_range(0.01, 0.5, 0.01) var hit_flash_duration := 0.12
@export_range(0.0, 0.4, 0.01) var hit_squash_y := 0.14

@onready var visual: Node2D = $Visual
@onready var edge_probe: RayCast2D = $EdgeProbe

var gravity: float = float(
	ProjectSettings.get_setting("physics/2d/default_gravity", 1500.0)
)
@export_range(-1.0, 1.0, 2.0) var patrol_direction := -1.0
var knockback_time_remaining := 0.0
var hit_flash_time_remaining := 0.0
var impact_freeze_frames_remaining := 0
var base_visual_modulate := Color.WHITE
var base_visual_scale_y := 1.0


func _ready() -> void:
	base_visual_modulate = visual.modulate
	base_visual_scale_y = visual.scale.y
	_sync_direction()


func _physics_process(delta: float) -> void:
	if _consume_impact_freeze_frame():
		return

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
	hit_flash_time_remaining = hit_flash_duration
	_apply_hit_visual()

	if not is_zero_approx(impulse.x):
		patrol_direction = signf(impulse.x)
		_sync_direction()


func begin_impact_freeze(frames: int = 3) -> void:
	impact_freeze_frames_remaining = maxi(
		impact_freeze_frames_remaining,
		frames
	)


func is_impact_frozen() -> bool:
	return impact_freeze_frames_remaining > 0


func _turn_around() -> void:
	patrol_direction *= -1.0
	_sync_direction()


func _sync_direction() -> void:
	visual.scale.x = patrol_direction
	edge_probe.target_position.x = absf(edge_probe.target_position.x) * patrol_direction


func _update_hit_flash(delta: float) -> void:
	hit_flash_time_remaining = maxf(hit_flash_time_remaining - delta, 0.0)
	_apply_hit_visual()


func _apply_hit_visual() -> void:
	var intensity := clampf(
		hit_flash_time_remaining / maxf(hit_flash_duration, 0.001),
		0.0,
		1.0
	)
	visual.modulate = base_visual_modulate.lerp(
		Color(1.0, 0.82, 0.62, 1.0),
		intensity
	)
	visual.scale.y = base_visual_scale_y * (
		1.0 - hit_squash_y * intensity
	)


func _consume_impact_freeze_frame() -> bool:
	if impact_freeze_frames_remaining <= 0:
		return false
	impact_freeze_frames_remaining -= 1
	return true

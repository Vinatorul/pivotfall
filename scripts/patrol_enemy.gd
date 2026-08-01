class_name PatrolEnemy
extends CharacterBody2D

const PATROL_VISUAL_HALF_HEIGHT := 21.0
const PATROL_VISUAL_HALF_WIDTH := 15.0

@export var patrol_speed := 85.0
@export var knockback_lock_time := 0.28
@export var knockback_drag := 420.0
@export var maximum_fall_speed := 900.0

@export_category("Impact feedback")
@export_range(0.01, 0.5, 0.01) var hit_flash_duration := 0.12
@export_range(0.0, 0.4, 0.01) var hit_squash_y := 0.14

@export_category("Patrol animation")
@export_range(0.0, 2.0, 0.1) var patrol_walk_bob_height := 1.0
@export_range(0.5, 6.0, 0.1) var patrol_walk_cycle_frequency := 2.4
@export_range(0.0, 0.1, 0.005) var patrol_walk_stretch := 0.025
@export_range(0.0, 0.2, 0.01) var patrol_walk_lean := 0.045
@export_range(0.01, 0.4, 0.01) var patrol_turn_visual_time := 0.14
@export_range(0.0, 0.3, 0.01) var patrol_turn_squash := 0.12
@export_range(0.0, 6.0, 0.5) var patrol_turn_back_offset := 2.0
@export_range(0.0, 8.0, 0.5) var patrol_knockback_recoil_offset := 2.5
@export_range(0.0, 0.2, 0.01) var patrol_knockback_stretch := 0.07
@export_range(0.0, 0.2, 0.01) var patrol_knockback_lean := 0.075

@onready var visual: Node2D = $Visual
@onready var edge_probe: RayCast2D = $EdgeProbe
@onready var contact_hazard: Area2D = $ContactHazard

var gravity: float = float(
	ProjectSettings.get_setting("physics/2d/default_gravity", 1500.0)
)
@export_range(-1.0, 1.0, 2.0) var patrol_direction := -1.0
var knockback_time_remaining := 0.0
var hit_flash_time_remaining := 0.0
var impact_freeze_frames_remaining := 0
var base_visual_modulate := Color.WHITE
var base_visual_scale_y := 1.0
var patrol_animation_cycle := 0.0
var patrol_turn_visual_time_remaining := 0.0
var patrol_knockback_visual_direction := -1.0
var patrol_base_visual_position := Vector2.ZERO
var patrol_base_visual_rotation := 0.0
var patrol_base_visual_scale_x := 1.0


func _ready() -> void:
	contact_hazard.body_entered.connect(
		_on_contact_hazard_body_entered
	)
	base_visual_modulate = visual.modulate
	base_visual_scale_y = visual.scale.y
	patrol_base_visual_position = visual.position
	patrol_base_visual_rotation = visual.rotation
	patrol_base_visual_scale_x = absf(visual.scale.x)
	_sync_direction()
	_apply_patrol_visual()


func _on_contact_hazard_body_entered(body: Node2D) -> void:
	if body is Player:
		body.receive_lethal_hit()


func _physics_process(delta: float) -> void:
	if _consume_impact_freeze_frame():
		return

	_update_hit_flash(delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	var was_processing_knockback := knockback_time_remaining > 0.0
	if was_processing_knockback:
		knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	else:
		if is_on_floor() and not edge_probe.is_colliding():
			_turn_around()
			_start_patrol_turn_visual()
		velocity.x = patrol_direction * patrol_speed

	move_and_slide()

	if is_on_wall():
		_turn_around()
		if not was_processing_knockback:
			_start_patrol_turn_visual()

	_update_patrol_animation(delta, was_processing_knockback)


func receive_impulse(impulse: Vector2) -> void:
	patrol_knockback_visual_direction = (
		signf(impulse.x)
		if not is_zero_approx(impulse.x)
		else patrol_direction
	)
	patrol_animation_cycle = 0.0
	patrol_turn_visual_time_remaining = 0.0
	velocity = impulse
	knockback_time_remaining = knockback_lock_time
	hit_flash_time_remaining = hit_flash_duration
	_apply_hit_visual()

	if not is_zero_approx(impulse.x):
		patrol_direction = signf(impulse.x)
		_sync_direction()

	_apply_patrol_visual()


func begin_impact_freeze(frames: int = 3) -> void:
	impact_freeze_frames_remaining = maxi(
		impact_freeze_frames_remaining,
		frames
	)


func is_impact_frozen() -> bool:
	return impact_freeze_frames_remaining > 0


func _uses_base_patrol_animation() -> bool:
	return true


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


func _start_patrol_turn_visual() -> void:
	patrol_animation_cycle = 0.0
	patrol_turn_visual_time_remaining = patrol_turn_visual_time
	_apply_patrol_visual()


func _update_patrol_animation(
	delta: float,
	hold_knockback_exit: bool = false
) -> void:
	patrol_turn_visual_time_remaining = maxf(
		patrol_turn_visual_time_remaining - delta,
		0.0
	)

	if (
		knockback_time_remaining <= 0.0
		and patrol_turn_visual_time_remaining <= 0.0
		and not hold_knockback_exit
	):
		var speed_ratio := clampf(
			absf(velocity.x) / maxf(absf(patrol_speed), 1.0),
			0.0,
			1.0
		)
		patrol_animation_cycle = fmod(
			patrol_animation_cycle
			+ delta
			* patrol_walk_cycle_frequency
			* TAU
			* speed_ratio,
			TAU
		)

	_apply_patrol_visual()


func _apply_patrol_visual() -> void:
	if not _uses_base_patrol_animation():
		return

	var offset := Vector2.ZERO
	var rotation_offset := 0.0
	var body_scale_x := 1.0
	var body_scale_y := 1.0
	var lift := 0.0

	if knockback_time_remaining > 0.0:
		var recoil := _patrol_smoothstep01(
			clampf(
				knockback_time_remaining
				/ maxf(knockback_lock_time, 0.001),
				0.0,
				1.0
			)
		)
		offset.x = (
			-patrol_knockback_visual_direction
			* patrol_knockback_recoil_offset
			* recoil
		)
		body_scale_x = 1.0 + patrol_knockback_stretch * recoil
		rotation_offset = (
			-patrol_knockback_visual_direction
			* patrol_knockback_lean
			* recoil
		)
	elif patrol_turn_visual_time_remaining > 0.0:
		var turn_weight := _patrol_smoothstep01(
			clampf(
				patrol_turn_visual_time_remaining
				/ maxf(patrol_turn_visual_time, 0.001),
				0.0,
				1.0
			)
		)
		offset.x = (
			-patrol_direction
			* patrol_turn_back_offset
			* turn_weight
		)
		body_scale_x = 1.0 + patrol_turn_squash * 0.5 * turn_weight
		body_scale_y = 1.0 - patrol_turn_squash * turn_weight
		rotation_offset = (
			-patrol_direction
			* patrol_walk_lean
			* 1.4
			* turn_weight
		)
	else:
		var step := sin(patrol_animation_cycle)
		var step_lift := absf(step)
		lift = -patrol_walk_bob_height * step_lift
		body_scale_x = 1.0 - patrol_walk_stretch * 0.35 * step_lift
		body_scale_y = 1.0 + patrol_walk_stretch * step_lift
		rotation_offset = patrol_direction * patrol_walk_lean * step

	var hit_intensity := clampf(
		hit_flash_time_remaining / maxf(hit_flash_duration, 0.001),
		0.0,
		1.0
	)
	var hit_scale_y := 1.0 - hit_squash_y * hit_intensity
	var final_rotation := patrol_base_visual_rotation + rotation_offset
	var final_scale := Vector2(
		patrol_direction * patrol_base_visual_scale_x * body_scale_x,
		base_visual_scale_y * body_scale_y * hit_scale_y
	)
	offset.y = (
		lift
		+ _patrol_visual_bottom_extent(
			patrol_base_visual_rotation,
			Vector2(patrol_base_visual_scale_x, base_visual_scale_y)
		)
		- _patrol_visual_bottom_extent(final_rotation, final_scale)
	)

	visual.position = patrol_base_visual_position + offset
	visual.rotation = final_rotation
	visual.scale = final_scale


func _patrol_visual_bottom_extent(
	rotation: float,
	scale: Vector2
) -> float:
	var left_foot := Vector2(
		-PATROL_VISUAL_HALF_WIDTH * scale.x,
		PATROL_VISUAL_HALF_HEIGHT * scale.y
	).rotated(rotation)
	var right_foot := Vector2(
		PATROL_VISUAL_HALF_WIDTH * scale.x,
		PATROL_VISUAL_HALF_HEIGHT * scale.y
	).rotated(rotation)
	return maxf(left_foot.y, right_foot.y)


func _patrol_smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

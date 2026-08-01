class_name Player
extends CharacterBody2D

signal attack_landed(
	target: Node2D,
	impact_position: Vector2,
	impulse: Vector2
)
signal defeated(
	player: Node2D,
	cause: int,
	impact_direction: Vector2
)

const IMPACT_BURST_SCRIPT := preload(
	"res://scripts/effects/impact_burst.gd"
)
const VISUAL_HALF_HEIGHT := 20.0
const RUN_ANIMATION_MIN_SPEED := 18.0

enum LocomotionPose {
	IDLE,
	RUN,
	RISE,
	FALL,
	LAND,
}

enum DefeatCause {
	COMBAT,
	FALL,
}

@export_category("Movement")
@export var move_speed := 260.0
@export var ground_acceleration := 1900.0
@export var ground_deceleration := 2300.0
@export var air_acceleration := 1100.0
@export var jump_velocity := -540.0
@export var maximum_fall_speed := 900.0

@export_category("Movement animation")
@export_range(0.0, 2.0, 0.1) var idle_bob_height := 0.6
@export_range(0.5, 4.0, 0.1) var idle_bob_frequency := 1.6
@export_range(0.0, 3.0, 0.1) var run_bob_height := 1.5
@export_range(0.5, 8.0, 0.1) var run_cycle_frequency := 3.5
@export_range(0.0, 0.2, 0.01) var run_lean_radians := 0.07
@export_range(0.0, 0.2, 0.01) var air_stretch := 0.08
@export_range(0.05, 0.3, 0.01) var landing_duration := 0.12
@export_range(0.0, 0.25, 0.01) var landing_squash := 0.14
@export_range(0.0, 600.0, 10.0) var landing_min_speed := 180.0

@export_category("Attack")
@export var attack_horizontal_impulse := 390.0
@export var attack_vertical_impulse := -170.0
@export var attack_active_time := 0.12
@export var attack_cooldown := 0.3

@export_category("Attack animation")
@export_range(0.1, 0.4, 0.01) var attack_anticipation_ratio := 0.22
@export_range(0.35, 0.75, 0.01) var attack_contact_ratio := 0.52
@export_range(0.0, 12.0, 0.5) var attack_anticipation_offset := 4.0
@export_range(0.0, 16.0, 0.5) var attack_strike_offset := 8.0
@export_range(0.0, 0.35, 0.01) var attack_lean_radians := 0.14

@export_category("Impact feedback")
@export_range(1, 6, 1) var attack_hit_stop_frames := 3

@export_category("Fall feedback")
@export_range(0.0, 2.5, 0.01) var fall_spin_radians := 0.32
@export_range(0.0, 64.0, 1.0) var fall_drop_distance := 40.0
@export_range(0.01, 1.0, 0.01) var fall_end_scale := 0.08
@export_range(0.0, 1.0, 0.01) var fall_end_alpha := 0.0
@export_range(0.0, 0.3, 0.01) var fall_entry_squash := 0.1

@export_category("Combat defeat feedback")
@export_range(1, 6, 1) var combat_defeat_hit_stop_frames := 3
@export_range(0.0, 80.0, 1.0) var combat_defeat_recoil_distance := 44.0
@export_range(0.0, 40.0, 1.0) var combat_defeat_lift_height := 18.0
@export_range(0.0, 32.0, 1.0) var combat_defeat_drop_distance := 10.0
@export_range(0.0, 1.0, 0.01) var combat_defeat_spin_radians := 0.22
@export_range(0.01, 1.0, 0.01) var combat_defeat_end_scale := 0.62
@export_range(0.0, 1.0, 0.01) var combat_defeat_end_alpha := 0.0
@export_range(0.0, 0.4, 0.01) var combat_defeat_entry_squash := 0.18
@export var combat_defeat_flash_color := Color(3.0, 0.52, 0.52, 1.0)

@export_category("Clear celebration")
@export_range(0.1, 1.2, 0.01) var clear_celebration_time := 0.68
@export_range(0.0, 32.0, 1.0) var clear_celebration_lift := 12.0
@export_range(0.0, 8.0, 0.5) var clear_celebration_hold_lift := 2.0
@export_range(0.0, 0.3, 0.01) var clear_celebration_spin := 0.05
@export_range(0.0, 0.4, 0.01) var clear_celebration_entry_squash := 0.16
@export_range(1.0, 1.2, 0.01) var clear_celebration_end_scale := 1.03
@export_range(0.0, 0.5, 0.01) var clear_celebration_hold_glow := 0.22
@export var clear_celebration_glow_color := Color(0.72, 1.35, 0.58, 1.0)

@export_category("Knockback")
@export var knockback_lock_time := 0.22
@export var knockback_drag := 520.0

@onready var fall_visual_pivot: Node2D = $FallVisualPivot
@onready var visual: Node2D = $FallVisualPivot/Visual
@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_area: Area2D = $AttackPivot/AttackArea
@onready var attack_visual: Polygon2D = $AttackPivot/AttackVisual

var gravity: float = float(
	ProjectSettings.get_setting("physics/2d/default_gravity", 1500.0)
)
var jump_requested := false
var attack_requested := false
var facing_direction := 1.0
var attack_time_remaining := 0.0
var attack_cooldown_remaining := 0.0
var knockback_time_remaining := 0.0
var impact_freeze_frames_remaining := 0
var struck_targets: Dictionary[int, bool] = {}
var locomotion_pose := LocomotionPose.IDLE
var locomotion_time := 0.0
var run_cycle := 0.0
var landing_time_remaining := 0.0
var landing_strength := 0.0
var attack_pose_progress := 0.0
var base_visual_position := Vector2.ZERO
var base_visual_rotation := 0.0
var base_visual_scale_y := 1.0
var base_attack_visual_scale := Vector2.ONE
var base_attack_visual_color := Color.WHITE
var base_fall_pivot_position := Vector2.ZERO
var base_fall_pivot_rotation := 0.0
var base_fall_pivot_scale := Vector2.ONE
var base_fall_pivot_modulate := Color.WHITE
var fall_out_duration := 0.001
var fall_out_elapsed := 0.0
var fall_out_direction := 1.0
var is_falling_out := false
var fall_out_origin_position := Vector2.ZERO
var fall_out_origin_rotation := 0.0
var fall_out_origin_scale := Vector2.ONE
var fall_out_origin_modulate := Color.WHITE
var is_defeated := false
var defeat_cause := DefeatCause.FALL
var defeat_impact_direction := Vector2.ZERO
var is_combat_defeat_active := false
var combat_defeat_duration := 0.001
var combat_defeat_elapsed := 0.0
var combat_defeat_hold_frames_remaining := 0
var combat_defeat_origin_position := Vector2.ZERO
var combat_defeat_origin_rotation := 0.0
var combat_defeat_origin_scale := Vector2.ONE
var combat_defeat_origin_modulate := Color.WHITE
var is_clear_celebrating := false
var clear_celebration_duration := 0.001
var clear_celebration_elapsed := 0.0
var clear_celebration_origin_position := Vector2.ZERO
var clear_celebration_origin_rotation := 0.0
var clear_celebration_origin_scale := Vector2.ONE
var clear_celebration_origin_modulate := Color.WHITE


func _ready() -> void:
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.area_entered.connect(_on_attack_area_area_entered)
	base_visual_position = visual.position
	base_visual_rotation = visual.rotation
	base_visual_scale_y = visual.scale.y
	base_attack_visual_scale = attack_visual.scale
	base_attack_visual_color = attack_visual.color
	base_fall_pivot_position = fall_visual_pivot.position
	base_fall_pivot_rotation = fall_visual_pivot.rotation
	base_fall_pivot_scale = fall_visual_pivot.scale
	base_fall_pivot_modulate = fall_visual_pivot.modulate
	_reset_fall_out_visual()
	_reset_attack_pose()


func _input(event: InputEvent) -> void:
	if (
		is_defeated
		or is_clear_celebrating
		or not event is InputEventKey
		or not event.pressed
		or event.echo
	):
		return

	if event.physical_keycode == KEY_W:
		jump_requested = true
	elif event.physical_keycode in [KEY_X, KEY_J]:
		attack_requested = true


func _physics_process(delta: float) -> void:
	if is_clear_celebrating:
		_update_clear_celebration_animation(delta)
		return

	if is_defeated and defeat_cause == DefeatCause.COMBAT:
		if combat_defeat_hold_frames_remaining > 0:
			combat_defeat_hold_frames_remaining -= 1
			return
		_update_combat_defeat_animation(delta)
		return

	_update_fall_out_animation(delta)
	if _consume_impact_freeze_frame():
		return
	if is_defeated:
		_process_fall_defeat_physics(delta)
		return

	var was_grounded := is_on_floor()
	_update_attack_timers(delta)

	var direction := Input.get_axis("ui_left", "ui_right")
	direction += Input.get_axis(
		"mobile_move_left",
		"mobile_move_right"
	)

	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1.0

	direction = clampf(direction, -1.0, 1.0)

	var controls_locked := knockback_time_remaining > 0.0
	if controls_locked:
		knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	else:
		var acceleration := ground_acceleration if is_on_floor() else air_acceleration
		if is_zero_approx(direction):
			velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		else:
			velocity.x = move_toward(
				velocity.x,
				direction * move_speed,
				acceleration * delta
			)
			facing_direction = signf(direction)
			visual.scale.x = facing_direction
			attack_pivot.scale.x = facing_direction
			if not is_zero_approx(attack_time_remaining):
				_apply_attack_pose(attack_pose_progress)

	var wants_to_jump := (
		Input.is_action_just_pressed("ui_accept")
		or Input.is_action_just_pressed("ui_up")
		or Input.is_action_just_pressed("mobile_jump")
		or jump_requested
	)
	jump_requested = false
	var wants_to_attack := (
		Input.is_action_just_pressed("mobile_attack")
		or attack_requested
	)

	if (
		not controls_locked
		and wants_to_attack
		and is_zero_approx(attack_cooldown_remaining)
	):
		_start_attack()
	attack_requested = false

	if is_on_floor():
		if wants_to_jump and not controls_locked:
			velocity.y = jump_velocity
	else:
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	var landing_speed := maxf(velocity.y, 0.0)
	move_and_slide()
	_update_locomotion_animation(
		delta,
		was_grounded,
		is_on_floor(),
		landing_speed,
		controls_locked
	)


func _process_fall_defeat_physics(delta: float) -> void:
	var was_grounded := is_on_floor()
	_update_attack_timers(delta)
	var controls_locked := knockback_time_remaining > 0.0
	if controls_locked:
		knockback_time_remaining = maxf(
			knockback_time_remaining - delta,
			0.0
		)
		velocity.x = move_toward(
			velocity.x,
			0.0,
			knockback_drag * delta
		)
	else:
		velocity.x = move_toward(
			velocity.x,
			0.0,
			ground_deceleration * delta
		)

	if not is_on_floor():
		velocity.y = minf(
			velocity.y + gravity * delta,
			maximum_fall_speed
		)
	var landing_speed := maxf(velocity.y, 0.0)
	move_and_slide()
	_update_locomotion_animation(
		delta,
		was_grounded,
		is_on_floor(),
		landing_speed,
		controls_locked
	)


func receive_impulse(impulse: Vector2) -> void:
	if is_defeated or is_clear_celebrating:
		return

	velocity = impulse
	knockback_time_remaining = knockback_lock_time
	jump_requested = false
	attack_requested = false


func receive_lethal_hit(
	cause: int = DefeatCause.COMBAT,
	impact_direction := Vector2.ZERO
) -> bool:
	if is_defeated or is_clear_celebrating:
		return false

	is_defeated = true
	defeat_cause = cause
	defeat_impact_direction = impact_direction.normalized()
	if (
		cause == DefeatCause.COMBAT
		and defeat_impact_direction.is_zero_approx()
	):
		defeat_impact_direction = Vector2(facing_direction, 0.0)
		if defeat_impact_direction.is_zero_approx():
			defeat_impact_direction = Vector2.RIGHT
	jump_requested = false
	attack_requested = false
	_finish_attack()
	if cause == DefeatCause.COMBAT:
		combat_defeat_hold_frames_remaining = (
			combat_defeat_hit_stop_frames
		)
	defeated.emit(self, cause, defeat_impact_direction)
	return true


func begin_impact_freeze(frames: int = 3) -> void:
	if is_defeated or is_clear_celebrating:
		return

	impact_freeze_frames_remaining = maxi(
		impact_freeze_frames_remaining,
		frames
	)


func begin_fall_out(duration: float) -> bool:
	if (
		is_clear_celebrating
		or is_falling_out
		or is_combat_defeat_active
	):
		return false

	fall_out_duration = maxf(duration, 0.001)
	fall_out_elapsed = 0.0
	fall_out_direction = signf(velocity.x)
	if is_zero_approx(fall_out_direction):
		fall_out_direction = facing_direction
	if is_zero_approx(fall_out_direction):
		fall_out_direction = 1.0
	var visual_global_transform := fall_visual_pivot.global_transform
	fall_visual_pivot.set_as_top_level(true)
	fall_visual_pivot.global_transform = visual_global_transform
	fall_out_origin_position = fall_visual_pivot.position
	fall_out_origin_rotation = fall_visual_pivot.rotation
	fall_out_origin_scale = fall_visual_pivot.scale
	fall_out_origin_modulate = fall_visual_pivot.modulate
	is_falling_out = true
	_apply_fall_out_visual()
	return true


func begin_combat_defeat(
	impact_direction: Vector2,
	duration: float
) -> bool:
	if (
		is_clear_celebrating
		or is_combat_defeat_active
		or is_falling_out
	):
		return false

	combat_defeat_duration = maxf(duration, 0.001)
	combat_defeat_elapsed = 0.0
	defeat_impact_direction = impact_direction.normalized()
	if defeat_impact_direction.is_zero_approx():
		defeat_impact_direction = Vector2(facing_direction, 0.0)
	if defeat_impact_direction.is_zero_approx():
		defeat_impact_direction = Vector2.RIGHT
	var visual_global_transform := fall_visual_pivot.global_transform
	fall_visual_pivot.set_as_top_level(true)
	fall_visual_pivot.global_transform = visual_global_transform
	combat_defeat_origin_position = fall_visual_pivot.position
	combat_defeat_origin_rotation = fall_visual_pivot.rotation
	combat_defeat_origin_scale = fall_visual_pivot.scale
	combat_defeat_origin_modulate = fall_visual_pivot.modulate
	is_combat_defeat_active = true
	_apply_combat_defeat_visual()
	return true


func begin_clear_celebration(outcome_delay: float) -> bool:
	if (
		is_clear_celebrating
		or is_defeated
		or is_falling_out
		or is_combat_defeat_active
	):
		return false

	clear_celebration_duration = minf(
		clear_celebration_time,
		maxf(outcome_delay, 0.001)
	)
	clear_celebration_elapsed = 0.0
	jump_requested = false
	attack_requested = false
	knockback_time_remaining = 0.0
	impact_freeze_frames_remaining = 0
	velocity = Vector2.ZERO
	locomotion_pose = LocomotionPose.IDLE
	locomotion_time = 0.0
	run_cycle = 0.0
	landing_time_remaining = 0.0
	landing_strength = 0.0
	_finish_attack()
	struck_targets.clear()
	fall_visual_pivot.set_as_top_level(false)
	clear_celebration_origin_position = fall_visual_pivot.position
	clear_celebration_origin_rotation = fall_visual_pivot.rotation
	clear_celebration_origin_scale = fall_visual_pivot.scale
	clear_celebration_origin_modulate = fall_visual_pivot.modulate
	is_clear_celebrating = true
	_apply_clear_celebration_visual()
	return true


func is_impact_frozen() -> bool:
	return impact_freeze_frames_remaining > 0


func _start_attack() -> void:
	if is_defeated or is_clear_celebrating:
		return

	attack_time_remaining = attack_active_time
	attack_cooldown_remaining = attack_cooldown
	struck_targets.clear()
	attack_visual.visible = true
	attack_area.monitoring = true
	attack_pose_progress = 0.0
	_apply_attack_pose(attack_pose_progress)


func _finish_attack() -> void:
	attack_time_remaining = 0.0
	attack_visual.visible = false
	attack_area.monitoring = false
	_reset_attack_pose()


func _update_attack_timers(delta: float) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)

	if is_zero_approx(attack_time_remaining):
		return

	attack_time_remaining = maxf(attack_time_remaining - delta, 0.0)
	if is_zero_approx(attack_time_remaining):
		_finish_attack()
		return

	var timer_progress := 1.0 - (
		attack_time_remaining / maxf(attack_active_time, 0.001)
	)
	attack_pose_progress = maxf(
		attack_pose_progress,
		clampf(timer_progress, 0.0, 1.0)
	)
	_apply_attack_pose(attack_pose_progress)


func _on_attack_area_body_entered(body: Node2D) -> void:
	_try_apply_impulse(body)


func _on_attack_area_area_entered(area: Area2D) -> void:
	_try_apply_impulse(area)


func _try_apply_impulse(target: Node2D) -> void:
	if (
		is_defeated
		or is_clear_celebrating
		or is_zero_approx(attack_time_remaining)
		or not target.has_method("receive_impulse")
	):
		return

	var target_id := target.get_instance_id()
	if struck_targets.has(target_id):
		return

	struck_targets[target_id] = true
	var impulse := Vector2(
		facing_direction * attack_horizontal_impulse,
		attack_vertical_impulse
	)
	var impact_position := target.global_position
	target.call("receive_impulse", impulse)
	_show_attack_impact(target, impact_position, impulse)


func _show_attack_impact(
	target: Node2D,
	impact_position: Vector2,
	impulse: Vector2
) -> void:
	_snap_attack_pose_to_contact()

	var effect_parent := get_parent()
	if is_instance_valid(effect_parent):
		var burst := IMPACT_BURST_SCRIPT.new() as ImpactBurst
		burst.configure(impulse)
		effect_parent.add_child(burst)
		burst.global_position = (
			impact_position - impulse.normalized() * 12.0
		)

	if (
		target.is_in_group("enemies")
		and target.has_method("begin_impact_freeze")
	):
		begin_impact_freeze(attack_hit_stop_frames)
		target.call(
			"begin_impact_freeze",
			attack_hit_stop_frames
		)

	attack_landed.emit(target, impact_position, impulse)


func _snap_attack_pose_to_contact() -> void:
	attack_pose_progress = _attack_contact_point()
	_apply_attack_pose(attack_pose_progress)


func _apply_attack_pose(progress: float) -> void:
	var anticipation_end := _attack_anticipation_end()
	var contact := _attack_contact_point()
	var pose_progress := clampf(progress, 0.0, 1.0)
	var offset := 0.0
	var lean := 0.0
	var body_scale_y := 1.0
	var strike_scale := Vector2.ONE
	var strike_alpha := 1.0

	if pose_progress <= anticipation_end:
		var phase := _smoothstep01(pose_progress / anticipation_end)
		offset = lerpf(0.0, -attack_anticipation_offset, phase)
		lean = lerpf(0.0, -attack_lean_radians * 0.7, phase)
		body_scale_y = lerpf(1.0, 0.92, phase)
		strike_scale = Vector2(
			lerpf(0.28, 0.48, phase),
			lerpf(0.72, 0.82, phase)
		)
		strike_alpha = lerpf(0.18, 0.38, phase)
	elif pose_progress <= contact:
		var phase := _smoothstep01(
			(pose_progress - anticipation_end)
			/ (contact - anticipation_end)
		)
		offset = lerpf(
			-attack_anticipation_offset,
			attack_strike_offset,
			phase
		)
		lean = lerpf(
			-attack_lean_radians * 0.7,
			attack_lean_radians,
			phase
		)
		body_scale_y = lerpf(0.92, 1.06, phase)
		strike_scale = Vector2(
			lerpf(0.48, 1.18, phase),
			lerpf(0.82, 1.08, phase)
		)
		strike_alpha = lerpf(0.38, 1.0, phase)
	else:
		var phase := _smoothstep01(
			(pose_progress - contact) / (1.0 - contact)
		)
		offset = lerpf(attack_strike_offset, 0.0, phase)
		lean = lerpf(attack_lean_radians, 0.0, phase)
		body_scale_y = lerpf(1.06, 1.0, phase)
		strike_scale = Vector2(
			lerpf(1.18, 0.88, phase),
			lerpf(1.08, 0.9, phase)
		)
		strike_alpha = lerpf(1.0, 0.0, phase)

	visual.position = base_visual_position + Vector2(
		facing_direction * offset,
		0.0
	)
	visual.rotation = (
		base_visual_rotation + facing_direction * lean
	)
	visual.scale.y = base_visual_scale_y * body_scale_y
	attack_visual.scale = base_attack_visual_scale * strike_scale
	attack_visual.color = Color(
		base_attack_visual_color.r,
		base_attack_visual_color.g,
		base_attack_visual_color.b,
		base_attack_visual_color.a * strike_alpha
	)


func _reset_attack_pose() -> void:
	attack_pose_progress = 0.0
	attack_visual.scale = base_attack_visual_scale
	attack_visual.color = base_attack_visual_color
	_apply_locomotion_pose()


func _update_locomotion_animation(
	delta: float,
	was_grounded: bool,
	grounded: bool,
	landing_speed: float,
	controls_locked: bool
) -> void:
	locomotion_time += delta
	var started_landing := false

	if (
		not was_grounded
		and grounded
		and landing_speed >= landing_min_speed
	):
		landing_time_remaining = landing_duration
		started_landing = true
		landing_strength = clampf(
			(landing_speed - landing_min_speed)
			/ maxf(maximum_fall_speed - landing_min_speed, 1.0),
			0.35,
			1.0
		)
	elif not grounded:
		landing_time_remaining = 0.0

	if grounded and landing_time_remaining > 0.0:
		locomotion_pose = LocomotionPose.LAND
	elif not grounded:
		locomotion_pose = (
			LocomotionPose.RISE
			if velocity.y < 0.0
			else LocomotionPose.FALL
		)
	elif (
		not controls_locked
		and absf(velocity.x) >= RUN_ANIMATION_MIN_SPEED
	):
		locomotion_pose = LocomotionPose.RUN
	else:
		locomotion_pose = LocomotionPose.IDLE

	if locomotion_pose == LocomotionPose.RUN:
		var speed_ratio := clampf(
			absf(velocity.x) / maxf(move_speed, 1.0),
			0.0,
			1.0
		)
		run_cycle = fmod(
			run_cycle
			+ delta * run_cycle_frequency * TAU * speed_ratio,
			TAU
		)

	if locomotion_pose == LocomotionPose.LAND and not started_landing:
		landing_time_remaining = maxf(
			landing_time_remaining - delta,
			0.0
		)

	_apply_current_visual_pose()


func _apply_current_visual_pose() -> void:
	if attack_time_remaining > 0.0:
		_apply_attack_pose(attack_pose_progress)
	else:
		_apply_locomotion_pose()


func _apply_locomotion_pose() -> void:
	var offset_y := 0.0
	var lean := 0.0
	var body_scale_y := 1.0

	match locomotion_pose:
		LocomotionPose.IDLE:
			var breath := sin(
				locomotion_time * idle_bob_frequency * TAU
			)
			offset_y = -breath * idle_bob_height
			body_scale_y = 1.0 + breath * 0.012
		LocomotionPose.RUN:
			var step := absf(sin(run_cycle))
			var speed_ratio := clampf(
				absf(velocity.x) / maxf(move_speed, 1.0),
				0.0,
				1.0
			)
			offset_y = -step * run_bob_height
			lean = run_lean_radians * speed_ratio
			body_scale_y = lerpf(0.97, 1.025, step)
		LocomotionPose.RISE:
			var rise_ratio := clampf(
				absf(velocity.y) / maxf(absf(jump_velocity), 1.0),
				0.0,
				1.0
			)
			body_scale_y = 1.0 + air_stretch * lerpf(
				0.35,
				1.0,
				rise_ratio
			)
			offset_y = -VISUAL_HALF_HEIGHT * (body_scale_y - 1.0)
			lean = _air_lean()
		LocomotionPose.FALL:
			var fall_ratio := clampf(
				velocity.y / maxf(maximum_fall_speed, 1.0),
				0.0,
				1.0
			)
			body_scale_y = 1.0 + air_stretch * lerpf(
				0.35,
				1.0,
				fall_ratio
			)
			offset_y = -VISUAL_HALF_HEIGHT * (body_scale_y - 1.0)
			lean = _air_lean()
		LocomotionPose.LAND:
			var progress := 1.0 - (
				landing_time_remaining / maxf(landing_duration, 0.001)
			)
			var squash := (
				landing_squash
				* landing_strength
				* (1.0 - _smoothstep01(progress))
			)
			body_scale_y = 1.0 - squash
			offset_y = VISUAL_HALF_HEIGHT * squash

	visual.position = base_visual_position + Vector2(0.0, offset_y)
	visual.rotation = (
		base_visual_rotation + facing_direction * lean
	)
	visual.scale.y = base_visual_scale_y * body_scale_y


func _update_clear_celebration_animation(delta: float) -> void:
	if not is_clear_celebrating:
		return
	clear_celebration_elapsed = minf(
		clear_celebration_elapsed + maxf(delta, 0.0),
		clear_celebration_duration
	)
	_apply_clear_celebration_visual()


func _apply_clear_celebration_visual() -> void:
	var progress := clampf(
		clear_celebration_elapsed
		/ maxf(clear_celebration_duration, 0.001),
		0.0,
		1.0
	)
	var hop := sin(progress * PI)
	var settle := smoothstep(0.55, 1.0, progress)
	var entry_strength := 1.0 - smoothstep(0.0, 0.16, progress)
	var pulse := sin(progress * PI)
	var wobble := (
		sin(progress * TAU)
		* (1.0 - smoothstep(0.08, 0.88, progress))
	)
	fall_visual_pivot.position = (
		clear_celebration_origin_position
		+ Vector2(
			0.0,
			VISUAL_HALF_HEIGHT
			* clear_celebration_entry_squash
			* entry_strength
			-clear_celebration_lift * hop
			- clear_celebration_hold_lift * settle
		)
	)
	fall_visual_pivot.rotation = (
		clear_celebration_origin_rotation
		+ facing_direction
		* clear_celebration_spin
		* wobble
	)
	var uniform_scale := (
		1.0
		+ 0.04 * pulse
		+ (clear_celebration_end_scale - 1.0) * settle
	)
	fall_visual_pivot.scale = clear_celebration_origin_scale * Vector2(
		uniform_scale
		* (1.0 - 0.06 * hop)
		* (1.0 + clear_celebration_entry_squash * entry_strength),
		uniform_scale
		* (1.0 + 0.06 * hop)
		* (1.0 - clear_celebration_entry_squash * entry_strength)
	)
	var flash_strength := 1.0 - smoothstep(0.0, 0.38, progress)
	var glow_strength := maxf(
		flash_strength,
		maxf(
			0.32 * pulse,
			clear_celebration_hold_glow * settle
		)
	)
	var glow_color := Color(
		clear_celebration_glow_color.r,
		clear_celebration_glow_color.g,
		clear_celebration_glow_color.b,
		clear_celebration_origin_modulate.a
	)
	fall_visual_pivot.modulate = clear_celebration_origin_modulate.lerp(
		glow_color,
		glow_strength
	)


func _update_combat_defeat_animation(delta: float) -> void:
	if not is_combat_defeat_active:
		return
	combat_defeat_elapsed = minf(
		combat_defeat_elapsed + maxf(delta, 0.0),
		combat_defeat_duration
	)
	_apply_combat_defeat_visual()


func _apply_combat_defeat_visual() -> void:
	var progress := clampf(
		combat_defeat_elapsed / maxf(combat_defeat_duration, 0.001),
		0.0,
		1.0
	)
	var travel_progress := smoothstep(0.0, 1.0, progress)
	var lift_offset := -combat_defeat_lift_height * sin(progress * PI)
	var drop_offset := combat_defeat_drop_distance * pow(progress, 2.0)
	fall_visual_pivot.position = (
		combat_defeat_origin_position
		+ defeat_impact_direction
		* combat_defeat_recoil_distance
		* travel_progress
		+ Vector2(0.0, lift_offset + drop_offset)
	)
	var rotation_direction := signf(defeat_impact_direction.x)
	if is_zero_approx(rotation_direction):
		rotation_direction = facing_direction
	if is_zero_approx(rotation_direction):
		rotation_direction = 1.0
	fall_visual_pivot.rotation = (
		combat_defeat_origin_rotation
		+ combat_defeat_spin_radians
		* rotation_direction
		* smoothstep(0.08, 0.82, progress)
	)
	var entry_strength := 1.0 - smoothstep(0.0, 0.18, progress)
	var uniform_scale := lerpf(
		1.0,
		combat_defeat_end_scale,
		smoothstep(0.1, 1.0, progress)
	)
	fall_visual_pivot.scale = combat_defeat_origin_scale * Vector2(
		uniform_scale * (1.0 + combat_defeat_entry_squash * entry_strength),
		uniform_scale * (1.0 - combat_defeat_entry_squash * entry_strength)
	)
	var flash_strength := 1.0 - smoothstep(0.0, 0.28, progress)
	var flash_color := Color(
		combat_defeat_flash_color.r,
		combat_defeat_flash_color.g,
		combat_defeat_flash_color.b,
		combat_defeat_origin_modulate.a
	)
	var tint := combat_defeat_origin_modulate.lerp(
		flash_color,
		flash_strength
	)
	var alpha := combat_defeat_origin_modulate.a * lerpf(
		1.0,
		combat_defeat_end_alpha,
		smoothstep(0.42, 1.0, progress)
	)
	fall_visual_pivot.modulate = Color(
		tint.r,
		tint.g,
		tint.b,
		alpha
	)


func _update_fall_out_animation(delta: float) -> void:
	if not is_falling_out:
		return
	fall_out_elapsed = minf(
		fall_out_elapsed + maxf(delta, 0.0),
		fall_out_duration
	)
	_apply_fall_out_visual()


func _apply_fall_out_visual() -> void:
	var progress := clampf(
		fall_out_elapsed / maxf(fall_out_duration, 0.001),
		0.0,
		1.0
	)
	var scale_progress := smoothstep(0.08, 1.0, progress)
	var rotation_progress := smoothstep(0.1, 0.8, progress)
	var fade_progress := smoothstep(0.46, 1.0, progress)
	var entry_strength := 1.0 - smoothstep(
		0.0,
		0.14,
		progress
	)
	var uniform_scale := lerpf(
		1.0,
		fall_end_scale,
		scale_progress
	)
	fall_visual_pivot.position = fall_out_origin_position + Vector2(
		0.0,
		fall_drop_distance * pow(progress, 1.55)
	)
	fall_visual_pivot.rotation = (
		fall_out_origin_rotation
		+ fall_spin_radians * fall_out_direction * rotation_progress
	)
	fall_visual_pivot.scale = fall_out_origin_scale * Vector2(
		uniform_scale * (1.0 + fall_entry_squash * entry_strength),
		uniform_scale * (1.0 - fall_entry_squash * entry_strength)
	)
	var alpha := fall_out_origin_modulate.a * lerpf(
		1.0,
		fall_end_alpha,
		fade_progress
	)
	fall_visual_pivot.modulate = Color(
		fall_out_origin_modulate.r,
		fall_out_origin_modulate.g,
		fall_out_origin_modulate.b,
		alpha
	)


func _reset_fall_out_visual() -> void:
	fall_visual_pivot.set_as_top_level(false)
	fall_visual_pivot.position = base_fall_pivot_position
	fall_visual_pivot.rotation = base_fall_pivot_rotation
	fall_visual_pivot.scale = base_fall_pivot_scale
	fall_visual_pivot.modulate = base_fall_pivot_modulate


func _air_lean() -> float:
	var horizontal_speed_ratio := clampf(
		absf(velocity.x) / maxf(move_speed, 1.0),
		0.0,
		1.0
	)
	return run_lean_radians * 0.45 * horizontal_speed_ratio


func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _attack_anticipation_end() -> float:
	return clampf(attack_anticipation_ratio, 0.05, 0.45)


func _attack_contact_point() -> float:
	return clampf(
		attack_contact_ratio,
		_attack_anticipation_end() + 0.05,
		0.85
	)


func _consume_impact_freeze_frame() -> bool:
	if impact_freeze_frames_remaining <= 0:
		return false
	impact_freeze_frames_remaining -= 1
	return true

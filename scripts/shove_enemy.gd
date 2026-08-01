class_name ShoveEnemy
extends PatrolEnemy

enum State {
	PATROL,
	TELEGRAPH,
	LUNGE,
	RECOVERY,
	KNOCKBACK,
}

const VISUAL_HALF_HEIGHT := 22.0

@export_category("Shove attack")
@export var detection_range := 180.0
@export var vertical_detection_tolerance := 48.0
@export var telegraph_time := 0.5
@export var lunge_speed := 420.0
@export var lunge_time := 0.28
@export var recovery_time := 0.55
@export var shove_horizontal_impulse := 520.0
@export var shove_vertical_impulse := -140.0

@export_category("Shove animation")
@export_range(0.0, 2.0, 0.1) var patrol_bob_height := 1.0
@export_range(0.5, 6.0, 0.1) var patrol_cycle_frequency := 2.8
@export_range(0.0, 0.1, 0.005) var patrol_step_lean := 0.035
@export_range(0.0, 0.3, 0.01) var telegraph_squash := 0.14
@export_range(0.0, 8.0, 0.5) var telegraph_back_offset := 4.0
@export_range(0.0, 0.3, 0.01) var lunge_stretch := 0.16
@export_range(0.0, 10.0, 0.5) var lunge_forward_offset := 4.5
@export_range(0.0, 0.25, 0.01) var shove_pose_lean := 0.1
@export_range(0.0, 0.2, 0.01) var recovery_squash := 0.08
@export_range(0.0, 8.0, 0.5) var knockback_recoil_offset := 2.5
@export_range(0.0, 0.15, 0.01) var knockback_stretch := 0.06

@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_area: Area2D = $AttackPivot/AttackArea
@onready var attack_visual: Polygon2D = $AttackPivot/AttackVisual
@onready var telegraph_visual: Polygon2D = $Telegraph

var state := State.PATROL
var state_time_remaining := 0.0
var lunge_direction := -1.0
var player: Player
var struck_targets: Dictionary[int, bool] = {}
var patrol_cycle := 0.0
var base_visual_position := Vector2.ZERO
var base_visual_rotation := 0.0
var base_telegraph_scale := Vector2.ONE


func _ready() -> void:
	super()
	base_visual_position = visual.position
	base_visual_rotation = visual.rotation
	base_telegraph_scale = telegraph_visual.scale
	player = _find_player_sibling()
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.area_entered.connect(_on_attack_area_area_entered)
	_enter_patrol()


func _uses_base_patrol_animation() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if _consume_impact_freeze_frame():
		return

	_update_hit_flash(delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	if knockback_time_remaining > 0.0:
		_process_knockback(delta)
	else:
		if state == State.KNOCKBACK:
			_enter_patrol()

		match state:
			State.PATROL:
				_process_patrol()
			State.TELEGRAPH:
				_process_telegraph(delta)
			State.LUNGE:
				_process_lunge(delta)
			State.RECOVERY:
				_process_recovery(delta)

	move_and_slide()

	if is_on_wall():
		if state == State.LUNGE:
			_begin_recovery()
		elif state == State.PATROL:
			_turn_around()

	_update_shove_animation(delta)


func receive_impulse(impulse: Vector2) -> void:
	super(impulse)
	_cancel_attack()
	state = State.KNOCKBACK
	_apply_shove_visual()


func _process_knockback(delta: float) -> void:
	knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)


func _process_patrol() -> void:
	if _can_attack_player():
		_begin_telegraph()
		return

	if is_on_floor() and not edge_probe.is_colliding():
		_turn_around()

	velocity.x = patrol_direction * patrol_speed


func _process_telegraph(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_begin_lunge()


func _process_lunge(delta: float) -> void:
	velocity.x = lunge_direction * lunge_speed
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_begin_recovery()


func _process_recovery(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_enter_patrol()


func _can_attack_player() -> bool:
	if not is_instance_valid(player):
		player = _find_player_sibling()
	if not is_instance_valid(player) or not is_on_floor():
		return false

	var offset := player.global_position - global_position
	return (
		absf(offset.x) <= detection_range
		and absf(offset.y) <= vertical_detection_tolerance
	)


func _find_player_sibling() -> Player:
	var actor_parent := get_parent()
	if not is_instance_valid(actor_parent):
		return null
	for sibling: Node in actor_parent.get_children():
		if sibling is Player:
			return sibling as Player
	return null


func _begin_telegraph() -> void:
	var player_offset := player.global_position.x - global_position.x
	lunge_direction = (
		signf(player_offset)
		if not is_zero_approx(player_offset)
		else patrol_direction
	)
	patrol_direction = lunge_direction
	_sync_direction()
	state = State.TELEGRAPH
	state_time_remaining = telegraph_time
	velocity.x = 0.0
	telegraph_visual.visible = true
	_apply_shove_visual()


func _begin_lunge() -> void:
	state = State.LUNGE
	state_time_remaining = lunge_time
	telegraph_visual.visible = false
	attack_visual.visible = true
	attack_pivot.scale.x = lunge_direction
	struck_targets.clear()
	attack_area.monitoring = true
	_apply_shove_visual()


func _begin_recovery() -> void:
	_cancel_attack()
	state = State.RECOVERY
	state_time_remaining = recovery_time
	velocity.x = 0.0
	_apply_shove_visual()


func _enter_patrol() -> void:
	_cancel_attack()
	state = State.PATROL
	state_time_remaining = 0.0
	patrol_cycle = 0.0
	_sync_direction()
	_apply_shove_visual()


func _cancel_attack() -> void:
	telegraph_visual.visible = false
	attack_visual.visible = false
	attack_area.set_deferred("monitoring", false)


func _update_shove_animation(delta: float) -> void:
	if state == State.PATROL:
		var speed_ratio := clampf(
			absf(velocity.x) / maxf(patrol_speed, 1.0),
			0.0,
			1.0
		)
		patrol_cycle = fmod(
			patrol_cycle
			+ delta * patrol_cycle_frequency * TAU * speed_ratio,
			TAU
		)

	_apply_shove_visual()


func _apply_shove_visual() -> void:
	var offset := Vector2.ZERO
	var lean := 0.0
	var body_scale_x := 1.0
	var body_scale_y := 1.0
	var telegraph_scale := base_telegraph_scale

	match state:
		State.PATROL:
			var step := sin(patrol_cycle)
			var lift := absf(step)
			offset.y = -patrol_bob_height * lift
			lean = patrol_step_lean * step
			body_scale_x = 1.0 - 0.01 * lift
			body_scale_y = 1.0 + 0.018 * lift
		State.TELEGRAPH:
			var charge := _smoothstep01(
				_state_progress(telegraph_time)
			)
			offset.x = -patrol_direction * telegraph_back_offset * charge
			body_scale_x = 1.0 + telegraph_squash * 0.55 * charge
			body_scale_y = 1.0 - telegraph_squash * charge
			offset.y = (
				VISUAL_HALF_HEIGHT
				* base_visual_scale_y
				* (1.0 - body_scale_y)
			)
			lean = -shove_pose_lean * charge
			telegraph_scale = base_telegraph_scale * lerpf(
				0.85,
				1.2,
				charge
			)
		State.LUNGE:
			var drive := 1.0 - 0.2 * _smoothstep01(
				_state_progress(lunge_time)
			)
			offset.x = patrol_direction * lunge_forward_offset * drive
			body_scale_x = 1.0 + lunge_stretch * drive
			body_scale_y = 1.0 - lunge_stretch * 0.45 * drive
			offset.y = (
				VISUAL_HALF_HEIGHT
				* base_visual_scale_y
				* (1.0 - body_scale_y)
			)
			lean = shove_pose_lean * 1.1 * drive
		State.RECOVERY:
			var weight := 1.0 - _smoothstep01(
				_state_progress(recovery_time)
			)
			body_scale_x = 1.0 + recovery_squash * 0.25 * weight
			body_scale_y = 1.0 - recovery_squash * weight
			offset.y = (
				VISUAL_HALF_HEIGHT
				* base_visual_scale_y
				* (1.0 - body_scale_y)
			)
			lean = -shove_pose_lean * 0.45 * weight
		State.KNOCKBACK:
			var recoil := _smoothstep01(
				clampf(
					knockback_time_remaining
					/ maxf(knockback_lock_time, 0.001),
					0.0,
					1.0
				)
			)
			offset.x = -patrol_direction * knockback_recoil_offset * recoil
			body_scale_x = 1.0 + knockback_stretch * recoil
			lean = -shove_pose_lean * 0.8 * recoil

	var hit_intensity := clampf(
		hit_flash_time_remaining / maxf(hit_flash_duration, 0.001),
		0.0,
		1.0
	)
	var hit_scale_y := 1.0 - hit_squash_y * hit_intensity
	offset.y += (
		VISUAL_HALF_HEIGHT
		* base_visual_scale_y
		* body_scale_y
		* (1.0 - hit_scale_y)
	)
	visual.position = base_visual_position + offset
	visual.rotation = (
		base_visual_rotation + patrol_direction * lean
	)
	visual.scale = Vector2(
		patrol_direction * body_scale_x,
		base_visual_scale_y
		* body_scale_y
		* hit_scale_y
	)
	telegraph_visual.scale = telegraph_scale


func _state_progress(duration: float) -> float:
	return clampf(
		1.0 - state_time_remaining / maxf(duration, 0.001),
		0.0,
		1.0
	)


func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _on_attack_area_body_entered(body: Node2D) -> void:
	_try_apply_shove(body)


func _on_attack_area_area_entered(area: Area2D) -> void:
	_try_apply_shove(area)


func _try_apply_shove(target: Node2D) -> void:
	if (
		state != State.LUNGE
		or target == self
	):
		return

	var target_id := target.get_instance_id()
	if struck_targets.has(target_id):
		return

	struck_targets[target_id] = true
	if target is Player:
		target.receive_lethal_hit(
			Player.DefeatCause.COMBAT,
			Vector2(
				lunge_direction * shove_horizontal_impulse,
				shove_vertical_impulse
			).normalized()
		)
		return
	if not target.has_method("receive_impulse"):
		return
	target.call(
		"receive_impulse",
		Vector2(
			lunge_direction * shove_horizontal_impulse,
			shove_vertical_impulse
		)
	)

class_name ShooterEnemy
extends PatrolEnemy

signal shot_fired(projectile: ShooterProjectile)

enum State {
	READY,
	AIMING,
	COOLDOWN,
	KNOCKBACK,
}

const VISUAL_HALF_HEIGHT := 22.0

@export_category("Ranged attack")
@export var line_length := 900.0
@export var aim_time := 0.7
@export var aim_lock_time := 0.23
@export var cooldown_time := 1.3
@export var muzzle_flash_time := 0.1
@export var projectile_scene: PackedScene = preload(
	"res://scenes/shooter_projectile.tscn"
)

@export_category("Shooter animation")
@export_range(0.0, 2.0, 0.1) var ready_bob_height := 0.7
@export_range(0.5, 5.0, 0.1) var ready_cycle_frequency := 1.4
@export_range(0.0, 0.1, 0.005) var ready_breath_stretch := 0.018
@export_range(0.0, 8.0, 0.5) var aim_forward_offset := 2.5
@export_range(0.0, 0.25, 0.01) var aim_brace_squash := 0.08
@export_range(0.0, 0.2, 0.01) var aim_pose_lean := 0.055
@export_range(1.0, 1.5, 0.01) var locked_marker_scale := 1.2
@export_range(0.0, 10.0, 0.5) var fire_recoil_offset := 5.0
@export_range(0.0, 0.25, 0.01) var fire_recoil_stretch := 0.12
@export_range(0.0, 0.2, 0.01) var cooldown_slump := 0.06
@export_range(0.0, 8.0, 0.5) var knockback_recoil_offset := 3.0
@export_range(0.0, 0.2, 0.01) var knockback_stretch := 0.07

@onready var gun_pivot: Node2D = $GunPivot
@onready var muzzle: Marker2D = $GunPivot/Muzzle
@onready var aim_ray: RayCast2D = $GunPivot/Muzzle/AimRay
@onready var aim_line: Line2D = $AimLine
@onready var aim_mark: Polygon2D = $AimMark
@onready var target_mark: Polygon2D = $TargetMark
@onready var muzzle_flash: Polygon2D = $GunPivot/Muzzle/MuzzleFlash
@onready var cooldown_fill: Polygon2D = $CooldownFill

var state := State.READY
var state_time_remaining := 0.0
var flash_time_remaining := 0.0
var player: Player
var aim_direction := Vector2.LEFT
var aim_distance := 0.0
var facing_direction := -1.0
var aim_is_locked := false
var ready_cycle := 0.0
var fire_visual_direction := -1.0
var knockback_visual_direction := -1.0
var base_visual_position := Vector2.ZERO
var base_visual_rotation := 0.0
var base_visual_scale_x := 1.0
var base_aim_mark_scale := Vector2.ONE
var base_target_mark_scale := Vector2.ONE


func _ready() -> void:
	super()
	base_visual_position = visual.position
	base_visual_rotation = visual.rotation
	base_visual_scale_x = absf(visual.scale.x)
	base_aim_mark_scale = aim_mark.scale
	base_target_mark_scale = target_mark.scale
	player = _find_player_sibling()
	_track_player()
	_enter_ready()


func _uses_base_patrol_animation() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if _consume_impact_freeze_frame():
		return

	_update_hit_flash(delta)
	_update_muzzle_flash(delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	if knockback_time_remaining > 0.0:
		_process_knockback(delta)
	else:
		if state == State.KNOCKBACK:
			_begin_cooldown()

		velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)

		match state:
			State.READY:
				if _can_begin_aim():
					_begin_aim()
			State.AIMING:
				_process_aim(delta)
			State.COOLDOWN:
				_process_cooldown(delta)

	move_and_slide()
	_update_shooter_animation(delta)


func receive_impulse(impulse: Vector2) -> void:
	knockback_visual_direction = (
		signf(impulse.x)
		if not is_zero_approx(impulse.x)
		else facing_direction
	)
	super(impulse)
	_cancel_aim()
	_track_player()
	state = State.KNOCKBACK
	_set_cooldown_progress(0.0)
	_apply_shooter_visual()


func _process_knockback(delta: float) -> void:
	knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)


func _can_begin_aim() -> bool:
	if not is_instance_valid(player):
		player = _find_player_sibling()
	if not is_instance_valid(player) or not is_on_floor():
		return false

	return player.global_position.distance_to(global_position) <= line_length


func _begin_aim() -> void:
	state = State.AIMING
	state_time_remaining = aim_time
	velocity.x = 0.0
	aim_line.visible = true
	aim_mark.visible = true
	target_mark.visible = true
	aim_is_locked = false
	_track_player()
	_update_aim_style()
	_set_cooldown_progress(1.0)
	_update_aim_line()
	_apply_shooter_visual()


func _process_aim(delta: float) -> void:
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)
	if state_time_remaining > aim_lock_time:
		_track_player()
	elif not aim_is_locked:
		_track_player()
		aim_is_locked = true
		_update_aim_style()

	_update_aim_line()

	if is_zero_approx(state_time_remaining):
		_fire()


func _fire() -> void:
	_cancel_aim()

	var projectile := projectile_scene.instantiate() as ShooterProjectile
	if not is_instance_valid(projectile):
		push_error("Shooter projectile scene must instantiate ShooterProjectile.")
		_begin_cooldown()
		return

	var projectile_parent := _find_arena_parent()
	if not is_instance_valid(projectile_parent):
		push_error("Shooter enemy must be inside an Arena.")
		projectile.free()
		_begin_cooldown()
		return

	projectile_parent.add_child(projectile)
	projectile.launch(
		muzzle.global_position,
		aim_direction,
		self
	)
	fire_visual_direction = facing_direction
	shot_fired.emit(projectile)

	muzzle_flash.visible = true
	flash_time_remaining = muzzle_flash_time
	_begin_cooldown()


func _find_player_sibling() -> Player:
	var actor_parent := get_parent()
	if not is_instance_valid(actor_parent):
		return null
	for sibling: Node in actor_parent.get_children():
		if sibling is Player:
			return sibling as Player
	return null


func _find_arena_parent() -> Arena:
	var ancestor := get_parent()
	while is_instance_valid(ancestor):
		if ancestor is Arena:
			return ancestor as Arena
		ancestor = ancestor.get_parent()
	return null


func _begin_cooldown() -> void:
	_cancel_aim()
	state = State.COOLDOWN
	state_time_remaining = cooldown_time
	_set_cooldown_progress(0.0)
	_apply_shooter_visual()


func _process_cooldown(delta: float) -> void:
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)
	_track_player()
	var progress := 1.0 - state_time_remaining / cooldown_time
	_set_cooldown_progress(progress)

	if is_zero_approx(state_time_remaining):
		_enter_ready()


func _enter_ready() -> void:
	_cancel_aim()
	state = State.READY
	state_time_remaining = 0.0
	ready_cycle = 0.0
	_set_cooldown_progress(1.0)
	_apply_shooter_visual()


func _cancel_aim() -> void:
	aim_line.visible = false
	aim_mark.visible = false
	target_mark.visible = false
	aim_is_locked = false


func _update_aim_line() -> void:
	aim_ray.force_raycast_update()
	var line_end := (
		aim_ray.get_collision_point()
		if aim_ray.is_colliding()
		else muzzle.global_position
			+ aim_direction * aim_distance
	)
	aim_line.points = PackedVector2Array(
		[to_local(muzzle.global_position), to_local(line_end)]
	)
	target_mark.global_position = line_end


func _track_player() -> void:
	if not is_instance_valid(player):
		player = _find_player_sibling()
	if not is_instance_valid(player):
		return

	var target_offset := player.global_position - gun_pivot.global_position
	if target_offset.length_squared() <= 0.001:
		return

	aim_direction = target_offset.normalized()
	if absf(aim_direction.x) > 0.01:
		facing_direction = signf(aim_direction.x)

	visual.scale.x = facing_direction
	gun_pivot.rotation = aim_direction.angle()
	aim_distance = minf(
		muzzle.global_position.distance_to(player.global_position),
		line_length
	)
	aim_ray.target_position = Vector2(aim_distance, 0.0)


func _update_aim_style() -> void:
	aim_line.width = 5.0 if aim_is_locked else 3.0
	aim_line.default_color = (
		Color(1.0, 0.78, 0.278, 0.9)
		if aim_is_locked
		else Color(1.0, 0.255, 0.31, 0.7)
	)
	aim_mark.color = (
		Color(1.0, 0.78, 0.278, 1.0)
		if aim_is_locked
		else Color(1.0, 0.365, 0.365, 1.0)
	)
	target_mark.color = aim_mark.color


func _set_cooldown_progress(progress: float) -> void:
	cooldown_fill.scale.x = clampf(progress, 0.0, 1.0)
	cooldown_fill.color = (
		Color(1.0, 0.78, 0.278, 1.0)
		if state == State.AIMING
		else Color(0.439, 0.827, 0.816, 1.0)
	)


func _update_muzzle_flash(delta: float) -> void:
	flash_time_remaining = maxf(flash_time_remaining - delta, 0.0)
	if is_zero_approx(flash_time_remaining):
		muzzle_flash.visible = false


func _update_shooter_animation(delta: float) -> void:
	if state == State.READY:
		ready_cycle = fmod(
			ready_cycle + delta * ready_cycle_frequency * TAU,
			TAU
		)

	_apply_shooter_visual()


func _apply_shooter_visual() -> void:
	var offset := Vector2.ZERO
	var rotation_offset := 0.0
	var body_scale_x := 1.0
	var body_scale_y := 1.0
	var lift := 0.0
	var marker_scale := 1.0

	match state:
		State.READY:
			var breath := 0.5 - 0.5 * cos(ready_cycle)
			lift = -ready_bob_height * breath
			body_scale_x = 1.0 - ready_breath_stretch * 0.35 * breath
			body_scale_y = 1.0 + ready_breath_stretch * breath
			rotation_offset = (
				facing_direction
				* aim_pose_lean
				* 0.12
				* sin(ready_cycle)
			)
		State.AIMING:
			var charge := _smoothstep01(_state_progress(aim_time))
			var lock_weight := 0.0
			if aim_is_locked:
				lock_weight = lerpf(
					0.65,
					1.0,
					_smoothstep01(_state_progress(aim_lock_time))
				)
			var brace := lerpf(charge * 0.72, 1.0, lock_weight)
			offset.x = facing_direction * aim_forward_offset * brace
			body_scale_x = 1.0 + aim_brace_squash * 0.45 * brace
			body_scale_y = 1.0 - aim_brace_squash * brace
			rotation_offset = facing_direction * aim_pose_lean * brace
			marker_scale = lerpf(1.0, locked_marker_scale, lock_weight)
		State.COOLDOWN:
			var recoil := _smoothstep01(
				clampf(
					flash_time_remaining
					/ maxf(muzzle_flash_time, 0.001),
					0.0,
					1.0
				)
			)
			var cooldown_weight := 1.0 - _smoothstep01(
				_state_progress(cooldown_time)
			)
			offset.x = (
				-fire_visual_direction * fire_recoil_offset * recoil
			)
			body_scale_x = (
				1.0
				+ fire_recoil_stretch * recoil
				+ cooldown_slump * 0.25 * cooldown_weight
			)
			body_scale_y = (
				1.0
				- fire_recoil_stretch * 0.35 * recoil
				- cooldown_slump * cooldown_weight
			)
			rotation_offset = (
				-fire_visual_direction
				* aim_pose_lean
				* 1.4
				* recoil
				- facing_direction
				* aim_pose_lean
				* 0.45
				* cooldown_weight
			)
		State.KNOCKBACK:
			var recoil := _smoothstep01(
				clampf(
					knockback_time_remaining
					/ maxf(knockback_lock_time, 0.001),
					0.0,
					1.0
				)
			)
			var settle := 1.0 - recoil
			offset.x = (
				-knockback_visual_direction
				* knockback_recoil_offset
				* recoil
			)
			body_scale_x = (
				1.0
				+ knockback_stretch * recoil
				+ cooldown_slump * 0.25 * settle
			)
			body_scale_y = 1.0 - cooldown_slump * settle
			rotation_offset = (
				-knockback_visual_direction
				* aim_pose_lean
				* 0.9
				* recoil
				- facing_direction
				* aim_pose_lean
				* 0.45
				* settle
			)

	offset.y = (
		lift
		+ VISUAL_HALF_HEIGHT
		* base_visual_scale_y
		* (1.0 - body_scale_y)
	)
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
	visual.rotation = base_visual_rotation + rotation_offset
	visual.scale = Vector2(
		facing_direction * base_visual_scale_x * body_scale_x,
		base_visual_scale_y * body_scale_y * hit_scale_y
	)
	aim_mark.scale = base_aim_mark_scale * marker_scale
	target_mark.scale = base_target_mark_scale * marker_scale


func _state_progress(duration: float) -> float:
	return clampf(
		1.0 - state_time_remaining / maxf(duration, 0.001),
		0.0,
		1.0
	)


func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

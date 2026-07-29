class_name ShooterEnemy
extends PatrolEnemy

signal shot_fired(projectile: ShooterProjectile)

enum State {
	READY,
	AIMING,
	COOLDOWN,
	KNOCKBACK,
}

@export_category("Ranged attack")
@export var line_length := 900.0
@export var aim_time := 0.7
@export var aim_lock_time := 0.23
@export var cooldown_time := 1.3
@export var muzzle_flash_time := 0.1
@export var projectile_scene: PackedScene = preload(
	"res://scenes/shooter_projectile.tscn"
)

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


func _ready() -> void:
	super()
	player = _find_player_sibling()
	_track_player()
	_enter_ready()


func _physics_process(delta: float) -> void:
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


func receive_impulse(impulse: Vector2) -> void:
	super(impulse)
	_cancel_aim()
	_track_player()
	state = State.KNOCKBACK
	_set_cooldown_progress(0.0)


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
	_set_cooldown_progress(1.0)


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

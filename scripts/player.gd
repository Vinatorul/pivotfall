class_name Player
extends CharacterBody2D

@export_category("Movement")
@export var move_speed := 260.0
@export var ground_acceleration := 1900.0
@export var ground_deceleration := 2300.0
@export var air_acceleration := 1100.0
@export var jump_velocity := -540.0
@export var maximum_fall_speed := 900.0

@export_category("Attack")
@export var attack_horizontal_impulse := 390.0
@export var attack_vertical_impulse := -170.0
@export var attack_active_time := 0.12
@export var attack_cooldown := 0.3

@export_category("Knockback")
@export var knockback_lock_time := 0.22
@export var knockback_drag := 520.0

@onready var visual: Node2D = $Visual
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
var struck_targets: Dictionary[int, bool] = {}


func _ready() -> void:
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.area_entered.connect(_on_attack_area_area_entered)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.physical_keycode == KEY_W:
		jump_requested = true
	elif event.physical_keycode in [KEY_X, KEY_J]:
		attack_requested = true


func _physics_process(delta: float) -> void:
	_update_attack_timers(delta)

	var direction := Input.get_axis("ui_left", "ui_right")

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

	var wants_to_jump := (
		Input.is_action_just_pressed("ui_accept")
		or Input.is_action_just_pressed("ui_up")
		or jump_requested
	)
	jump_requested = false

	if (
		not controls_locked
		and attack_requested
		and is_zero_approx(attack_cooldown_remaining)
	):
		_start_attack()
	attack_requested = false

	if is_on_floor():
		if wants_to_jump and not controls_locked:
			velocity.y = jump_velocity
	else:
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	move_and_slide()


func receive_impulse(impulse: Vector2) -> void:
	velocity = impulse
	knockback_time_remaining = knockback_lock_time
	jump_requested = false
	attack_requested = false


func _start_attack() -> void:
	attack_time_remaining = attack_active_time
	attack_cooldown_remaining = attack_cooldown
	struck_targets.clear()
	attack_visual.visible = true
	attack_area.monitoring = true


func _finish_attack() -> void:
	attack_time_remaining = 0.0
	attack_visual.visible = false
	attack_area.monitoring = false


func _update_attack_timers(delta: float) -> void:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)

	if is_zero_approx(attack_time_remaining):
		return

	attack_time_remaining = maxf(attack_time_remaining - delta, 0.0)
	if is_zero_approx(attack_time_remaining):
		_finish_attack()


func _on_attack_area_body_entered(body: Node2D) -> void:
	_try_apply_impulse(body)


func _on_attack_area_area_entered(area: Area2D) -> void:
	_try_apply_impulse(area)


func _try_apply_impulse(target: Node2D) -> void:
	if (
		is_zero_approx(attack_time_remaining)
		or not target.has_method("receive_impulse")
	):
		return

	var target_id := target.get_instance_id()
	if struck_targets.has(target_id):
		return

	struck_targets[target_id] = true
	target.call(
		"receive_impulse",
		Vector2(
			facing_direction * attack_horizontal_impulse,
			attack_vertical_impulse
		)
	)

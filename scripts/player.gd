class_name Player
extends CharacterBody2D

@export_category("Movement")
@export var move_speed := 260.0
@export var ground_acceleration := 1900.0
@export var ground_deceleration := 2300.0
@export var air_acceleration := 1100.0
@export var jump_velocity := -540.0
@export var maximum_fall_speed := 900.0

@onready var visual: Node2D = $Visual

var gravity: float = float(
	ProjectSettings.get_setting("physics/2d/default_gravity", 1500.0)
)
var jump_requested := false


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_W
	):
		jump_requested = true


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")

	if Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction += 1.0

	direction = clampf(direction, -1.0, 1.0)

	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	if is_zero_approx(direction):
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
	else:
		velocity.x = move_toward(
			velocity.x,
			direction * move_speed,
			acceleration * delta
		)
		visual.scale.x = signf(direction)

	var wants_to_jump := (
		Input.is_action_just_pressed("ui_accept")
		or Input.is_action_just_pressed("ui_up")
		or jump_requested
	)
	jump_requested = false

	if is_on_floor():
		if wants_to_jump:
			velocity.y = jump_velocity
	else:
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	move_and_slide()

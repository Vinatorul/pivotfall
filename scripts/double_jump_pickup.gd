class_name DoubleJumpPickup
extends Area2D

signal collected(player: Player)

@export_category("Idle animation")
@export_range(0.0, 4.0, 0.1) var bob_height := 2.0
@export_range(0.1, 4.0, 0.1) var bob_frequency := 1.0
@export_range(0.0, 0.2, 0.01) var pulse_scale := 0.05
@export_range(0.1, 4.0, 0.1) var pulse_frequency := 1.6

@onready var visual: Node2D = $Visual
@onready var glow: Polygon2D = $Visual/Glow

var is_collected := false
var animation_time := 0.0
var base_visual_position := Vector2.ZERO
var base_visual_scale := Vector2.ONE
var base_glow_color := Color.WHITE


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	base_visual_position = visual.position
	base_visual_scale = visual.scale
	base_glow_color = glow.color
	_apply_idle_visual()


func _process(delta: float) -> void:
	animation_time = fmod(animation_time + maxf(delta, 0.0), 1024.0)
	_apply_idle_visual()


func _on_body_entered(body: Node2D) -> void:
	if is_collected or not body is Player:
		return

	var player := body as Player
	if not player.unlock_double_jump():
		return

	is_collected = true
	set_process(false)
	set_deferred("monitoring", false)
	hide()
	collected.emit(player)
	queue_free()


func _apply_idle_visual() -> void:
	var bob := sin(animation_time * bob_frequency * TAU)
	var pulse := 0.5 + 0.5 * sin(
		animation_time * pulse_frequency * TAU
	)
	visual.position = base_visual_position + Vector2(0.0, bob * bob_height)
	visual.scale = base_visual_scale * (1.0 + pulse * pulse_scale)
	var glow_color := base_glow_color
	glow_color.a = base_glow_color.a * (0.72 + 0.28 * pulse)
	glow.color = glow_color

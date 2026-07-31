class_name ImpactBurst
extends Node2D

const GROUP_NAME := "impact_feedback"
const ACCENT_COLOR := Color(1.0, 0.72, 0.31, 1.0)
const CORE_COLOR := Color(0.98, 0.96, 0.82, 1.0)

var duration := 0.18
var elapsed := 0.0
var impact_direction := Vector2.RIGHT


func configure(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		impact_direction = direction.normalized()
	rotation = impact_direction.angle()
	queue_redraw()


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func _ready() -> void:
	z_index = 100
	queue_redraw()


func _process(delta: float) -> void:
	elapsed = minf(elapsed + delta, duration)
	queue_redraw()
	if elapsed >= duration:
		queue_free()


func _draw() -> void:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	var fade := 1.0 - progress
	var ring_radius := lerpf(5.0, 24.0, progress)
	var line_width := lerpf(4.0, 1.2, progress)

	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		24,
		Color(
			ACCENT_COLOR.r,
			ACCENT_COLOR.g,
			ACCENT_COLOR.b,
			fade * 0.85
		),
		line_width,
		true
	)
	draw_circle(
		Vector2.ZERO,
		lerpf(7.0, 2.0, progress),
		Color(
			CORE_COLOR.r,
			CORE_COLOR.g,
			CORE_COLOR.b,
			fade
		)
	)

	for index: int in range(7):
		var ray_angle := lerpf(
			-1.15,
			1.15,
			float(index) / 6.0
		)
		var ray_direction := Vector2.RIGHT.rotated(ray_angle)
		var ray_start := ray_direction * lerpf(
			5.0,
			12.0,
			progress
		)
		var ray_end := ray_direction * lerpf(
			22.0,
			34.0,
			progress
		)
		draw_line(
			ray_start,
			ray_end,
			Color(
				ACCENT_COLOR.r,
				ACCENT_COLOR.g,
				ACCENT_COLOR.b,
				fade
			),
			line_width,
			true
		)

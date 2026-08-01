class_name EnemyEliminationBurst
extends Node2D

const ELIMINATION_ACCENT := Color(0.439, 0.827, 0.816, 1.0)
const CLEAR_ACCENT := Color(0.72, 1.0, 0.58, 1.0)

@export_range(0.1, 0.8, 0.01) var elimination_duration := 0.34
@export_range(0.1, 0.8, 0.01) var clear_duration := 0.46
@export_range(0.0, 48.0, 1.0) var horizontal_travel := 18.0
@export_range(0.0, 80.0, 1.0) var drop_distance := 38.0
@export_range(0.0, 32.0, 1.0) var visual_lift := 14.0
@export_range(0.0, 1.5, 0.01) var spin_radians := 0.52

var elapsed := 0.0
var active_duration := 0.34
var fall_direction := Vector2.DOWN
var source_color := ELIMINATION_ACCENT
var accent_color := ELIMINATION_ACCENT
var clears_arena := false
var source_world_position := Vector2.ZERO
var origin_position := Vector2.ZERO
var spin_direction := 1.0
var is_configured := false


func configure(
	world_position: Vector2,
	direction: Vector2,
	color: Color,
	is_clear: bool
) -> void:
	source_world_position = world_position
	var visual_world_position := world_position + Vector2.UP * visual_lift
	if is_inside_tree():
		global_position = visual_world_position
		origin_position = position
	else:
		position = visual_world_position
		origin_position = visual_world_position
	fall_direction = direction.normalized()
	if fall_direction.is_zero_approx():
		fall_direction = Vector2.DOWN
	source_color = color
	clears_arena = is_clear
	accent_color = CLEAR_ACCENT if clears_arena else ELIMINATION_ACCENT
	active_duration = clear_duration if clears_arena else elimination_duration
	spin_direction = signf(fall_direction.x)
	if is_zero_approx(spin_direction):
		spin_direction = 1.0
	is_configured = true


func _ready() -> void:
	z_index = 20
	if not is_configured:
		origin_position = position
	queue_redraw()


func _process(delta: float) -> void:
	elapsed = minf(
		elapsed + maxf(delta, 0.0),
		maxf(active_duration, 0.001)
	)
	var progress := _progress()
	var travel_progress := smoothstep(0.0, 1.0, progress)
	position = origin_position + Vector2(
		fall_direction.x * horizontal_travel * travel_progress,
		drop_distance * travel_progress
	)
	rotation = spin_direction * spin_radians * travel_progress
	var scale_value := lerpf(
		1.0,
		0.28,
		smoothstep(0.18, 1.0, progress)
	)
	scale = Vector2.ONE * scale_value
	queue_redraw()
	if elapsed >= maxf(active_duration, 0.001):
		queue_free()


func _draw() -> void:
	var progress := _progress()
	var fade := 1.0 - smoothstep(0.32, 1.0, progress)
	var burst := sin(progress * PI)
	var clear_scale := 1.22 if clears_arena else 1.0
	var core_half_size := lerpf(14.0, 4.0, progress) * clear_scale
	var tint := source_color.lerp(accent_color, 0.52 + burst * 0.3)
	var core_color := Color(tint.r, tint.g, tint.b, fade)
	var diamond := PackedVector2Array([
		Vector2(-core_half_size, 0.0),
		Vector2(0.0, -core_half_size),
		Vector2(core_half_size, 0.0),
		Vector2(0.0, core_half_size),
	])
	draw_colored_polygon(diamond, core_color)

	var ring_radius := lerpf(8.0, 34.0, progress) * clear_scale
	var ring_alpha := fade * (0.38 + burst * 0.62)
	var ring_color := Color(
		accent_color.r,
		accent_color.g,
		accent_color.b,
		ring_alpha
	)
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		32,
		ring_color,
		2.5 if clears_arena else 2.0,
		true
	)

	var spoke_count := 10 if clears_arena else 6
	for spoke_index: int in spoke_count:
		var angle := (
			TAU * float(spoke_index) / float(spoke_count)
			+ progress * 0.7 * spin_direction
		)
		var spoke_start := Vector2.from_angle(angle) * (
			ring_radius * 0.56
		)
		var spoke_end := Vector2.from_angle(angle) * (
			ring_radius * (0.88 + burst * 0.24)
		)
		draw_line(
			spoke_start,
			spoke_end,
			ring_color,
			2.0 if clears_arena else 1.5,
			true
		)

	if clears_arena:
		var halo_color := Color(
			CLEAR_ACCENT.r,
			CLEAR_ACCENT.g,
			CLEAR_ACCENT.b,
			fade * burst * 0.55
		)
		draw_arc(
			Vector2.ZERO,
			ring_radius * 1.35,
			0.0,
			TAU,
			40,
			halo_color,
			1.5,
			true
		)


func _progress() -> float:
	return clampf(
		elapsed / maxf(active_duration, 0.001),
		0.0,
		1.0
	)

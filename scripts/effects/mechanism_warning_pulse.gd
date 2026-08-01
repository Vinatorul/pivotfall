class_name MechanismWarningPulse
extends RefCounted

var outline: Line2D
var base_width := 0.0
var width_boost := 3.0
var duration := 0.001
var elapsed := 0.0
var active := false


func bind(outline_node: Line2D, boost := 3.0) -> void:
	outline = outline_node
	base_width = outline.width
	width_boost = boost
	finish()


func begin(pulse_duration: float) -> void:
	if not is_instance_valid(outline):
		return

	duration = maxf(pulse_duration, 0.001)
	elapsed = 0.0
	active = true
	_apply_width(0.0)


func advance(delta: float) -> void:
	if not active:
		return

	elapsed = minf(elapsed + maxf(delta, 0.0), duration)
	_apply_width(elapsed / duration)
	if elapsed >= duration:
		finish()


func finish() -> void:
	active = false
	elapsed = 0.0
	if is_instance_valid(outline):
		outline.width = base_width


func _apply_width(progress: float) -> void:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var decay := 1.0 - clamped_progress
	var beat := 0.72 + 0.28 * cos(clamped_progress * TAU * 2.0)
	outline.width = base_width + width_boost * decay * beat

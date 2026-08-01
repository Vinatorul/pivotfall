class_name ArenaHazardFeedback
extends Node

const ALERT_EDGE_COLOR := Color(1.0, 0.78, 0.36, 1.0)
const ALERT_BAND_COLOR := Color(0.15, 0.035, 0.055, 1.0)
const ELIMINATION_EDGE_COLOR := Color(0.439, 0.827, 0.816, 1.0)
const ELIMINATION_BAND_COLOR := Color(0.025, 0.09, 0.11, 1.0)
const CLEAR_EDGE_COLOR := Color(0.72, 1.0, 0.58, 1.0)
const CLEAR_BAND_COLOR := Color(0.035, 0.13, 0.075, 1.0)

enum AlertKind {
	NONE,
	FALL,
	ELIMINATION,
	CLEAR,
}

@export_node_path var pit_band_path: NodePath
@export_node_path var pit_edge_path: NodePath
@export_range(0.1, 3.0, 0.05) var idle_frequency := 0.55
@export_range(0.0, 3.0, 0.05) var idle_width_boost := 0.35
@export_range(0.0, 8.0, 0.1) var alert_width_boost := 2.6
@export_range(0.0, 8.0, 0.1) var elimination_width_boost := 3.2
@export_range(0.0, 8.0, 0.1) var clear_width_boost := 4.8
@export_range(0.05, 0.5, 0.01) var alert_duration := 0.18

@onready var pit_band: Polygon2D = get_node_or_null(
	pit_band_path
) as Polygon2D
@onready var pit_edge: Line2D = get_node_or_null(
	pit_edge_path
) as Line2D

var base_band_color := Color.WHITE
var base_edge_color := Color.WHITE
var base_edge_width := 0.0
var idle_cycle := 0.0
var alert_elapsed := 0.0
var is_alerting := false
var alert_kind := AlertKind.NONE
var fall_count := 0
var elimination_count := 0
var clear_count := 0


func _ready() -> void:
	if not is_instance_valid(pit_band) or not is_instance_valid(pit_edge):
		push_error("Arena hazard feedback is missing pit visuals.")
		set_process(false)
		return

	base_band_color = pit_band.color
	base_edge_color = pit_edge.default_color
	base_edge_width = pit_edge.width
	_apply_visual()


func _process(delta: float) -> void:
	idle_cycle = fmod(
		idle_cycle + maxf(delta, 0.0) * idle_frequency,
		1.0
	)
	if is_alerting:
		alert_elapsed = minf(
			alert_elapsed + maxf(delta, 0.0),
			maxf(alert_duration, 0.001)
		)
		if alert_elapsed >= maxf(alert_duration, 0.001):
			is_alerting = false
			alert_kind = AlertKind.NONE
	_apply_visual()


func play_fall() -> bool:
	if (
		not is_instance_valid(pit_band)
		or not is_instance_valid(pit_edge)
		or (
			is_alerting
			and alert_kind == AlertKind.FALL
		)
	):
		return false

	fall_count += 1
	_start_alert(AlertKind.FALL)
	return true


func play_elimination(clears_arena: bool) -> bool:
	if not is_instance_valid(pit_band) or not is_instance_valid(pit_edge):
		return false

	elimination_count += 1
	if clears_arena:
		clear_count += 1
	_start_alert(
		AlertKind.CLEAR
		if clears_arena
		else AlertKind.ELIMINATION
	)
	return true


func _start_alert(kind: int) -> void:
	alert_kind = kind
	alert_elapsed = 0.0
	is_alerting = true
	_apply_visual()


func _apply_visual() -> void:
	if not is_instance_valid(pit_band) or not is_instance_valid(pit_edge):
		return

	var idle_wave := 0.5 + 0.5 * sin(idle_cycle * TAU)
	var alert_strength := 0.0
	var alert_edge_color := ALERT_EDGE_COLOR
	var alert_band_color := ALERT_BAND_COLOR
	var active_width_boost := alert_width_boost
	match alert_kind:
		AlertKind.ELIMINATION:
			alert_edge_color = ELIMINATION_EDGE_COLOR
			alert_band_color = ELIMINATION_BAND_COLOR
			active_width_boost = elimination_width_boost
		AlertKind.CLEAR:
			alert_edge_color = CLEAR_EDGE_COLOR
			alert_band_color = CLEAR_BAND_COLOR
			active_width_boost = clear_width_boost
	if is_alerting:
		var progress := clampf(
			alert_elapsed / maxf(alert_duration, 0.001),
			0.0,
			1.0
		)
		var decay := 1.0 - smoothstep(0.0, 1.0, progress)
		var beat := 0.78 + 0.22 * cos(progress * TAU * 2.0)
		alert_strength = decay * beat

	var idle_alpha := base_edge_color.a * lerpf(
		0.72,
		1.0,
		idle_wave
	)
	var idle_color := Color(
		base_edge_color.r,
		base_edge_color.g,
		base_edge_color.b,
		idle_alpha
	)
	pit_edge.width = (
		base_edge_width
		+ idle_width_boost * idle_wave
		+ active_width_boost * alert_strength
	)
	pit_edge.default_color = idle_color.lerp(
		alert_edge_color,
		alert_strength
	)
	pit_band.color = base_band_color.lerp(
		alert_band_color,
		alert_strength * 0.35
	)

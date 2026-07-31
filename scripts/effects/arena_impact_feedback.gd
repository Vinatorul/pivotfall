class_name ArenaImpactFeedback
extends Node

@export_category("Camera shake")
@export_range(0.01, 0.5, 0.01) var shake_duration := 0.12
@export_range(0.0, 16.0, 0.5) var enemy_shake_strength := 5.0
@export_range(0.0, 16.0, 0.5) var mechanism_shake_strength := 2.5
@export_range(1.0, 120.0, 1.0) var shake_frequency := 48.0

@export_category("Impact sound")
@export_range(0.02, 0.25, 0.01) var sound_duration := 0.08
@export_range(8000, 48000, 50) var sound_mix_rate := 22050
@export_range(-40.0, 0.0, 1.0) var enemy_volume_db := -8.0
@export_range(-40.0, 0.0, 1.0) var mechanism_volume_db := -11.0
@export_range(0.5, 2.0, 0.01) var enemy_pitch_scale := 0.92
@export_range(0.5, 2.0, 0.01) var mechanism_pitch_scale := 1.18
@export var play_audio_in_headless := false

@onready var camera: Camera2D = $Camera
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

var shake_time_remaining := 0.0
var shake_elapsed := 0.0
var shake_direction := Vector2.RIGHT
var active_shake_strength := 0.0
var impact_count := 0
var sound_play_count := 0
var last_impact_direction := Vector2.RIGHT
var last_impact_was_enemy := false
var impact_stream: AudioStreamWAV
var base_camera_offset := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	audio_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	base_camera_offset = camera.offset
	impact_stream = _build_impact_stream()
	audio_player.stream = impact_stream
	set_process(false)


func _process(delta: float) -> void:
	shake_elapsed += delta
	shake_time_remaining = maxf(shake_time_remaining - delta, 0.0)
	if is_zero_approx(shake_time_remaining):
		_finish_shake()
		return

	var decay := shake_time_remaining / maxf(shake_duration, 0.001)
	var phase := shake_elapsed * shake_frequency
	var perpendicular := Vector2(-shake_direction.y, shake_direction.x)
	camera.offset = base_camera_offset + (
		-shake_direction * cos(phase)
		+ perpendicular * sin(phase * 1.37) * 0.42
	) * active_shake_strength * decay


func play_impact(direction: Vector2, hit_enemy: bool) -> void:
	var normalized_direction := direction.normalized()
	if normalized_direction.is_zero_approx():
		normalized_direction = Vector2.RIGHT

	impact_count += 1
	last_impact_direction = normalized_direction
	last_impact_was_enemy = hit_enemy
	shake_direction = normalized_direction
	active_shake_strength = (
		enemy_shake_strength
		if hit_enemy
		else mechanism_shake_strength
	)
	shake_elapsed = 0.0
	shake_time_remaining = shake_duration
	camera.offset = (
		base_camera_offset
		- shake_direction * active_shake_strength
	)
	set_process(true)

	audio_player.volume_db = (
		enemy_volume_db
		if hit_enemy
		else mechanism_volume_db
	)
	audio_player.pitch_scale = (
		enemy_pitch_scale
		if hit_enemy
		else mechanism_pitch_scale
	)
	if (
		DisplayServer.get_name() != "headless"
		or play_audio_in_headless
	):
		audio_player.play()
		sound_play_count += 1


func cancel_feedback() -> void:
	_finish_shake()
	if is_instance_valid(audio_player):
		audio_player.stop()


func is_shaking() -> bool:
	return shake_time_remaining > 0.0


func _finish_shake() -> void:
	shake_time_remaining = 0.0
	shake_elapsed = 0.0
	active_shake_strength = 0.0
	if is_instance_valid(camera):
		camera.offset = base_camera_offset
	set_process(false)


func _build_impact_stream() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sound_mix_rate
	stream.stereo = false

	var sample_count := maxi(
		roundi(sound_duration * float(sound_mix_rate)),
		1
	)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for sample_index: int in sample_count:
		var progress := float(sample_index) / float(sample_count)
		var time := float(sample_index) / float(sound_mix_rate)
		var envelope := pow(1.0 - progress, 2.4)
		var frequency := lerpf(190.0, 92.0, progress)
		var body := sin(TAU * frequency * time)
		var click_seed := sin(float(sample_index) * 12.9898) * 43758.5453
		var click := (click_seed - floorf(click_seed)) * 2.0 - 1.0
		var sample := (body * 0.72 + click * 0.28) * envelope * 0.78
		var signed_value := clampi(
			roundi(sample * 32767.0),
			-32768,
			32767
		)
		var encoded_value := signed_value
		if encoded_value < 0:
			encoded_value += 65536
		data[sample_index * 2] = encoded_value & 0xff
		data[sample_index * 2 + 1] = (encoded_value >> 8) & 0xff

	stream.data = data
	return stream


func _exit_tree() -> void:
	cancel_feedback()
	if is_instance_valid(audio_player):
		audio_player.stream = null
	impact_stream = null
	if is_instance_valid(camera):
		camera.enabled = false

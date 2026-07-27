class_name Arena
extends Node2D

@export var fall_restart_delay := 0.45
@export var clear_restart_delay := 1.25

@onready var death_zone: Area2D = $DeathZone
@onready var status_label: Label = $UI/Status

var enemies_remaining := 0
var restart_scheduled := false


func _ready() -> void:
	enemies_remaining = get_tree().get_nodes_in_group("enemies").size()
	death_zone.body_entered.connect(_on_death_zone_body_entered)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.physical_keycode == KEY_R
	):
		_reload_scene()


func _on_death_zone_body_entered(body: Node2D) -> void:
	if restart_scheduled:
		return

	if body is Player:
		status_label.text = "ПАДЕНИЕ  /  ПЕРЕЗАПУСК..."
		_schedule_restart(fall_restart_delay)
		return

	if body.is_in_group("enemies"):
		body.queue_free()
		enemies_remaining = maxi(enemies_remaining - 1, 0)

		if enemies_remaining == 0:
			status_label.text = "АРЕНА ПРОЙДЕНА  /  ПЕРЕЗАПУСК..."
			_schedule_restart(clear_restart_delay)


func _schedule_restart(delay: float) -> void:
	restart_scheduled = true
	get_tree().create_timer(delay).timeout.connect(_reload_scene)


func _reload_scene() -> void:
	get_tree().reload_current_scene()

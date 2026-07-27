class_name Arena
extends Node2D

enum Outcome {
	NONE,
	CLEAR,
	FALL,
}

@export var fall_restart_delay := 0.45
@export var clear_restart_delay := 1.25
@export_file("*.tscn") var next_arena_path := ""
@export var clear_message := "АРЕНА ПРОЙДЕНА  /  ПЕРЕЗАПУСК..."

@onready var death_zone: Area2D = $DeathZone
@onready var status_label: Label = $UI/Status

var enemies_remaining := 0
var restart_scheduled := false
var advance_after_delay := false
var pending_outcome := Outcome.NONE
var outcome_generation := 0


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
	if body is Player:
		if pending_outcome == Outcome.FALL:
			return

		status_label.text = "ПАДЕНИЕ  /  ПЕРЕЗАПУСК..."
		_schedule_outcome(fall_restart_delay, false, Outcome.FALL)
		return

	if restart_scheduled:
		return

	if body.is_in_group("enemies"):
		body.queue_free()
		enemies_remaining = maxi(enemies_remaining - 1, 0)

		if enemies_remaining == 0:
			status_label.text = clear_message
			_schedule_outcome(
				clear_restart_delay,
				not next_arena_path.is_empty(),
				Outcome.CLEAR
			)


func _schedule_outcome(
	delay: float,
	should_advance: bool,
	outcome: Outcome
) -> void:
	restart_scheduled = true
	advance_after_delay = should_advance
	pending_outcome = outcome
	outcome_generation += 1
	get_tree().create_timer(delay, false).timeout.connect(
		_finish_outcome.bind(outcome_generation)
	)


func _finish_outcome(generation: int) -> void:
	if generation != outcome_generation:
		return

	if advance_after_delay:
		var change_error := get_tree().change_scene_to_file(next_arena_path)
		if change_error == OK:
			return

		push_error(
			"Could not open the next arena '%s' (error %d)."
			% [next_arena_path, change_error]
		)

	_reload_scene()


func _reload_scene() -> void:
	get_tree().reload_current_scene()

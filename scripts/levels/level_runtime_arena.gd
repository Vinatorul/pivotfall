class_name LevelRuntimeArena
extends Arena

signal embedded_restart_requested
signal campaign_advance_requested
signal campaign_completed_requested
signal campaign_restart_requested(outcome: int)

const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_BUILDER := preload(
	"res://scripts/levels/level_builder.gd"
)

@export_file("*.json") var level_path := ""

@onready var title_label: Label = $UI/Title
@onready var controls_label: Label = $UI/Controls
@onready var impact_feedback: ArenaImpactFeedback = $ImpactFeedback

var level_loaded := false
var level_data: Dictionary = {}
var level_objects: Dictionary = {}
var load_errors: Array[String] = []
var embedded_mode := false
var campaign_mode := false

var _embedded_snapshot_json := ""
var _campaign_snapshot_json := ""
var _campaign_has_next := false
var _campaign_advance_message := ""


func configure_embedded_snapshot(json_text: String) -> void:
	if is_inside_tree():
		push_error(
			"Embedded level snapshot must be configured before entering the tree."
		)
		return
	if campaign_mode:
		push_error(
			"Campaign and embedded level modes are mutually exclusive."
		)
		return

	embedded_mode = true
	_embedded_snapshot_json = json_text


func configure_campaign_snapshot(
	json_text: String,
	has_next: bool,
	advance_message: String
) -> void:
	if is_inside_tree():
		push_error(
			"Campaign level snapshot must be configured before entering the tree."
		)
		return
	if embedded_mode:
		push_error(
			"Campaign and embedded level modes are mutually exclusive."
		)
		return
	if campaign_mode:
		push_error("Campaign level snapshot is already configured.")
		return

	campaign_mode = true
	_campaign_snapshot_json = json_text
	_campaign_has_next = has_next
	_campaign_advance_message = advance_message


func _ready() -> void:
	if campaign_mode:
		controls_label.text += "    Esc — пауза"
	elif embedded_mode:
		controls_label.text += "    Esc — в редактор"

	var load_result: Dictionary
	if campaign_mode:
		load_result = LEVEL_DATA_CODEC.decode_text(
			_campaign_snapshot_json
		)
	elif embedded_mode:
		load_result = LEVEL_DATA_CODEC.decode_text(
			_embedded_snapshot_json
		)
	else:
		load_result = LEVEL_DATA_CODEC.load_file(level_path)
	if not bool(load_result["ok"]):
		_show_load_failure(load_result["errors"])
		return

	level_data = load_result["data"]
	var build_result: Dictionary = LEVEL_BUILDER.build_into(
		self,
		level_data
	)
	if not bool(build_result["ok"]):
		_show_load_failure(build_result["errors"])
		return

	level_objects = build_result["objects"]
	var player := _find_runtime_player()
	if is_instance_valid(player):
		player.attack_landed.connect(_on_player_attack_landed)
	title_label.text = level_data["title"]
	status_label.text = level_data["objective"]
	clear_message = (
		_campaign_advance_message
		if campaign_mode and _campaign_has_next
		else level_data["clear_message"]
	)
	level_loaded = true
	super._ready()


func get_level_object(object_id: String) -> Node:
	return level_objects.get(object_id) as Node


func _find_runtime_player() -> Player:
	for level_object: Node in level_objects.values():
		if level_object is Player:
			return level_object as Player
	return null


func _on_player_attack_landed(
	target: Node2D,
	_impact_position: Vector2,
	impulse: Vector2
) -> void:
	impact_feedback.play_impact(
		impulse,
		target.is_in_group("enemies")
	)


func _play_combat_defeat_feedback(
	impact_direction: Vector2
) -> void:
	impact_feedback.play_defeat(impact_direction)


func _should_advance_after_clear() -> bool:
	if campaign_mode:
		return true
	return super._should_advance_after_clear()


func _advance_arena() -> bool:
	if campaign_mode:
		if _campaign_has_next:
			campaign_advance_requested.emit()
		else:
			campaign_completed_requested.emit()
		return true
	return super._advance_arena()


func _reload_scene() -> void:
	if embedded_mode:
		embedded_restart_requested.emit()
		return
	if campaign_mode:
		campaign_restart_requested.emit(int(pending_outcome))
		return

	super._reload_scene()


func _show_load_failure(errors: Array) -> void:
	load_errors.clear()
	for error: Variant in errors:
		load_errors.append(str(error))

	title_label.text = "DATA ARENA  /  ОШИБКА ЗАГРУЗКИ"
	status_label.text = (
		load_errors[0]
		if not load_errors.is_empty()
		else "Неизвестная ошибка уровня."
	)
	set_process_input(false)

	for error: String in load_errors:
		push_error(error)

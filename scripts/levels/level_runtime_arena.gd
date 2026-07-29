class_name LevelRuntimeArena
extends Arena

const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_BUILDER := preload(
	"res://scripts/levels/level_builder.gd"
)

@export_file("*.json") var level_path := ""

@onready var title_label: Label = $UI/Title

var level_loaded := false
var level_data: Dictionary = {}
var level_objects: Dictionary = {}
var load_errors: Array[String] = []


func _ready() -> void:
	var load_result: Dictionary = LEVEL_DATA_CODEC.load_file(level_path)
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
	title_label.text = level_data["title"]
	status_label.text = level_data["objective"]
	clear_message = level_data["clear_message"]
	level_loaded = true
	super._ready()


func get_level_object(object_id: String) -> Node:
	return level_objects.get(object_id) as Node


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

class_name LevelRuntimeArena
extends Arena

signal embedded_restart_requested
signal embedded_exit_requested
signal pause_requested
signal help_requested
signal campaign_advance_requested
signal campaign_completed_requested
signal campaign_restart_requested(outcome: int)

const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_BUILDER := preload(
	"res://scripts/levels/level_builder.gd"
)
const ENEMY_ELIMINATION_BURST_SCRIPT := preload(
	"res://scripts/effects/enemy_elimination_burst.gd"
)

const PAUSE_MENU_SCENE := preload("res://scenes/campaign_pause_menu.tscn")
const CAMPAIGN_STORAGE := preload("res://scripts/campaign/campaign_storage.gd")

@export_file("*.json") var level_path := ""

var local_pause_menu: CampaignPauseMenu
var _resume_generation := 0

@onready var title_label: Label = $UI/Title
@onready var controls_label: Label = $UI/Controls
@onready var progress_label: Label = $UI/Progress
@onready var help_button: Button = $UI/Help
@onready var pause_button: Button = $UI/Pause
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
	_configure_hud()

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
	_set_level_title()
	status_label.text = ""
	status_label.visible = false
	clear_message = (
		_campaign_advance_message
		if campaign_mode and _campaign_has_next
		else level_data["clear_message"]
	)
	if "DATA ARENA" in clear_message:
		clear_message = "Арена пройдена" if campaign_mode else "Арена пройдена · Перезапуск…"
	level_loaded = true
	super._ready()


func _configure_hud() -> void:
	controls_label.hide()
	help_button.pressed.connect(_request_help)
	pause_button.pressed.connect(_request_pause)
	get_viewport().size_changed.connect(_update_hud_layout)
	_update_hud_layout()
	if campaign_mode:
		return
	local_pause_menu = PAUSE_MENU_SCENE.instantiate() as CampaignPauseMenu
	add_child(local_pause_menu)
	local_pause_menu.resume_requested.connect(_resume_local_menu)
	local_pause_menu.restart_requested.connect(_restart_from_local_menu)
	local_pause_menu.main_menu_requested.connect(_leave_local_menu)


func _update_hud_layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport().get_visible_rect().size
	var window_size := Vector2(get_window().size)
	var display_scale := minf(window_size.x / view.x, window_size.y / view.y)
	var compact := view.x * display_scale < 640.0
	var unit := 1.0 / display_scale if compact else 1.0
	var width := view.x / unit
	var top_shift := maxf(0.0, 42.0 * display_scale - 8.0) if embedded_mode and compact else 0.0
	var title_rect := Rect2(12, 12, width - 136, 22) if compact else Rect2(52, 48, width - 358, 44)
	var progress_rect := (
		Rect2(12, 36, width - 136, 18) if compact else Rect2(width - 286, 48, 130, 44)
	)
	var help_rect := Rect2(width - 108, 12, 44, 44) if compact else Rect2(width - 144, 48, 52, 44)
	var pause_rect := Rect2(width - 56, 12, 44, 44) if compact else Rect2(width - 76, 48, 52, 44)
	var status_rect := Rect2(12, 70, width - 24, 58) if compact else Rect2(52, 108, width - 104, 58)
	progress_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_RIGHT
	)
	for item: Array in [
		[title_label, title_rect, 16 if compact else 20],
		[progress_label, progress_rect, 12 if compact else 17],
		[help_button, help_rect, 22],
		[pause_button, pause_rect, 22],
		[status_label, status_rect, 18 if compact else 22],
	]:
		_place_hud_item(item[0], item[1], item[2], unit, top_shift)


func _place_hud_item(
	control: Control, rect: Rect2, font_size: int, unit: float, top_shift: float
) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.add_theme_font_size_override("font_size", roundi(font_size * unit))
	control.position = (rect.position + Vector2(0, top_shift)) * unit
	control.size = rect.size * unit


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode if event.physical_keycode else event.keycode
	if key == KEY_H:
		_request_help()
	elif key == KEY_ESCAPE and not campaign_mode and not embedded_mode:
		_request_pause()
	else:
		super._input(event)
		return
	get_viewport().set_input_as_handled()


func _set_level_title() -> void:
	title_label.text = str(level_data["title"])
	progress_label.text = "Тест" if embedded_mode else ""
	if campaign_mode:
		return
	var entries := CAMPAIGN_STORAGE.list_builtin_levels()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if entry["id"] == level_data.get("level_id", ""):
			title_label.text = _compact_title(str(entry["title"]))
			if not embedded_mode:
				progress_label.text = "%d/%d" % [index + 1, entries.size()]
			return


func set_campaign_hud(title: String, progress: String) -> void:
	title_label.text = _compact_title(title)
	progress_label.text = progress


func _compact_title(title: String) -> String:
	return title.trim_prefix("Arena ").replace(" / ", " · ")


func get_arena_title() -> String:
	return title_label.text


func get_help_text() -> String:
	var text := str(level_data.get("objective", ""))
	var types: Array[String] = []
	for object: Dictionary in level_data.get("objects", []):
		var object_type := str(object.get("type", ""))
		if not types.has(object_type):
			types.append(object_type)
	if types.has("pressure_plate"):
		text += (
			"\n\nПлита нажата, пока на ней стоит герой или враг. "
			+ "Без груза связанный мост или стена возвращается в исходное состояние."
		)
	if types.has("double_jump_pickup"):
		text += (
			"\n\nУсилитель даёт второй прыжок в воздухе. " + "Подбери его и нажми прыжок ещё раз."
		)
	text += (
		"\n\nУдар отбрасывает. Устраняй врагов окружением. "
		+ "Касание врага, его атака, яма и шипы смертельны."
	)
	return text


func _request_help() -> void:
	if campaign_mode:
		help_requested.emit()
	else:
		open_local_pause_menu(true)


func _request_pause() -> void:
	if campaign_mode:
		pause_requested.emit()
	else:
		open_local_pause_menu()


func open_local_pause_menu(show_help: bool = false) -> bool:
	if not level_loaded or not is_instance_valid(local_pause_menu):
		return false
	var opened := local_pause_menu.open_menu(
		get_arena_title(),
		get_help_text(),
		DisplayServer.is_touchscreen_available(),
		embedded_mode,
		show_help
	)
	if opened:
		process_mode = Node.PROCESS_MODE_DISABLED
	return opened


func close_local_pause_menu() -> void:
	_resume_generation += 1
	if is_instance_valid(local_pause_menu):
		local_pause_menu.close_menu()


func is_local_pause_open() -> bool:
	return is_instance_valid(local_pause_menu) and local_pause_menu.is_open()


func _resume_local_menu() -> void:
	close_local_pause_menu()
	await resume_after_menu()


func resume_after_menu() -> void:
	_resume_generation += 1
	var generation := _resume_generation
	process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().physics_frame
	await get_tree().process_frame
	if generation != _resume_generation:
		return
	var player := _find_runtime_player()
	if is_instance_valid(player):
		player.jump_requested = false
		player.attack_requested = false
	process_mode = Node.PROCESS_MODE_INHERIT


func _restart_from_local_menu() -> void:
	close_local_pause_menu()
	_reload_scene()


func _leave_local_menu() -> void:
	close_local_pause_menu()
	if embedded_mode:
		embedded_exit_requested.emit()
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _schedule_outcome(delay: float, should_advance: bool, outcome: Outcome) -> bool:
	var scheduled := super._schedule_outcome(delay, should_advance, outcome)
	if scheduled:
		status_label.show()
	return scheduled


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


func _play_enemy_elimination_feedback(
	world_position: Vector2,
	fall_direction: Vector2,
	source_color: Color,
	clears_arena: bool
) -> void:
	impact_feedback.play_enemy_elimination(
		world_position,
		fall_direction,
		clears_arena
	)
	var effects_parent := get_node_or_null("Actors") as Node2D
	if not is_instance_valid(effects_parent):
		return
	var burst := ENEMY_ELIMINATION_BURST_SCRIPT.new() as EnemyEliminationBurst
	effects_parent.add_child(burst)
	burst.configure(
		world_position,
		fall_direction,
		source_color,
		clears_arena
	)


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

	title_label.text = "Не удалось загрузить арену"
	status_label.show()
	status_label.text = (
		load_errors[0]
		if not load_errors.is_empty()
		else "Неизвестная ошибка уровня."
	)
	set_process_input(false)

	for error: String in load_errors:
		push_error(error)

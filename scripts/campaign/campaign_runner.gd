class_name CampaignRunner
extends Node2D

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const CAMPAIGN_DATA_VALIDATOR := preload(
	"res://scripts/campaign/campaign_data_validator.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_RUNTIME_SCENE := preload(
	"res://scenes/data_arena_01.tscn"
)
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const COMPLETION_CLEAR_MESSAGE := (
	"КАМПАНИЯ ПРОЙДЕНА  /  ФИНАЛ..."
)

enum Phase {
	BOOTING,
	INTRO,
	PLAYING,
	REPLACING,
	COMPLETED,
	FAILED,
}

@export_range(0.0, 5.0, 0.05) var intro_duration := 0.9

@onready var runtime_host: Node2D = $RuntimeHost
@onready var progress_backing: ColorRect = $CampaignUI/ProgressBacking
@onready var progress_label: Label = $CampaignUI/Progress
@onready var intro_ui: Control = $CampaignUI/Intro
@onready var intro_title: Label = $CampaignUI/Intro/Panel/Title
@onready var intro_meta: Label = $CampaignUI/Intro/Panel/Meta
@onready var completion_ui: Control = $CampaignUI/Completion
@onready var completion_count: Label = $CampaignUI/Completion/Panel/Count
@onready var failure_ui: CanvasLayer = $FailureUI
@onready var failure_label: Label = $FailureUI/Panel/Message

var campaign_data: Dictionary = {}
var campaign_entries: Array[Dictionary] = []
var load_errors: Array[String] = []
var current_runtime: LevelRuntimeArena
var current_level_index := -1
var transition_generation := 0
var transitioning := false
var campaign_completed := false
var intro_active := false
var phase := Phase.BOOTING

var _snapshots_by_id: Dictionary = {}
var _intro_generation := 0


func _ready() -> void:
	_set_debug_selector_suppressed(false)
	var campaign_result: Dictionary = (
		CAMPAIGN_STORAGE.load_builtin_campaign()
	)
	if not bool(campaign_result.get("ok", false)):
		_show_failure(campaign_result.get("errors", []))
		return

	campaign_data = (
		campaign_result.get("data", {}) as Dictionary
	).duplicate(true)
	if not CAMPAIGN_DATA_VALIDATOR.FINAL_BEHAVIORS.has(
		str(campaign_data.get("final_behavior", ""))
	):
		_show_failure(["Campaign final behavior is not supported."])
		return
	for raw_entry: Variant in campaign_result.get("entries", []):
		if typeof(raw_entry) == TYPE_DICTIONARY:
			campaign_entries.append(
				(raw_entry as Dictionary).duplicate(true)
			)

	var snapshot_errors := _prepare_snapshots()
	if not snapshot_errors.is_empty():
		_show_failure(snapshot_errors)
		return
	if campaign_entries.is_empty():
		_show_failure(["Campaign does not contain any levels."])
		return

	var start_index := 0
	var requested_id := _requested_campaign_level_id()
	if not requested_id.is_empty():
		var requested_index := _entry_index_by_id(requested_id)
		if requested_index >= 0:
			start_index = requested_index

	if not _spawn_runtime(
		start_index,
		transition_generation,
		true
	):
		return
	_remember_campaign_level_id(get_current_level_id())


func _exit_tree() -> void:
	transition_generation += 1
	_intro_generation += 1
	transitioning = false
	intro_active = false
	current_runtime = null


func _input(event: InputEvent) -> void:
	if (
		get_tree().paused
		or not event is InputEventKey
		or not event.pressed
		or event.echo
	):
		return

	var key_event := event as InputEventKey
	var key := (
		key_event.physical_keycode
		if key_event.physical_keycode != 0
		else key_event.keycode
	)
	if key == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		return_to_main_menu()
		return

	if not campaign_completed or key != KEY_R:
		return

	if restart_campaign():
		get_viewport().set_input_as_handled()


func open_level_by_id(level_id: String) -> bool:
	var target_index := _entry_index_by_id(level_id)
	if target_index < 0 or transitioning:
		return false

	if (
		target_index == current_level_index
		and is_instance_valid(current_runtime)
		and not campaign_completed
	):
		_remember_campaign_level_id(level_id)
		return true

	_replace_runtime(target_index, true)
	return true


func get_current_level_id() -> String:
	if (
		current_level_index < 0
		or current_level_index >= campaign_entries.size()
	):
		return ""
	return str(campaign_entries[current_level_index].get("id", ""))


func get_current_level_index() -> int:
	return current_level_index


func get_level_count() -> int:
	return campaign_entries.size()


func is_campaign_complete() -> bool:
	return campaign_completed


func restart_campaign() -> bool:
	if (
		not campaign_completed
		or transitioning
		or campaign_entries.is_empty()
	):
		return false

	_replace_runtime(0, true)
	return true


func return_to_main_menu() -> bool:
	if transitioning:
		return false
	if not ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		push_error(
			"Main menu scene does not exist: %s"
			% MAIN_MENU_SCENE_PATH
		)
		return false

	transitioning = true
	var previous_phase := phase
	phase = Phase.REPLACING
	var change_error := get_tree().change_scene_to_file(
		MAIN_MENU_SCENE_PATH
	)
	if change_error == OK:
		transition_generation += 1
		_intro_generation += 1
		return true

	transitioning = false
	phase = previous_phase
	push_error(
		"Could not open main menu '%s' (error %d)."
		% [MAIN_MENU_SCENE_PATH, change_error]
	)
	return false


func get_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in campaign_entries:
		entries.append(entry.duplicate(true))
	return entries


func _prepare_snapshots() -> Array[String]:
	var errors: Array[String] = []
	_snapshots_by_id.clear()

	for index in campaign_entries.size():
		var entry: Dictionary = campaign_entries[index]
		var level_id := str(entry.get("id", ""))
		var level_data: Variant = entry.get("data")
		if level_id.is_empty() or typeof(level_data) != TYPE_DICTIONARY:
			errors.append(
				"Campaign entry %d is missing its ID or level data."
				% index
			)
			continue
		if str((level_data as Dictionary).get("level_id", "")) != level_id:
			errors.append(
				(
					"Campaign entry '%s' does not match its level data ID."
					% level_id
				)
			)
			continue
		if _snapshots_by_id.has(level_id):
			errors.append(
				"Campaign runtime received duplicate level ID '%s'."
				% level_id
			)
			continue

		var encoded: Dictionary = LEVEL_DATA_CODEC.encode(level_data)
		if not bool(encoded.get("ok", false)):
			for error: Variant in encoded.get("errors", []):
				errors.append(
					"Campaign level '%s': %s" % [level_id, error]
				)
			continue
		_snapshots_by_id[level_id] = str(encoded["text"])

	return errors


func _spawn_runtime(
	index: int,
	generation: int,
	show_intro: bool
) -> bool:
	if (
		generation != transition_generation
		or index < 0
		or index >= campaign_entries.size()
		or runtime_host.get_child_count() != 0
	):
		return false

	var entry: Dictionary = campaign_entries[index]
	var level_id := str(entry.get("id", ""))
	var snapshot_json := str(_snapshots_by_id.get(level_id, ""))
	if snapshot_json.is_empty():
		_show_failure(
			["Campaign snapshot is unavailable for level '%s'." % level_id]
		)
		return false

	var runtime := (
		LEVEL_RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	)
	if not is_instance_valid(runtime):
		_show_failure(
			["Could not instantiate runtime for level '%s'." % level_id]
		)
		return false

	runtime.configure_campaign_snapshot(
		snapshot_json,
		index + 1 < campaign_entries.size(),
		str(campaign_data.get("advance_message", ""))
	)
	runtime.campaign_advance_requested.connect(
		_on_advance_requested.bind(runtime, generation)
	)
	runtime.campaign_completed_requested.connect(
		_on_completed_requested.bind(runtime, generation)
	)
	runtime.campaign_restart_requested.connect(
		_on_restart_requested.bind(runtime, generation)
	)

	current_level_index = index
	current_runtime = runtime
	runtime_host.add_child(runtime)
	if runtime.level_loaded:
		if _is_completion_final_index(index):
			runtime.clear_message = COMPLETION_CLEAR_MESSAGE
		failure_ui.visible = false
		_update_progress(index)
		if show_intro:
			_begin_intro(index, generation)
		else:
			phase = Phase.PLAYING
			_set_runtime_active(true)
		return true

	var runtime_errors: Array = runtime.load_errors
	current_runtime = null
	current_level_index = -1
	runtime.queue_free()
	_show_failure(runtime_errors)
	return false


func _replace_runtime(
	target_index: int,
	show_intro: bool
) -> void:
	if (
		transitioning
		or target_index < 0
		or target_index >= campaign_entries.size()
	):
		return

	transitioning = true
	phase = Phase.REPLACING
	_hide_completion()
	_cancel_intro()
	transition_generation += 1
	var generation := transition_generation
	var previous_runtime := current_runtime
	current_runtime = null
	current_level_index = -1

	if is_instance_valid(previous_runtime):
		previous_runtime.queue_free()
		await previous_runtime.tree_exited

	if generation != transition_generation or not is_inside_tree():
		return

	var spawned := _spawn_runtime(
		target_index,
		generation,
		show_intro
	)
	transitioning = false
	if spawned:
		_remember_campaign_level_id(get_current_level_id())


func _on_advance_requested(
	runtime: LevelRuntimeArena,
	generation: int
) -> void:
	if not _is_current_request(runtime, generation):
		return

	var next_index := current_level_index + 1
	if next_index >= campaign_entries.size():
		next_index = current_level_index
	_replace_runtime(next_index, true)


func _on_completed_requested(
	runtime: LevelRuntimeArena,
	generation: int
) -> void:
	if not _is_current_request(runtime, generation):
		return

	if (
		str(campaign_data.get("final_behavior", ""))
		== CAMPAIGN_DATA_VALIDATOR.FINAL_BEHAVIOR_SHOW_COMPLETION
	):
		_show_completion()
		return

	_replace_runtime(current_level_index, false)


func _on_restart_requested(
	_outcome: int,
	runtime: LevelRuntimeArena,
	generation: int
) -> void:
	if not _is_current_request(runtime, generation):
		return
	_replace_runtime(current_level_index, false)


func _begin_intro(index: int, generation: int) -> void:
	_intro_generation += 1
	var intro_generation := _intro_generation
	intro_active = true
	phase = Phase.INTRO
	intro_title.text = str(
		campaign_entries[index].get("title", "ARENA")
	).to_upper()
	intro_meta.text = "АРЕНА %d / %d" % [
		index + 1,
		campaign_entries.size(),
	]
	intro_ui.visible = true
	_set_runtime_active(false)

	if intro_duration <= 0.0:
		call_deferred(
			"_finish_intro",
			generation,
			intro_generation
		)
		return

	get_tree().create_timer(
		intro_duration,
		true
	).timeout.connect(
		_finish_intro.bind(generation, intro_generation)
	)


func _finish_intro(
	generation: int,
	intro_generation: int
) -> void:
	if (
		generation != transition_generation
		or intro_generation != _intro_generation
		or campaign_completed
		or not is_instance_valid(current_runtime)
	):
		return

	intro_active = false
	intro_ui.visible = false
	phase = Phase.PLAYING
	_set_runtime_active(true)


func _cancel_intro() -> void:
	_intro_generation += 1
	intro_active = false
	intro_ui.visible = false


func _update_progress(index: int) -> void:
	var progress_text := "КАМПАНИЯ  %d / %d" % [
		index + 1,
		campaign_entries.size(),
	]
	progress_label.text = progress_text
	progress_backing.visible = true
	progress_label.visible = true


func _show_completion() -> void:
	_cancel_intro()
	transitioning = true
	campaign_completed = true
	phase = Phase.REPLACING
	completion_count.text = "%d / %d" % [
		campaign_entries.size(),
		campaign_entries.size(),
	]
	completion_ui.visible = true
	_set_runtime_active(false)
	transition_generation += 1
	var generation := transition_generation
	var completed_runtime := current_runtime
	current_runtime = null

	if is_instance_valid(completed_runtime):
		completed_runtime.queue_free()
		await completed_runtime.tree_exited

	if generation != transition_generation or not is_inside_tree():
		return

	transitioning = false
	phase = Phase.COMPLETED


func _hide_completion() -> void:
	campaign_completed = false
	completion_ui.visible = false


func _set_runtime_active(active: bool) -> void:
	if not is_instance_valid(current_runtime):
		return
	current_runtime.process_mode = (
		Node.PROCESS_MODE_INHERIT
		if active
		else Node.PROCESS_MODE_DISABLED
	)


func _is_completion_final_index(index: int) -> bool:
	return (
		index == campaign_entries.size() - 1
		and str(campaign_data.get("final_behavior", ""))
		== CAMPAIGN_DATA_VALIDATOR.FINAL_BEHAVIOR_SHOW_COMPLETION
	)


func _is_current_request(
	runtime: LevelRuntimeArena,
	generation: int
) -> bool:
	return (
		not transitioning
		and generation == transition_generation
		and runtime == current_runtime
		and is_instance_valid(runtime)
	)


func _entry_index_by_id(level_id: String) -> int:
	for index in campaign_entries.size():
		if str(campaign_entries[index].get("id", "")) == level_id:
			return index
	return -1


func _requested_campaign_level_id() -> String:
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("get_requested_campaign_level_id")
	):
		return str(
			selector.call("get_requested_campaign_level_id")
		)
	return ""


func _remember_campaign_level_id(level_id: String) -> void:
	if level_id.is_empty():
		return

	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method(
			"remember_requested_campaign_level_id"
		)
	):
		selector.call(
			"remember_requested_campaign_level_id",
			level_id
		)


func _set_debug_selector_suppressed(suppressed: bool) -> void:
	var selector := get_node_or_null("/root/DebugLevelSelector")
	if (
		is_instance_valid(selector)
		and selector.has_method("set_context_suppressed")
	):
		selector.call("set_context_suppressed", suppressed)


func _show_failure(errors: Array) -> void:
	_cancel_intro()
	_hide_completion()
	phase = Phase.FAILED
	progress_backing.visible = false
	progress_label.visible = false
	_set_runtime_active(false)
	load_errors.clear()
	for error: Variant in errors:
		load_errors.append(str(error))
	if load_errors.is_empty():
		load_errors.append("Unknown campaign runtime error.")

	failure_label.text = "\n".join(load_errors)
	failure_ui.visible = true
	for error: String in load_errors:
		push_error(error)

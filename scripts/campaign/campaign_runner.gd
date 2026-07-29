class_name CampaignRunner
extends Node2D

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_RUNTIME_SCENE := preload(
	"res://scenes/data_arena_01.tscn"
)
const FINAL_BEHAVIOR_RESTART_FINAL_LEVEL := "restart_final_level"

@onready var runtime_host: Node2D = $RuntimeHost
@onready var failure_ui: CanvasLayer = $FailureUI
@onready var failure_label: Label = $FailureUI/Panel/Message

var campaign_data: Dictionary = {}
var campaign_entries: Array[Dictionary] = []
var load_errors: Array[String] = []
var current_runtime: LevelRuntimeArena
var current_level_index := -1
var transition_generation := 0
var transitioning := false

var _snapshots_by_id: Dictionary = {}


func _ready() -> void:
	var campaign_result: Dictionary = (
		CAMPAIGN_STORAGE.load_builtin_campaign()
	)
	if not bool(campaign_result.get("ok", false)):
		_show_failure(campaign_result.get("errors", []))
		return

	campaign_data = (
		campaign_result.get("data", {}) as Dictionary
	).duplicate(true)
	if (
		str(campaign_data.get("final_behavior", ""))
		!= FINAL_BEHAVIOR_RESTART_FINAL_LEVEL
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

	if not _spawn_runtime(start_index, transition_generation):
		return
	_remember_campaign_level_id(get_current_level_id())


func _exit_tree() -> void:
	transition_generation += 1
	transitioning = false
	current_runtime = null


func open_level_by_id(level_id: String) -> bool:
	var target_index := _entry_index_by_id(level_id)
	if target_index < 0 or transitioning:
		return false

	if (
		target_index == current_level_index
		and is_instance_valid(current_runtime)
	):
		_remember_campaign_level_id(level_id)
		return true

	_replace_runtime(target_index)
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


func _spawn_runtime(index: int, generation: int) -> bool:
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
	runtime.campaign_restart_requested.connect(
		_on_restart_requested.bind(runtime, generation)
	)

	current_level_index = index
	current_runtime = runtime
	runtime_host.add_child(runtime)
	if runtime.level_loaded:
		failure_ui.visible = false
		return true

	var runtime_errors: Array = runtime.load_errors
	current_runtime = null
	current_level_index = -1
	runtime.queue_free()
	_show_failure(runtime_errors)
	return false


func _replace_runtime(target_index: int) -> void:
	if (
		transitioning
		or target_index < 0
		or target_index >= campaign_entries.size()
	):
		return

	transitioning = true
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

	var spawned := _spawn_runtime(target_index, generation)
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
	_replace_runtime(next_index)


func _on_restart_requested(
	_outcome: int,
	runtime: LevelRuntimeArena,
	generation: int
) -> void:
	if not _is_current_request(runtime, generation):
		return
	_replace_runtime(current_level_index)


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


func _show_failure(errors: Array) -> void:
	load_errors.clear()
	for error: Variant in errors:
		load_errors.append(str(error))
	if load_errors.is_empty():
		load_errors.append("Unknown campaign runtime error.")

	failure_label.text = "\n".join(load_errors)
	failure_ui.visible = true
	for error: String in load_errors:
		push_error(error)

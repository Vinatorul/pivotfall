extends SceneTree

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const MAIN_MENU_SCENE := preload(
	"res://scenes/main_menu.tscn"
)
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const CAMPAIGN_PATH := "res://scenes/campaign_runner.tscn"

var failures: Array[String] = []
var progress_store: CampaignProgressStore
var progress_path_configured := false
var campaign_entries: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	_cleanup_progress()


func _run() -> void:
	if not _setup():
		_finish()
		return

	_test_missing_and_round_trip()
	_test_validation_and_recovery()
	await _test_menu_and_runner_integration()
	_finish()


func _setup() -> bool:
	progress_store = root.get_node_or_null(
		"CampaignProgress"
	) as CampaignProgressStore
	_expect(
		is_instance_valid(progress_store),
		"Campaign progress autoload is unavailable."
	)
	if not is_instance_valid(progress_store):
		return false

	var test_path := (
		"user://campaign_progress_test_progress_%d_%d.json"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_expect(
		not progress_store.configure_storage_path_for_tests(
			CampaignProgressStore.DEFAULT_STORAGE_PATH
		),
		"Campaign progress accepted the real save path as a test path."
	)
	_expect(
		not progress_store.configure_storage_path_for_tests(
			"user://campaign_progress_unsafe_test.json"
		),
		"Campaign progress accepted a path outside the test namespace."
	)
	progress_path_configured = (
		progress_store.configure_storage_path_for_tests(test_path)
	)
	_expect(
		progress_path_configured,
		"Campaign progress test path was rejected."
	)
	if not progress_path_configured:
		return false
	progress_store.clear_progress()

	var campaign_result := CAMPAIGN_STORAGE.load_builtin_campaign()
	_expect(
		bool(campaign_result["ok"]),
		"Built-in campaign is unavailable to progress smoke."
	)
	if not bool(campaign_result["ok"]):
		return false
	for raw_entry: Variant in campaign_result["entries"]:
		if typeof(raw_entry) == TYPE_DICTIONARY:
			campaign_entries.append(
				(raw_entry as Dictionary).duplicate(true)
			)
	return not campaign_entries.is_empty()


func _test_missing_and_round_trip() -> void:
	var missing := progress_store.load_progress(campaign_entries)
	_expect(
		bool(missing["ok"]) and not bool(missing["exists"]),
		"Missing progress was not treated as a clean first launch."
	)

	var started := progress_store.begin_new_game(campaign_entries)
	var request := progress_store.consume_launch_request()
	var loaded := progress_store.load_progress(campaign_entries)
	_expect(
		bool(started["ok"])
		and bool(loaded["ok"])
		and bool(loaded["exists"])
		and loaded["data"] == _progress_data(
			"arena_01_data",
			"arena_01_data"
		)
		and request["level_id"] == "arena_01_data"
		and bool(request["track_progress"]),
		"New Game did not create canonical Arena 01 progress."
	)
	var consumed_again := progress_store.consume_launch_request()
	_expect(
		str(consumed_again["level_id"]).is_empty()
		and not bool(consumed_again["track_progress"]),
		"Campaign launch request was not one-shot."
	)

	var advanced := progress_store.record_level_started(
		campaign_entries,
		"arena_02_data"
	)
	var replayed := progress_store.record_level_started(
		campaign_entries,
		"arena_01_data"
	)
	var skipped := progress_store.record_level_started(
		campaign_entries,
		"arena_04_data"
	)
	var resumed_path := progress_store.record_level_started(
		campaign_entries,
		"arena_03_data"
	)
	loaded = progress_store.load_progress(campaign_entries)
	_expect(
		bool(advanced["ok"])
		and bool(replayed["ok"])
		and not bool(skipped["ok"])
		and bool(resumed_path["ok"])
		and loaded["data"]["current_level_id"] == "arena_03_data"
		and loaded["data"]["highest_unlocked_level_id"]
		== "arena_03_data",
		"Progress checkpoints did not preserve unlock ordering."
	)

	var continued := progress_store.prepare_continue(campaign_entries)
	request = progress_store.consume_launch_request()
	_expect(
		bool(continued["ok"])
		and request["level_id"] == "arena_03_data"
		and bool(request["track_progress"]),
		"Continue did not prepare the saved current arena."
	)


func _test_validation_and_recovery() -> void:
	progress_store.clear_progress()
	_write_text(_progress_path(), "{")
	var malformed := progress_store.load_progress(campaign_entries)
	_expect(
		not bool(malformed["ok"]) and bool(malformed["exists"]),
		"Malformed progress did not fail as an existing save."
	)

	var replaced := progress_store.begin_new_game(campaign_entries)
	progress_store.consume_launch_request()
	_expect(
		bool(replaced["ok"]),
		"New Game could not replace malformed progress."
	)

	_write_json(
		_progress_path(),
		{
			"schema_version": 2,
			"campaign_id": "main",
			"current_level_id": "arena_01_data",
			"highest_unlocked_level_id": "arena_01_data",
			"completed": false,
		}
	)
	var unknown_schema := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		not bool(unknown_schema["ok"])
		and bool(unknown_schema["exists"]),
		"Unknown progress schema was accepted."
	)

	progress_store.clear_progress()
	_write_json(
		_progress_path(),
		_progress_data(
			"arena_08_data",
			"arena_08_data",
			true
		)
	)
	var migrated_legacy := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		bool(migrated_legacy["ok"])
		and migrated_legacy["data"]
		== _progress_data("jailbreak", "jailbreak")
		and not migrated_legacy["warnings"].is_empty(),
		"Completed Arena 08 progress did not unlock Arena 09."
	)
	var persisted_migration := progress_store.record_level_started(
		campaign_entries,
		"jailbreak"
	)
	var reloaded_migration := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		bool(persisted_migration["ok"])
		and bool(reloaded_migration["ok"])
		and reloaded_migration["data"]
		== _progress_data("jailbreak", "jailbreak")
		and reloaded_migration["warnings"].is_empty(),
		"Starting Arena 09 did not persist the migrated progress."
	)

	progress_store.clear_progress()
	_write_json(
		"%s.bak" % _progress_path(),
		_progress_data("arena_01_data", "arena_01_data")
	)
	_write_json(
		"%s.tmp" % _progress_path(),
		_progress_data("arena_02_data", "arena_02_data")
	)
	var recovered_newer := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		bool(recovered_newer["ok"])
		and recovered_newer["data"]["current_level_id"]
		== "arena_02_data"
		and not recovered_newer["warnings"].is_empty(),
		"Recovery did not prefer the verified temporary save."
	)

	progress_store.clear_progress()
	_write_text(_progress_path(), "{")
	_write_json(
		"%s.bak" % _progress_path(),
		_progress_data("arena_03_data", "arena_03_data")
	)
	var recovered_corrupt := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		bool(recovered_corrupt["ok"])
		and recovered_corrupt["data"]["current_level_id"]
		== "arena_03_data"
		and FileAccess.file_exists(
			"%s.corrupt" % _progress_path()
		),
		"Valid backup did not recover a corrupt target safely."
	)

	progress_store.clear_progress()
	var corrupt_path := "%s.corrupt" % _progress_path()
	_write_text(corrupt_path, "older quarantine")
	_write_text(_progress_path(), "{")
	_write_json(
		"%s.bak" % _progress_path(),
		_progress_data("arena_04_data", "arena_04_data")
	)
	var recovered_with_quarantine := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		bool(recovered_with_quarantine["ok"])
		and recovered_with_quarantine["data"]["current_level_id"]
		== "arena_04_data"
		and FileAccess.get_file_as_string(corrupt_path)
		== "older quarantine"
		and FileAccess.file_exists("%s.1" % corrupt_path),
		"Recovery overwrote an existing quarantine."
	)

	progress_store.clear_progress()
	_write_text(corrupt_path, "orphaned quarantine")
	var lone_quarantine := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		not bool(lone_quarantine["ok"])
		and bool(lone_quarantine["exists"]),
		"A lone quarantine was mistaken for missing progress."
	)

	progress_store.clear_progress()
	progress_store.begin_new_game(campaign_entries)
	progress_store.consume_launch_request()
	_write_json(
		"%s.tmp" % _progress_path(),
		_progress_data("arena_02_data", "arena_02_data")
	)
	_write_json(
		"%s.bak" % _progress_path(),
		_progress_data("arena_03_data", "arena_03_data")
	)
	var kept_target := progress_store.load_progress(campaign_entries)
	_expect(
		bool(kept_target["ok"])
		and kept_target["data"]["current_level_id"]
		== "arena_01_data"
		and not FileAccess.file_exists(
			"%s.tmp" % _progress_path()
		)
		and not FileAccess.file_exists(
			"%s.bak" % _progress_path()
		),
		"Valid target did not win over stale recovery files."
	)


func _test_menu_and_runner_integration() -> void:
	progress_store.reset_progress(campaign_entries)
	progress_store.record_level_started(
		campaign_entries,
		"arena_02_data"
	)
	progress_store.record_level_started(
		campaign_entries,
		"arena_03_data"
	)

	var menu := await _replace_with_menu()
	_expect(
		not menu.continue_button.disabled
		and "АРЕНА 03" in menu.continue_button.text
		and root.get_viewport().gui_get_focus_owner()
		== menu.continue_button,
		"Valid progress did not enable and focus Continue."
	)

	menu.continue_button.pressed.emit()
	var runner := await _wait_for_scene(CAMPAIGN_PATH) as CampaignRunner
	_expect(
		is_instance_valid(runner)
		and runner.get_current_level_id() == "arena_03_data"
		and runner.is_tracking_progress(),
		"Continue did not launch tracked Arena 03."
	)
	if not is_instance_valid(runner):
		return

	var arena_03_runtime_id := runner.current_runtime.get_instance_id()
	runner.current_runtime.campaign_advance_requested.emit()
	await _wait_for_runtime_id_change(runner, arena_03_runtime_id)
	var after_advance := progress_store.load_progress(campaign_entries)
	_expect(
		runner.get_current_level_id() == "arena_04_data"
		and bool(after_advance["ok"])
		and after_advance["data"]["current_level_id"]
		== "arena_04_data"
		and after_advance["data"]["highest_unlocked_level_id"]
		== "arena_04_data",
		"Natural Arena 03 to 04 transition was not checkpointed."
	)

	var debug_opened := runner.open_level_by_id("tower_assault")
	await _wait_for_level(runner, "tower_assault")
	_expect(
		debug_opened and not runner.is_tracking_progress(),
		"Accepted debug jump did not detach progress tracking."
	)
	runner.current_runtime.campaign_completed_requested.emit()
	await _wait_for_completion(runner)
	var after_debug_completion := progress_store.load_progress(
		campaign_entries
	)
	_expect(
		after_debug_completion["data"]["current_level_id"]
		== "arena_04_data"
		and not bool(after_debug_completion["data"]["completed"]),
		"Debug completion modified tracked campaign progress."
	)

	runner.return_to_main_menu()
	menu = await _wait_for_scene(MAIN_MENU_PATH) as MainMenu
	var bytes_before_cancel := FileAccess.get_file_as_bytes(
		_progress_path()
	)
	menu.new_game_button.pressed.emit()
	_expect(
		menu.new_game_confirm.visible
		and menu.confirming_new_game
		and root.get_viewport().gui_get_focus_owner()
		== menu.cancel_button,
		"New Game did not open a safely focused reset confirmation."
	)
	await _press_physical_key(KEY_ESCAPE)
	_expect(
		not menu.new_game_confirm.visible
		and FileAccess.get_file_as_bytes(_progress_path())
		== bytes_before_cancel,
		"Cancelling New Game changed campaign progress."
	)

	menu.new_game_button.pressed.emit()
	menu.confirm_button.pressed.emit()
	runner = await _wait_for_scene(CAMPAIGN_PATH) as CampaignRunner
	var reset_loaded := progress_store.load_progress(campaign_entries)
	_expect(
		is_instance_valid(runner)
		and runner.get_current_level_id() == "arena_01_data"
		and runner.is_tracking_progress()
		and reset_loaded["data"] == _progress_data(
			"arena_01_data",
			"arena_01_data"
		),
		"Confirmed New Game did not reset progress to Arena 01."
	)

	if is_instance_valid(runner):
		for index in range(1, campaign_entries.size()):
			runner.current_runtime.campaign_advance_requested.emit()
			await _wait_for_level(
				runner,
				str(campaign_entries[index]["id"])
			)
		runner.current_runtime.campaign_completed_requested.emit()
		await _wait_for_completion(runner)
		var honest_completion := progress_store.load_progress(
			campaign_entries
		)
		_expect(
			bool(honest_completion["ok"])
			and bool(honest_completion["data"]["completed"])
			and honest_completion["data"]["current_level_id"]
			== "tower_assault",
			"Tracked campaign completion was not persisted."
		)

		var restarted_campaign := runner.restart_campaign()
		await _wait_for_level(runner, "arena_01_data")
		var restarted_progress := progress_store.load_progress(
			campaign_entries
		)
		_expect(
			restarted_campaign
			and restarted_progress["data"] == _progress_data(
				"arena_01_data",
				"arena_01_data"
			),
			"Restarting a completed campaign did not reset progress."
		)

		runner.return_to_main_menu()
		await _wait_for_scene(MAIN_MENU_PATH)
	for index in range(1, campaign_entries.size()):
		progress_store.record_level_started(
			campaign_entries,
			str(campaign_entries[index]["id"])
		)
	var completed := progress_store.mark_completed(campaign_entries)
	menu = await _replace_with_menu()
	_expect(
		bool(completed["ok"])
		and menu.continue_button.disabled
		and menu.continue_button.text == "КАМПАНИЯ ПРОЙДЕНА"
		and "11 ИЗ 11" in menu.status_label.text
		and root.get_viewport().gui_get_focus_owner()
		== menu.new_game_button,
		"Completed progress did not produce the completed menu state."
	)

	progress_store.clear_progress()
	_write_text(_progress_path(), "{")
	menu = await _replace_with_menu()
	var corrupt_bytes := FileAccess.get_file_as_bytes(
		_progress_path()
	)
	_expect(
		menu.continue_button.disabled
		and menu.status_label.visible
		and "повреждено" in menu.status_label.text.to_lower()
		and root.get_viewport().gui_get_focus_owner()
		== menu.new_game_button,
		"Corrupt progress did not disable Continue with a warning."
	)
	menu.new_game_button.pressed.emit()
	_expect(
		menu.new_game_confirm.visible
		and "ПОВРЕЖДЁННОЕ" in menu.confirm_message.text
		and root.get_viewport().gui_get_focus_owner()
		== menu.cancel_button,
		"Corrupt progress did not request explicit replacement."
	)
	await _press_physical_key(KEY_ESCAPE)
	_expect(
		FileAccess.get_file_as_bytes(_progress_path())
		== corrupt_bytes,
		"Cancelling corrupt-save replacement changed its bytes."
	)
	menu.new_game_button.pressed.emit()
	menu.confirm_button.pressed.emit()
	runner = await _wait_for_scene(CAMPAIGN_PATH) as CampaignRunner
	var repaired := progress_store.load_progress(campaign_entries)
	_expect(
		is_instance_valid(runner)
		and bool(repaired["ok"])
		and repaired["data"] == _progress_data(
			"arena_01_data",
			"arena_01_data"
		),
		"Confirmed New Game did not replace corrupt progress."
	)


func _progress_data(
	current_level_id: String,
	highest_level_id: String,
	completed: bool = false
) -> Dictionary:
	return {
		"schema_version": CampaignProgressStore.SCHEMA_VERSION,
		"campaign_id": CAMPAIGN_STORAGE.BUILTIN_CAMPAIGN_ID,
		"current_level_id": current_level_id,
		"highest_unlocked_level_id": highest_level_id,
		"completed": completed,
	}


func _replace_with_menu() -> MainMenu:
	var previous := current_scene
	current_scene = null
	if is_instance_valid(previous):
		previous.queue_free()
		await previous.tree_exited
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	return menu


func _wait_for_scene(scene_path: String) -> Node:
	for _frame in 240:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(current_scene)
			and current_scene.scene_file_path == scene_path
		):
			return current_scene
	return null


func _wait_for_runtime_id_change(
	runner: CampaignRunner,
	old_runtime_id: int
) -> void:
	for _frame in 240:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(runner.current_runtime)
			and runner.current_runtime.get_instance_id()
			!= old_runtime_id
			and not runner.transitioning
		):
			return


func _wait_for_level(
	runner: CampaignRunner,
	level_id: String
) -> void:
	for _frame in 240:
		await process_frame
		await physics_frame
		if (
			runner.get_current_level_id() == level_id
			and is_instance_valid(runner.current_runtime)
			and not runner.transitioning
		):
			return


func _wait_for_completion(runner: CampaignRunner) -> void:
	for _frame in 240:
		await process_frame
		await physics_frame
		if runner.is_campaign_complete() and not runner.transitioning:
			return


func _press_physical_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	await physics_frame

	var release := InputEventKey.new()
	release.physical_keycode = key
	release.keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _write_json(path: String, data: Dictionary) -> void:
	_write_text(path, JSON.stringify(data, "\t", true, false) + "\n")


func _progress_path() -> String:
	return progress_store.get_storage_path()


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_expect(
		is_instance_valid(file),
		"Could not create campaign progress fixture."
	)
	if not is_instance_valid(file):
		return
	file.store_string(text)
	file.flush()
	file.close()


func _cleanup_progress() -> void:
	if not progress_path_configured or not is_instance_valid(progress_store):
		return
	progress_store.clear_progress()
	progress_store.restore_default_storage_path()
	progress_path_configured = false


func _finish() -> void:
	paused = false
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited
	_cleanup_progress()

	if failures.is_empty():
		print("CAMPAIGN_PROGRESS_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

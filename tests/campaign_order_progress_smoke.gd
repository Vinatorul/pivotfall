extends SceneTree

const STORAGE := preload("res://scripts/campaign/campaign_storage.gd")
const OLD_IDS := [
	"arena_01_data", "arena_02_data", "arena_03_data", "arena_04_data",
	"arena_05_data", "arena_06_data", "arena_07_data", "arena_08_data",
	"jailbreak", "sniper_party", "tower_assault", "arena_12_data",
	"arena_13_data", "arena_14_data", "arena_15_data", "arena_16_data",
]

var failures: Array[String] = []
var store: CampaignProgressStore
var entries: Array[Dictionary] = []
var ids: Array[String] = []
var save_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _setup():
		_finish()
		return
	_test_legacy_prefixes()
	_test_reordered_current()
	_test_continue_and_new_save()
	_test_completed_campaign()
	await _test_completed_ui()
	_test_expansion_after_reorder()
	_test_new_game()
	_finish()


func _setup() -> bool:
	store = root.get_node_or_null("CampaignProgress") as CampaignProgressStore
	if not is_instance_valid(store):
		_expect(false, "Progress autoload is missing.")
		return false
	save_path = "user://campaign_progress_test_order_%d.json" % OS.get_process_id()
	if not store.configure_storage_path_for_tests(save_path):
		_expect(false, "Isolated progress path was rejected.")
		return false
	var loaded := STORAGE.load_builtin_campaign()
	if not bool(loaded["ok"]):
		_expect(false, "Campaign failed to load.")
		return false
	entries.assign(loaded["entries"])
	for entry: Dictionary in entries:
		ids.append(str(entry["id"]))
	return true


func _test_legacy_prefixes() -> void:
	for old_highest in OLD_IDS.size():
		_write(_data(OLD_IDS[old_highest], OLD_IDS[old_highest], false, 1))
		var before := FileAccess.get_file_as_string(save_path)
		var loaded := store.load_progress(entries)
		_expect(bool(loaded["ok"]), "Legacy prefix %d failed to load." % old_highest)
		if not bool(loaded["ok"]):
			continue
		var highest := ids.find(loaded["data"]["highest_unlocked_level_id"])
		var expected_highest := 0
		for old_index in range(old_highest + 1):
			expected_highest = maxi(expected_highest, ids.find(OLD_IDS[old_index]))
			var replay := store.prepare_replay(entries, OLD_IDS[old_index])
			_expect(bool(replay["ok"]), "Previously open arena became locked.")
			var request := store.consume_launch_request()
			_expect(bool(request["replay"]) and not bool(request["track_progress"]),
				"Legacy replay enabled persistent progress tracking.")
		_expect(highest == expected_highest, "Migration opened the wrong prefix.")
		if highest + 1 < ids.size():
			_expect(not bool(store.prepare_replay(entries, ids[highest + 1])["ok"]),
				"Migration opened an arena beyond the required prefix.")
		_expect(FileAccess.get_file_as_string(save_path) == before,
			"Loading or replaying legacy progress rewrote the save.")


func _test_reordered_current() -> void:
	for fixture: Array in [
		["arena_03_data", "arena_04_data", "arena_03_data"],
		["arena_02_data", "arena_03_data", "arena_03_data"],
		["arena_06_data", "arena_07_data", "arena_06_data"],
		["arena_04_data", "arena_08_data", "arena_08_data"],
	]:
		_write(_data(fixture[0], fixture[1], false, 1))
		var loaded := store.load_progress(entries)
		_expect(bool(loaded["ok"]) and loaded["data"] == _data(fixture[0], fixture[2]),
			"Migration lost the current ID or unlocked boundary: %s." % [fixture])


func _test_continue_and_new_save() -> void:
	_write(_data("arena_03_data", "arena_04_data", false, 1))
	var continued := store.prepare_continue(entries)
	var request := store.consume_launch_request()
	_expect(bool(continued["ok"]) and request["level_id"] == "arena_03_data"
		and bool(request["track_progress"]), "Continue lost the legacy current arena.")
	var saved := store.record_level_started(entries, request["level_id"])
	_expect(bool(saved["ok"]), "Continuing could not save migrated progress.")
	var persisted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	_expect(persisted["schema_version"] == 2,
		"Tracked progress did not persist the new save version.")
	var before := FileAccess.get_file_as_string(save_path)
	for attempt in 2:
		var loaded := store.load_progress(entries)
		_expect(bool(loaded["ok"]) and loaded["data"] == continued["data"]
			and loaded["warnings"].is_empty(), "New save was migrated again.")
	_expect(FileAccess.get_file_as_string(save_path) == before, "Reload rewrote progress.")
	var advanced := store.record_level_started(entries, "arena_05_data")
	_expect(bool(advanced["ok"])
		and advanced["data"] == _data("arena_05_data", "arena_05_data"),
		"Migrated campaign did not advance in the new order.")


func _test_completed_campaign() -> void:
	_write(_data("arena_16_data", "arena_16_data", true, 1))
	var loaded := store.load_progress(entries)
	var expected := _data("arena_16_data", "tower_assault", true)
	_expect(bool(loaded["ok"]) and loaded["data"] == expected,
		"Completed legacy campaign lost completion or its current arena ID.")
	_expect(not bool(store.prepare_continue(entries)["ok"]),
		"Completed legacy campaign unexpectedly offered Continue.")
	_expect(bool(store.prepare_replay(entries, "tower_assault")["ok"]),
		"Completed legacy campaign did not unlock the new final arena.")
	store.consume_launch_request()
	_write(expected)
	for attempt in 2:
		var reloaded := store.load_progress(entries)
		_expect(bool(reloaded["ok"]) and reloaded["data"] == expected
			and reloaded["warnings"].is_empty(), "Completed new save was migrated again.")


func _test_completed_ui() -> void:
	_write(_data("arena_16_data", "arena_16_data", true, 1))
	var before := FileAccess.get_file_as_string(save_path)
	var menu := load("res://scenes/main_menu.tscn").instantiate() as MainMenu
	root.add_child(menu)
	await process_frame
	_expect(menu.progress_completed and menu.continue_button.disabled
		and menu.continue_button.text == "КАМПАНИЯ ПРОЙДЕНА"
		and not menu.arena_select_button.disabled,
		"Completed legacy campaign did not retain its completed main-menu state.")
	menu.queue_free()
	await menu.tree_exited
	var selector := load("res://scenes/arena_select.tscn").instantiate() as ArenaSelect
	root.add_child(selector)
	await process_frame
	_expect(selector.progress_completed and selector.arena_buttons.size() == 16
		and selector.current_level_index == 9 and selector.highest_unlocked_index == 15
		and selector.campaign_entries[selector.current_level_index]["id"] == "arena_16_data",
		"Completed legacy selector lost the current arena or unlocked boundary.")
	for button: Button in selector.arena_buttons:
		_expect(not button.disabled and button.get_meta("state") == "ПРОЙДЕНА",
			"Completed legacy selector left an arena locked or unfinished.")
	_expect(FileAccess.get_file_as_string(save_path) == before,
		"Opening menus changed completed legacy progress.")
	selector.queue_free()
	await selector.tree_exited


func _test_expansion_after_reorder() -> void:
	var expanded := entries.duplicate(true)
	expanded.append({"id": "future_arena"})
	for version in [1, 2]:
		var highest := "arena_16_data" if version == 1 else "tower_assault"
		_write(_data("arena_16_data", highest, true, version))
		var loaded := store.load_progress(expanded)
		_expect(bool(loaded["ok"])
			and loaded["data"] == _data("future_arena", "future_arena"),
			"Completed schema %d save did not unlock an appended arena." % version)
		var saved := store.record_level_started(expanded, "future_arena")
		var reloaded := store.load_progress(expanded)
		_expect(bool(saved["ok"]) and bool(reloaded["ok"])
			and reloaded["data"] == loaded["data"] and reloaded["warnings"].is_empty(),
			"Expansion did not persist its one-time unlock.")


func _test_new_game() -> void:
	var started := store.begin_new_game(entries)
	var request := store.consume_launch_request()
	_expect(bool(started["ok"])
		and started["data"] == _data("arena_01_data", "arena_01_data")
		and request["level_id"] == "arena_01_data", "New Game did not reset the campaign.")
	_expect(not bool(store.prepare_replay(entries, "arena_02_data")["ok"]),
		"New Game retained legacy unlocks.")


func _data(current: String, highest: String, completed: bool = false,
	version: int = 2) -> Dictionary:
	return {
		"schema_version": version,
		"campaign_id": "main",
		"current_level_id": current,
		"highest_unlocked_level_id": highest,
		"completed": completed,
	}


func _write(data: Dictionary) -> void:
	store.clear_progress()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_expect(false, "Could not write isolated progress fixture.")
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()


func _finish() -> void:
	if is_instance_valid(store) and not save_path.is_empty():
		store.clear_progress()
		store.restore_default_storage_path()
	if failures.is_empty():
		print("CAMPAIGN_ORDER_PROGRESS_SMOKE_OK")
	else:
		for failure: String in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

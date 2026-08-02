extends SceneTree

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const CAMPAIGN_DATA_CODEC := preload(
	"res://scripts/campaign/campaign_data_codec.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const RUNNER_SCENE := preload(
	"res://scenes/campaign_runner.tscn"
)

const EXPECTED_LEVEL_IDS: Array[String] = [
	"arena_01_data",
	"arena_02_data",
	"arena_03_data",
	"arena_04_data",
	"arena_05_data",
	"arena_06_data",
	"arena_07_data",
	"arena_08_data",
	"jailbreak",
	"sniper_party",
	"tower_assault",
]

var failures: Array[String] = []
var progress_store: CampaignProgressStore
var progress_path_configured := false


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	_cleanup_campaign_progress()


func _run() -> void:
	if not _setup_campaign_progress():
		failures.append("Could not isolate campaign progress.")

	var campaign_result := _test_manifest()
	if (
		progress_path_configured
		and bool(campaign_result.get("ok", false))
	):
		await _test_runner_lifecycle(campaign_result)

	await _cleanup_current_scene()
	_cleanup_campaign_progress()
	if failures.is_empty():
		print("CAMPAIGN_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_manifest() -> Dictionary:
	var result: Dictionary = CAMPAIGN_STORAGE.load_builtin_campaign()
	_expect(
		bool(result.get("ok", false)),
		"Built-in campaign did not pass its atomic preflight."
	)
	if not bool(result.get("ok", false)):
		return result

	var data: Dictionary = result["data"]
	var entries: Array = result["entries"]
	var actual_ids: Array[String] = []
	for entry: Dictionary in entries:
		actual_ids.append(str(entry.get("id", "")))

	_expect(
		actual_ids == EXPECTED_LEVEL_IDS,
		"Campaign order drifted from the expected built-in sequence."
	)
	_expect(
		entries.size() == EXPECTED_LEVEL_IDS.size(),
		"Campaign did not resolve exactly eleven entries."
	)
	_expect(
		str(data.get("advance_message", "")).length() > 0,
		"Campaign advance message is empty."
	)
	_expect(
		data.get("final_behavior") == "show_completion",
		"Campaign final behavior drifted."
	)

	for index in mini(entries.size(), EXPECTED_LEVEL_IDS.size()):
		var entry: Dictionary = entries[index]
		var level_data: Dictionary = entry.get("data", {})
		_expect(
			entry.get("id") == EXPECTED_LEVEL_IDS[index]
			and level_data.get("level_id") == EXPECTED_LEVEL_IDS[index]
			and str(entry.get("path", "")).ends_with(".json")
			and not str(entry.get("title", "")).is_empty(),
			"Resolved campaign entry %d is incomplete or mismatched."
			% index
		)

	_test_manifest_round_trip(data)
	_test_manifest_catalog(entries)
	_test_manifest_atomic_failures(data)
	_test_final_behavior_compatibility(data)
	return result


func _test_manifest_round_trip(data: Dictionary) -> void:
	var encoded: Dictionary = CAMPAIGN_DATA_CODEC.encode(data)
	_expect(
		bool(encoded.get("ok", false)),
		"Validated campaign could not be encoded."
	)
	if not bool(encoded.get("ok", false)):
		return

	var decoded: Dictionary = CAMPAIGN_DATA_CODEC.decode_text(
		str(encoded.get("text", ""))
	)
	_expect(
		bool(decoded.get("ok", false))
		and decoded.get("data", {}) == data,
		"Campaign encode/decode round-trip changed the manifest."
	)


func _test_manifest_catalog(entries: Array) -> void:
	var catalog_result: Dictionary = LEVEL_STORAGE.load_builtin_catalog()
	_expect(
		bool(catalog_result.get("ok", false)),
		"LevelStorage hid a valid built-in campaign."
	)
	var catalog: Array[Dictionary] = []
	for entry: Dictionary in catalog_result.get("entries", []):
		catalog.append(entry)
	_expect(
		catalog.size() == entries.size(),
		"LevelStorage catalog drifted from campaign.json."
	)
	for index in mini(catalog.size(), entries.size()):
		var catalog_entry: Dictionary = catalog[index]
		var campaign_entry: Dictionary = entries[index]
		_expect(
			catalog_entry.get("id") == campaign_entry.get("id")
			and catalog_entry.get("path") == campaign_entry.get("path")
			and catalog_entry.get("title") == campaign_entry.get("title"),
			"LevelStorage catalog entry %d drifted from campaign.json."
			% index
		)


func _test_manifest_atomic_failures(data: Dictionary) -> void:
	var invalid_user_path := data.duplicate(true)
	invalid_user_path["levels"][0]["path"] = (
		"user://levels/arena_01.json"
	)
	_expect_atomic_failure(
		CAMPAIGN_STORAGE.resolve_campaign(invalid_user_path),
		"Campaign accepted a user:// built-in level path."
	)

	var duplicate_id := data.duplicate(true)
	duplicate_id["levels"][1]["level_id"] = (
		duplicate_id["levels"][0]["level_id"]
	)
	_expect_atomic_failure(
		CAMPAIGN_STORAGE.resolve_campaign(duplicate_id),
		"Campaign accepted duplicate level IDs."
	)

	var mismatched_id := data.duplicate(true)
	mismatched_id["levels"][0]["level_id"] = "arena_99_data"
	_expect_atomic_failure(
		CAMPAIGN_STORAGE.resolve_campaign(mismatched_id),
		"Campaign accepted a manifest/file level ID mismatch."
	)

	var unknown_final_behavior := data.duplicate(true)
	unknown_final_behavior["final_behavior"] = "roll_credits"
	_expect_atomic_failure_contains(
		CAMPAIGN_STORAGE.resolve_campaign(unknown_final_behavior),
		"must be 'restart_final_level' or 'show_completion'",
		"Campaign accepted an unknown final behavior."
	)

	var non_string_final_behavior := data.duplicate(true)
	non_string_final_behavior["final_behavior"] = 8
	_expect_atomic_failure_contains(
		CAMPAIGN_STORAGE.resolve_campaign(non_string_final_behavior),
		"must be a string",
		"Campaign accepted a non-string final behavior."
	)

	var empty_final_behavior := data.duplicate(true)
	empty_final_behavior["final_behavior"] = ""
	_expect_atomic_failure_contains(
		CAMPAIGN_STORAGE.resolve_campaign(empty_final_behavior),
		"must be 'restart_final_level' or 'show_completion'",
		"Campaign accepted an empty final behavior."
	)

	var missing_final_behavior := data.duplicate(true)
	missing_final_behavior.erase("final_behavior")
	_expect_atomic_failure_contains(
		CAMPAIGN_STORAGE.resolve_campaign(missing_final_behavior),
		"missing required key 'final_behavior'",
		"Campaign accepted a missing final behavior."
	)


func _test_final_behavior_compatibility(data: Dictionary) -> void:
	var restart_final := data.duplicate(true)
	restart_final["final_behavior"] = "restart_final_level"
	var resolved: Dictionary = CAMPAIGN_STORAGE.resolve_campaign(
		restart_final
	)
	_expect(
		bool(resolved.get("ok", false))
		and (resolved.get("entries", []) as Array).size()
		== EXPECTED_LEVEL_IDS.size(),
		"Schema v1 no longer accepts restart_final_level."
	)


func _expect_atomic_failure(result: Dictionary, message: String) -> void:
	_expect(
		not bool(result.get("ok", true))
		and (result.get("data", {}) as Dictionary).is_empty()
		and (result.get("entries", []) as Array).is_empty()
		and not (result.get("errors", []) as Array).is_empty(),
		message
	)


func _expect_atomic_failure_contains(
	result: Dictionary,
	error_fragment: String,
	message: String
) -> void:
	_expect_atomic_failure(result, message)
	var errors := PackedStringArray()
	for error: Variant in result.get("errors", []):
		errors.append(str(error))
	_expect(
		error_fragment in "\n".join(errors),
		"%s Diagnostic fragment is missing: %s"
		% [message, error_fragment]
	)


func _test_runner_lifecycle(campaign_result: Dictionary) -> void:
	var runner := RUNNER_SCENE.instantiate() as CampaignRunner
	_expect(is_instance_valid(runner), "Could not instantiate campaign runner.")
	if not is_instance_valid(runner):
		return

	runner.intro_duration = 0.05
	root.add_child(runner)
	current_scene = runner

	var advance_message := str(
		(campaign_result["data"] as Dictionary).get(
			"advance_message",
			""
		)
	)

	_expect(
		runner.load_errors.is_empty()
		and runner.get_level_count() == EXPECTED_LEVEL_IDS.size()
		and runner.get_entries().size() == EXPECTED_LEVEL_IDS.size(),
		"Runner did not expose the complete preflighted campaign."
	)
	if not _expect_runtime(
		runner,
		"arena_01_data",
		"Runner did not start on Arena 01."
	):
		return

	var controller_id := runner.get_instance_id()
	_expect_intro(
		runner,
		"ARENA 01 / ПАТРУЛЬ",
		"АРЕНА 1 / 11",
		"КАМПАНИЯ  1 / 11",
		"Initial Arena 01 intro is incomplete."
	)
	if not await _wait_for_intro_end(runner):
		_expect(false, "Initial Arena 01 intro did not finish.")
		return
	_expect(
		runner.current_runtime.clear_message == advance_message,
		"Non-final Arena 01 did not use campaign advance_message."
	)
	_expect_selector_id("arena_01_data")

	var arena_01_ref: WeakRef = weakref(runner.current_runtime)
	runner.current_runtime.clear_restart_delay = 0.01
	_clear_runtime_enemies(runner.current_runtime)
	_expect(
		runner.current_runtime.status_label.text == advance_message,
		"Arena 01 clear UI did not show campaign advance_message."
	)
	var advanced := await _wait_for_runtime(
		runner,
		"arena_02_data"
	)
	_expect(
		advanced
		and runner.get_instance_id() == controller_id
		and not arena_01_ref.get_ref(),
		"Runner did not replace Arena 01 with Arena 02 cleanly."
	)
	if not advanced:
		return
	_expect_runtime(
		runner,
		"arena_02_data",
		"Runner lost its single Arena 02 runtime."
	)
	_expect(
		runner.current_runtime.clear_message == advance_message,
		"Non-final Arena 02 did not use campaign advance_message."
	)
	_expect_intro(
		runner,
		"ARENA 02 / ОПОРА",
		"АРЕНА 2 / 11",
		"КАМПАНИЯ  2 / 11",
		"Arena 02 transition intro is incomplete."
	)
	if not await _wait_for_intro_end(runner):
		_expect(false, "Arena 02 transition intro did not finish.")
		return
	_expect_selector_id("arena_02_data")

	var arena_02_id := runner.current_runtime.get_instance_id()
	await _press_physical_key(KEY_R)
	var restarted := await _wait_for_runtime(
		runner,
		"arena_02_data",
		arena_02_id
	)
	_expect(
		restarted
		and runner.get_instance_id() == controller_id,
		"Physical R did not replace only the current Arena 02 runtime."
	)
	if not restarted:
		return
	_expect_runtime(
		runner,
		"arena_02_data",
		"Restart did not preserve a single Arena 02 runtime."
	)
	_expect(
		not runner.intro_active
		and not runner.intro_ui.visible
		and runner.progress_label.text == "КАМПАНИЯ  2 / 11",
		"R restart incorrectly replayed the Arena 02 intro."
	)
	_expect_selector_id("arena_02_data")

	var arena_02_after_r_id := runner.current_runtime.get_instance_id()
	var arena_02_player := (
		runner.current_runtime.get_level_object("player_start") as Player
	)
	_expect(
		is_instance_valid(arena_02_player),
		"Arena 02 campaign runtime has no player."
	)
	if not is_instance_valid(arena_02_player):
		return
	runner.current_runtime.fall_restart_delay = 0.01
	runner.current_runtime.call(
		"_on_death_zone_body_entered",
		arena_02_player
	)
	var fall_restarted := await _wait_for_runtime(
		runner,
		"arena_02_data",
		arena_02_after_r_id
	)
	_expect(
		fall_restarted
		and runner.get_instance_id() == controller_id,
		"Player fall did not restart only the current Arena 02 runtime."
	)
	if not fall_restarted:
		return
	_expect_runtime(
		runner,
		"arena_02_data",
		"Fall restart did not preserve a single Arena 02 runtime."
	)
	_expect(
		not runner.intro_active
		and not runner.intro_ui.visible
		and runner.progress_label.text == "КАМПАНИЯ  2 / 11",
		"Fall restart incorrectly replayed the Arena 02 intro."
	)
	_expect_selector_id("arena_02_data")

	_expect(
		runner.open_level_by_id("tower_assault"),
		"Runner rejected a direct open of the final community arena."
	)
	var opened_final := await _wait_for_runtime(
		runner,
		"tower_assault"
	)
	_expect(
		opened_final
		and runner.get_instance_id() == controller_id,
		"Direct final-arena open replaced or lost the campaign controller."
	)
	if not opened_final:
		return
	_expect_runtime(
		runner,
		"tower_assault",
		"Direct open did not leave exactly one final runtime."
	)
	_expect_intro(
		runner,
		"ARENA 11 / ШТУРМ",
		"АРЕНА 11 / 11",
		"КАМПАНИЯ  11 / 11",
		"Direct final-arena intro is incomplete."
	)
	if not await _wait_for_intro_end(runner):
		_expect(false, "Direct final-arena intro did not finish.")
		return
	_expect_selector_id("tower_assault")
	_expect(
		runner.current_runtime.clear_message
		== CampaignRunner.COMPLETION_CLEAR_MESSAGE
		and runner.current_runtime.clear_message != advance_message,
		"Final arena did not receive its campaign completion message."
	)

	runner.campaign_data["final_behavior"] = "restart_final_level"
	var legacy_final_id := runner.current_runtime.get_instance_id()
	runner.current_runtime.clear_restart_delay = 0.01
	_clear_runtime_enemies(runner.current_runtime)
	var legacy_final_restarted := await _wait_for_runtime(
		runner,
		"tower_assault",
		legacy_final_id
	)
	_expect(
		legacy_final_restarted
		and not runner.is_campaign_complete()
		and not runner.completion_ui.visible
		and not runner.intro_active,
		"restart_final_level no longer restarts the final arena."
	)
	if not legacy_final_restarted:
		return
	runner.campaign_data["final_behavior"] = "show_completion"
	runner.current_runtime.clear_message = (
		CampaignRunner.COMPLETION_CLEAR_MESSAGE
	)

	var clear_race_runtime_id := (
		runner.current_runtime.get_instance_id()
	)
	runner.current_runtime.clear_restart_delay = 0.2
	_clear_runtime_enemies(runner.current_runtime)
	await _press_physical_key(KEY_R)
	var clear_race_restarted := await _wait_for_runtime(
		runner,
		"tower_assault",
		clear_race_runtime_id
	)
	_expect(
		clear_race_restarted
		and not runner.is_campaign_complete()
		and not runner.intro_active,
		"R during final clear delay incorrectly completed the campaign."
	)
	if not clear_race_restarted:
		return
	var restarted_final_id := runner.current_runtime.get_instance_id()
	await _wait_frames(20)
	_expect(
		runner.current_runtime.get_instance_id() == restarted_final_id
		and not runner.is_campaign_complete()
		and not runner.completion_ui.visible,
		"Stale final clear timer affected the restarted final arena."
	)

	var final_runtime_id := runner.current_runtime.get_instance_id()
	var final_runtime_ref: WeakRef = weakref(runner.current_runtime)
	runner.current_runtime.clear_restart_delay = 0.01
	_clear_runtime_enemies(runner.current_runtime)
	_expect(
		runner.current_runtime.pending_outcome == Arena.Outcome.CLEAR
		and runner.current_runtime.status_label.text
		== CampaignRunner.COMPLETION_CLEAR_MESSAGE,
		"Final clear did not use the campaign completion message."
	)
	var completed := await _wait_for_completion(runner)
	_expect(
		completed
		and runner.get_instance_id() == controller_id
		and not is_instance_valid(final_runtime_ref.get_ref())
		and not is_instance_valid(runner.current_runtime)
		and runner.runtime_host.get_child_count() == 0,
		"Final clear did not retire the final runtime cleanly."
	)
	if not completed:
		return
	_expect(
		runner.completion_ui.visible
		and not runner.intro_ui.visible
		and runner.completion_count.text == "11 / 11"
		and runner.completion_restart_button.visible
		and not runner.completion_restart_button.disabled
		and runner.completion_main_menu_button.visible
		and not runner.completion_main_menu_button.disabled
		and runner.progress_label.text == "КАМПАНИЯ  11 / 11",
		"Campaign completion presentation is incomplete."
	)
	_expect_selector_id("tower_assault")
	await _wait_frames(10)
	_expect(
		runner.is_campaign_complete()
		and not is_instance_valid(runner.current_runtime)
		and runner.runtime_host.get_child_count() == 0,
		"Completed campaign did not remain stable."
	)

	var selector := root.get_node_or_null("DebugLevelSelector")
	await _press_physical_key(KEY_F1)
	_expect(
		is_instance_valid(selector)
		and selector.get_node("Menu").visible
		and paused,
		"F1 menu is unavailable on the campaign completion screen."
	)
	await _press_physical_key(KEY_R)
	_expect(
		runner.is_campaign_complete()
		and selector.get_node("Menu").visible
		and paused,
		"R escaped the paused F1 menu on the completion screen."
	)
	await _press_physical_key(KEY_F1)
	_expect(
		is_instance_valid(selector)
		and not selector.get_node("Menu").visible
		and not paused,
		"F1 menu did not close cleanly on the completion screen."
	)

	runner.completion_restart_button.pressed.emit()
	var new_run_started := await _wait_for_runtime(
		runner,
		"arena_01_data",
		final_runtime_id
	)
	_expect(
		new_run_started
		and runner.get_instance_id() == controller_id
		and not runner.is_campaign_complete()
		and not runner.completion_ui.visible,
		"Completion restart button did not start a new campaign."
	)
	if not new_run_started:
		return
	_expect_intro(
		runner,
		"ARENA 01 / ПАТРУЛЬ",
		"АРЕНА 1 / 11",
		"КАМПАНИЯ  1 / 11",
		"New campaign did not show the Arena 01 intro."
	)
	_expect_selector_id("arena_01_data")
	if not await _wait_for_intro_end(runner):
		_expect(false, "New campaign Arena 01 intro did not finish.")


func _expect_intro(
	runner: CampaignRunner,
	expected_title: String,
	expected_meta: String,
	expected_progress: String,
	message: String
) -> void:
	_expect(
		runner.intro_active
		and runner.intro_ui.visible
		and runner.intro_title.text == expected_title
		and runner.intro_meta.text == expected_meta
		and runner.progress_label.text == expected_progress
		and is_instance_valid(runner.current_runtime)
		and runner.current_runtime.process_mode
		== Node.PROCESS_MODE_DISABLED,
		message
	)


func _wait_for_intro_end(runner: CampaignRunner) -> bool:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			not runner.intro_active
			and not runner.intro_ui.visible
			and is_instance_valid(runner.current_runtime)
			and runner.current_runtime.process_mode
			== Node.PROCESS_MODE_INHERIT
		):
			return true
	return false


func _wait_for_completion(runner: CampaignRunner) -> bool:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			runner.is_campaign_complete()
			and runner.completion_ui.visible
			and not runner.transitioning
			and not is_instance_valid(runner.current_runtime)
			and runner.runtime_host.get_child_count() == 0
		):
			return true
	return false


func _wait_frames(frame_count: int) -> void:
	for _frame in frame_count:
		await process_frame
		await physics_frame


func _clear_runtime_enemies(runtime: LevelRuntimeArena) -> void:
	var enemies: Array[Node2D] = []
	for node: Node in get_nodes_in_group("enemies"):
		if runtime.is_ancestor_of(node) and node is Node2D:
			enemies.append(node as Node2D)

	_expect(
		enemies.size() == runtime.enemies_remaining,
		"Runtime enemy count disagrees with the campaign fixture."
	)
	for enemy: Node2D in enemies:
		runtime.call("_on_death_zone_body_entered", enemy)


func _wait_for_runtime(
	runner: CampaignRunner,
	level_id: String,
	previous_runtime_id: int = 0
) -> bool:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			not runner.transitioning
			and runner.get_current_level_id() == level_id
			and is_instance_valid(runner.current_runtime)
			and (
				previous_runtime_id == 0
				or runner.current_runtime.get_instance_id()
				!= previous_runtime_id
			)
		):
			return true
	return false


func _expect_runtime(
	runner: CampaignRunner,
	level_id: String,
	message: String
) -> bool:
	var matches := (
		runner.get_current_level_id() == level_id
		and runner.get_current_level_index()
		== EXPECTED_LEVEL_IDS.find(level_id)
		and is_instance_valid(runner.current_runtime)
		and runner.current_runtime.level_loaded
		and runner.current_runtime.campaign_mode
		and runner.runtime_host.get_child_count() == 1
		and runner.runtime_host.get_child(0) == runner.current_runtime
	)
	_expect(matches, message)
	return matches


func _expect_selector_id(level_id: String) -> void:
	var selector := root.get_node_or_null("DebugLevelSelector")
	_expect(
		is_instance_valid(selector)
		and selector.has_method("get_requested_campaign_level_id")
		and str(
			selector.call("get_requested_campaign_level_id")
		) == level_id,
		"Debug selector did not remember '%s'." % level_id
	)


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


func _cleanup_current_scene() -> void:
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited


func _setup_campaign_progress() -> bool:
	progress_store = root.get_node_or_null(
		"CampaignProgress"
	) as CampaignProgressStore
	if not is_instance_valid(progress_store):
		return false
	var test_progress_path := (
		"user://campaign_progress_test_campaign_%d_%d.json"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	progress_path_configured = (
		progress_store.configure_storage_path_for_tests(
			test_progress_path
		)
	)
	if not progress_path_configured:
		return false
	var clear_result := progress_store.clear_progress()
	return bool(clear_result["ok"])


func _cleanup_campaign_progress() -> void:
	if not progress_path_configured or not is_instance_valid(progress_store):
		return
	progress_store.clear_progress()
	progress_store.restore_default_storage_path()
	progress_path_configured = false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

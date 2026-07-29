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
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var campaign_result := _test_manifest()
	if bool(campaign_result.get("ok", false)):
		await _test_runner_lifecycle(campaign_result)

	await _cleanup_current_scene()
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
		"Campaign order drifted from Arena 01 through Arena 08."
	)
	_expect(
		entries.size() == EXPECTED_LEVEL_IDS.size(),
		"Campaign did not resolve exactly eight entries."
	)
	_expect(
		str(data.get("advance_message", "")).length() > 0,
		"Campaign advance message is empty."
	)
	_expect(
		data.get("final_behavior") == "restart_final_level",
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


func _expect_atomic_failure(result: Dictionary, message: String) -> void:
	_expect(
		not bool(result.get("ok", true))
		and (result.get("data", {}) as Dictionary).is_empty()
		and (result.get("entries", []) as Array).is_empty()
		and not (result.get("errors", []) as Array).is_empty(),
		message
	)


func _test_runner_lifecycle(campaign_result: Dictionary) -> void:
	var runner := RUNNER_SCENE.instantiate() as CampaignRunner
	_expect(is_instance_valid(runner), "Could not instantiate campaign runner.")
	if not is_instance_valid(runner):
		return

	root.add_child(runner)
	current_scene = runner
	await process_frame
	await physics_frame

	var advance_message := str(
		(campaign_result["data"] as Dictionary).get(
			"advance_message",
			""
		)
	)
	var entries: Array = campaign_result["entries"]
	var final_data: Dictionary = entries[entries.size() - 1]["data"]
	var final_clear_message := str(
		final_data.get("clear_message", "")
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
	_expect_selector_id("arena_02_data")

	_expect(
		runner.open_level_by_id("arena_08_data"),
		"Runner rejected a direct open of Arena 08."
	)
	var opened_final := await _wait_for_runtime(
		runner,
		"arena_08_data"
	)
	_expect(
		opened_final
		and runner.get_instance_id() == controller_id,
		"Direct Arena 08 open replaced or lost the campaign controller."
	)
	if not opened_final:
		return
	_expect_runtime(
		runner,
		"arena_08_data",
		"Direct open did not leave exactly one Arena 08 runtime."
	)
	_expect_selector_id("arena_08_data")
	_expect(
		runner.current_runtime.clear_message == final_clear_message
		and runner.current_runtime.clear_message != advance_message,
		"Final Arena 08 incorrectly uses campaign advance_message."
	)

	var arena_08_id := runner.current_runtime.get_instance_id()
	var arena_08_ref: WeakRef = weakref(runner.current_runtime)
	runner.current_runtime.clear_restart_delay = 0.01
	_clear_runtime_enemies(runner.current_runtime)
	_expect(
		runner.current_runtime.pending_outcome == Arena.Outcome.CLEAR
		and runner.current_runtime.status_label.text
		== final_clear_message,
		"Final clear did not use Arena 08's own completion message."
	)
	var final_restarted := await _wait_for_runtime(
		runner,
		"arena_08_data",
		arena_08_id
	)
	_expect(
		final_restarted
		and runner.get_instance_id() == controller_id
		and not arena_08_ref.get_ref(),
		"Final clear did not restart Arena 08 inside the same controller."
	)
	if not final_restarted:
		return
	_expect_runtime(
		runner,
		"arena_08_data",
		"Final restart did not leave exactly one Arena 08 runtime."
	)
	_expect(
		runner.current_runtime.clear_message == final_clear_message,
		"Restarted final arena lost its own clear message."
	)
	_expect_selector_id("arena_08_data")


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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

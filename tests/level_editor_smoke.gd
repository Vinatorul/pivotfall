extends SceneTree

const EDITOR_SCENE := preload("res://scenes/level_editor.tscn")
const LEVEL_DRAFT := preload(
	"res://scripts/editor/level_draft.gd"
)
const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const LEVEL_DATA_VALIDATOR := preload(
	"res://scripts/levels/level_data_validator.gd"
)

var failures: Array[String] = []
var temporary_level_id := ""
var temporary_editor_level_id := ""
var temporary_broken_level_id := ""
var temporary_conflict_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _finalize() -> void:
	_cleanup_temporary_level()


func _run() -> void:
	_test_draft_history()
	_test_storage_round_trip()
	await _test_editor_workflow()

	_cleanup_temporary_level()
	if failures.is_empty():
		print("LEVEL_EDITOR_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _test_draft_history() -> void:
	var default_result: Dictionary = (
		LEVEL_STORAGE.make_default_level("draft_history_smoke")
	)
	_expect(
		bool(default_result["ok"]),
		"Could not create a default draft fixture."
	)
	if not bool(default_result["ok"]):
		return

	var level_draft: LevelDraft = LEVEL_DRAFT.new()
	level_draft.replace(default_result["data"], true)
	_expect(not level_draft.is_dirty(), "Loaded draft started dirty.")
	_expect(
		not level_draft.can_undo() and not level_draft.can_redo(),
		"Loaded draft unexpectedly has history."
	)

	level_draft.set_root_value("title", "HISTORY TEST")
	_expect(
		level_draft.is_dirty() and level_draft.can_undo(),
		"Draft edit did not create dirty undo state."
	)
	level_draft.undo()
	_expect(
		not level_draft.is_dirty()
		and level_draft.to_dictionary()["title"] == "MY ARENA"
		and level_draft.can_redo(),
		"Undo did not restore the clean draft."
	)
	level_draft.redo()
	_expect(
		level_draft.to_dictionary()["title"] == "HISTORY TEST",
		"Redo did not restore the draft edit."
	)
	level_draft.mark_saved()
	_expect(not level_draft.is_dirty(), "mark_saved did not reset dirty state.")

	var long_prefix := "a".repeat(80)
	var long_id := level_draft.make_unique_id(long_prefix)
	_expect(
		long_id.length() == 64,
		"Generated object ID was not capped at 64 characters."
	)
	level_draft.add_object(
		{
			"id": long_id,
			"type": "solid_rect",
			"rect": [40, 40, 20, 20],
		}
	)
	var suffixed_long_id := level_draft.make_unique_id(long_prefix)
	_expect(
		suffixed_long_id.length() <= 64
		and suffixed_long_id != long_id,
		"Unique object ID suffix exceeded the validator limit."
	)


func _test_storage_round_trip() -> void:
	temporary_level_id = "editor_smoke_%d" % Time.get_ticks_usec()
	var unsafe: Dictionary = LEVEL_STORAGE.load_user_level("../escape")
	_expect(
		not bool(unsafe["ok"]),
		"Storage accepted an unsafe level ID."
	)
	for reserved_id: String in ["con", "prn", "com1", "lpt9"]:
		var reserved: Dictionary = LEVEL_STORAGE.make_default_level(
			reserved_id
		)
		_expect(
			not bool(reserved["ok"]),
			"Storage accepted reserved Windows ID '%s'." % reserved_id
		)

	var default_result: Dictionary = (
		LEVEL_STORAGE.make_default_level(temporary_level_id)
	)
	_expect(
		bool(default_result["ok"]),
		"Storage could not create a valid default level."
	)
	if not bool(default_result["ok"]):
		return

	var data: Dictionary = default_result["data"]
	data["title"] = "EDITOR STORAGE SMOKE"
	var saved: Dictionary = LEVEL_STORAGE.save_user_level(data)
	_expect(
		bool(saved["ok"]),
		"Storage could not save a user level: %s" % str(saved["errors"])
	)
	if not bool(saved["ok"]):
		return

	var loaded: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	_expect(
		bool(loaded["ok"])
		and loaded["data"]["title"] == "EDITOR STORAGE SMOKE",
		"Storage round-trip changed the level."
	)

	data["title"] = "EDITOR STORAGE OVERWRITE"
	var overwritten: Dictionary = LEVEL_STORAGE.save_user_level(data)
	var reloaded: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	_expect(
		bool(overwritten["ok"])
		and bool(reloaded["ok"])
		and reloaded["data"]["title"] == "EDITOR STORAGE OVERWRITE",
		"Storage could not safely overwrite a user level."
	)

	var target_path := ProjectSettings.globalize_path(
		"user://levels/%s.json" % temporary_level_id
	)
	var backup_path := ProjectSettings.globalize_path(
		"user://levels/.level_editor.%s.999_999_0.bak"
		% temporary_level_id
	)
	var simulate_interruption_error := DirAccess.rename_absolute(
		target_path,
		backup_path
	)
	_expect(
		simulate_interruption_error == OK
		and not FileAccess.file_exists(target_path),
		"Could not create interrupted-save recovery fixture."
	)
	data["title"] = "EDITOR STORAGE RECOVER NEW"
	var recovery_snapshot: Dictionary = LEVEL_DATA_CODEC.encode(data)
	var temporary_path := ProjectSettings.globalize_path(
		"user://levels/.level_editor.%s.999_999_0.tmp"
		% temporary_level_id
	)
	var temporary_file := FileAccess.open(
		temporary_path,
		FileAccess.WRITE
	)
	if is_instance_valid(temporary_file):
		temporary_file.store_string(recovery_snapshot.get("text", ""))
		temporary_file.close()
	var recovered: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	_expect(
		bool(recovered["ok"])
		and recovered["data"]["title"] == "EDITOR STORAGE RECOVER NEW"
		and FileAccess.file_exists(target_path)
		and not FileAccess.file_exists(backup_path),
		"Storage did not promote the verified temp from an interrupted save."
	)
	_expect(
		not FileAccess.file_exists(temporary_path),
		"Recovery left the promoted temporary file behind."
	)

	var unowned_backup_path := ProjectSettings.globalize_path(
		"user://levels/.%s.manual.bak" % temporary_level_id
	)
	var unowned_backup := FileAccess.open(
		unowned_backup_path,
		FileAccess.WRITE
	)
	if is_instance_valid(unowned_backup):
		unowned_backup.store_string("manual backup")
		unowned_backup.close()
	LEVEL_STORAGE.load_user_level(temporary_level_id)
	_expect(
		FileAccess.file_exists(unowned_backup_path),
		"Recovery deleted a backup it does not own."
	)
	DirAccess.remove_absolute(unowned_backup_path)

	var exists_result: Dictionary = LEVEL_STORAGE.user_level_exists(
		temporary_level_id
	)
	_expect(
		bool(exists_result["ok"]) and bool(exists_result["data"]),
		"Storage existence check missed a saved user level."
	)

	var listed: Dictionary = LEVEL_STORAGE.list_user_levels()
	var found := false
	for entry: Dictionary in listed.get("entries", []):
		if (
			bool(entry.get("ok", false))
			and entry.get("level_id", "") == temporary_level_id
		):
			found = true
	_expect(found, "Saved user level was missing from the level list.")

	var valid_level_text := FileAccess.get_file_as_string(target_path)
	var quarantine_backup_path := ProjectSettings.globalize_path(
		"user://levels/.level_editor.%s.1000_1000_0.bak"
		% temporary_level_id
	)
	var quarantine_backup := FileAccess.open(
		quarantine_backup_path,
		FileAccess.WRITE
	)
	if is_instance_valid(quarantine_backup):
		quarantine_backup.store_string(valid_level_text)
		quarantine_backup.close()
	var invalid_target := FileAccess.open(target_path, FileAccess.WRITE)
	if is_instance_valid(invalid_target):
		invalid_target.store_string(
			"{\"schema_version\":2,\"future\":\"preserve me\"}"
		)
		invalid_target.close()

	var quarantined_recovery: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	var public_recoveries: Array = quarantined_recovery.get(
		"recoveries",
		[]
	)
	temporary_conflict_path = (
		str(public_recoveries[0].get("path", ""))
		if not public_recoveries.is_empty()
		else ""
	)
	_expect(
		bool(quarantined_recovery["ok"])
		and quarantined_recovery["data"]["title"]
		== "EDITOR STORAGE RECOVER NEW"
		and not quarantined_recovery.get("warnings", []).is_empty()
		and not temporary_conflict_path.is_empty()
		and "preserve me"
		in FileAccess.get_file_as_string(temporary_conflict_path),
		"Public storage result did not expose the quarantined target."
	)

	temporary_broken_level_id = (
		"broken_recovery_%d" % Time.get_ticks_usec()
	)
	var broken_backup_path := ProjectSettings.globalize_path(
		"user://levels/.level_editor.%s.1000_1000_0.bak"
		% temporary_broken_level_id
	)
	var broken_backup := FileAccess.open(
		broken_backup_path,
		FileAccess.WRITE
	)
	if is_instance_valid(broken_backup):
		broken_backup.store_string("not json")
		broken_backup.close()
	var list_with_broken: Dictionary = LEVEL_STORAGE.list_user_levels()
	var kept_valid_entry := false
	var reported_broken_entry := false
	for entry: Dictionary in list_with_broken.get("entries", []):
		kept_valid_entry = (
			kept_valid_entry
			or (
				bool(entry.get("ok", false))
				and entry.get("level_id", "") == temporary_level_id
			)
		)
		reported_broken_entry = (
			reported_broken_entry
			or (
				not bool(entry.get("ok", true))
				and entry.get("level_id", "")
				== temporary_broken_level_id
			)
		)
	_expect(
		kept_valid_entry and reported_broken_entry,
		"One broken recovery file hid unrelated valid levels."
	)
	var next_after_broken: Dictionary = (
		LEVEL_STORAGE.next_available_level_id(
			temporary_broken_level_id
		)
	)
	_expect(
		bool(next_after_broken["ok"])
		and next_after_broken["data"]
		!= temporary_broken_level_id,
		"Broken recovery state blocked generation of another level ID."
	)

	_expect(
		not _has_auxiliary_storage_files(temporary_level_id),
		"Successful save left temporary or backup files behind."
	)


func _test_editor_workflow() -> void:
	var editor := EDITOR_SCENE.instantiate() as LevelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame

	_expect(
		bool(editor.validation_result.get("ok", false)),
		"Editor did not open with a valid Arena 01 draft."
	)
	_expect(
		editor.canvas.size.is_equal_approx(Vector2(576, 324)),
		"Editor canvas is not the intended 0.6-scale overview."
	)
	_expect(
		editor.draft.to_dictionary()["objects"].size() == 4,
		"Editor example does not contain four initial objects."
	)
	var broken_ui_index := -1
	for index in editor.load_entries.size():
		if (
			editor.load_entries[index].get("id", "")
			== temporary_broken_level_id
		):
			broken_ui_index = index
			break
	_expect(
		broken_ui_index >= 0
		and editor.load_options.is_item_disabled(broken_ui_index)
		and temporary_broken_level_id in editor.notice_text,
		"Editor did not surface a broken recovery entry to the user."
	)
	_expect(
		not temporary_conflict_path.is_empty()
		and temporary_conflict_path in editor.notice_text,
		"Editor did not keep a quarantine conflict discoverable."
	)

	var selector := root.get_node_or_null("DebugLevelSelector")
	_expect(
		is_instance_valid(selector)
		and selector.context_suppressed
		and not selector.menu.visible
		and not selector.hint.visible,
		"Debug selector was not suppressed in the editor."
	)

	editor.call("_set_tool", "solid_rect")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(420, 380) * 0.6
	)
	editor.canvas.call(
		"_update_drag",
		Vector2(520, 420) * 0.6
	)
	editor.canvas.call(
		"_finish_primary_action",
		Vector2(520, 420) * 0.6
	)
	await process_frame

	var created_id: String = editor.selected_id
	var created := editor.draft.find_object(created_id)
	_expect(
		created.get("type", "") == "solid_rect"
		and created.get("rect", []) == [420, 380, 100, 40],
		"Canvas drag did not create the expected snapped solid."
	)
	var dirty_snapshot := editor.draft.to_dictionary()
	editor.call("_new_level")
	_expect(
		editor.discard_dialog.visible
		and editor.draft.to_dictionary() == dirty_snapshot,
		"New discarded an unsaved draft without confirmation."
	)
	editor.discard_dialog.hide()
	editor.call("_on_discard_confirmed")
	_expect(
		editor.source_label == "НОВЫЙ"
		and editor.draft.is_dirty()
		and not editor.draft.can_undo()
		and bool(editor.validation_result.get("ok", false)),
		"Confirmed New did not create a fresh valid unsaved draft."
	)
	editor.source_label = "ПРИМЕР"
	editor.loaded_user_level_id = ""
	editor.selected_id = created_id
	editor.draft.replace(dirty_snapshot, false)

	editor.call("_set_tool", "select")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(440, 400) * 0.6
	)
	editor.canvas.call(
		"_update_drag",
		Vector2(460, 400) * 0.6
	)
	editor.canvas.call(
		"_finish_primary_action",
		Vector2(460, 400) * 0.6
	)
	await process_frame
	_expect(
		editor.draft.find_object(created_id)["rect"][0] == 440,
		"Canvas drag did not move the selected solid by one grid step."
	)
	editor.call("_undo")
	_expect(
		editor.draft.find_object(created_id)["rect"][0] == 420,
		"Editor Undo did not revert a canvas move."
	)
	editor.call("_redo")
	_expect(
		editor.draft.find_object(created_id)["rect"][0] == 440,
		"Editor Redo did not restore a canvas move."
	)
	var before_keyboard_nudge: int = (
		editor.draft.find_object(created_id)["rect"][0]
	)
	editor.canvas.grab_focus()
	await process_frame
	_expect(
		editor.get_viewport().gui_get_focus_owner() == editor.canvas,
		"Canvas did not receive keyboard focus."
	)
	await _press_physical_key(KEY_RIGHT)
	_expect(
		editor.draft.find_object(created_id)["rect"][0]
		== before_keyboard_nudge + 20,
		"Focused canvas swallowed the arrow-key nudge."
	)
	editor.call("_undo")

	var original_player := (
		editor.draft.find_first_object_of_type("player_spawn")
	)
	editor.call("_set_tool", "player_spawn")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(200, 440) * 0.6
	)
	await process_frame
	var moved_player := (
		editor.draft.find_first_object_of_type("player_spawn")
	)
	var player_count := 0
	for object: Dictionary in editor.draft.to_dictionary()["objects"]:
		if object["type"] == "player_spawn":
			player_count += 1
	_expect(
		player_count == 1
		and moved_player["id"] == original_player["id"]
		and moved_player["position"] == [200, 440],
		"Player tool did not reposition the single existing spawn."
	)
	editor.call("_undo")

	editor.call("_set_tool", "patrol_enemy")
	editor.canvas.call(
		"_begin_primary_action",
		Vector2(600, 440) * 0.6
	)
	await process_frame
	var placed_patrol_id: String = editor.selected_id
	var placed_patrol := editor.draft.find_object(placed_patrol_id)
	_expect(
		placed_patrol.get("type", "") == "patrol_enemy"
		and placed_patrol.get("position", []) == [600, 440]
		and is_equal_approx(float(placed_patrol.get("speed", -1)), 65.0)
		and placed_patrol.get("direction", 0) == 1,
		"Patrol tool did not create an enemy with safe defaults."
	)
	editor.call("_duplicate_selected")
	var duplicate_patrol_id: String = editor.selected_id
	var duplicate_patrol := editor.draft.find_object(
		duplicate_patrol_id
	)
	_expect(
		not duplicate_patrol_id.is_empty()
		and duplicate_patrol_id != placed_patrol_id
		and duplicate_patrol.get("position", []) == [620, 460]
		and duplicate_patrol.get("speed", -1)
		== placed_patrol.get("speed", -2),
		"Duplicate did not preserve patrol properties and offset its copy."
	)
	editor.call("_delete_selected")
	_expect(
		editor.draft.find_object(duplicate_patrol_id).is_empty(),
		"Delete did not remove the selected patrol."
	)
	editor.call("_undo")
	_expect(
		not editor.draft.find_object(duplicate_patrol_id).is_empty(),
		"Undo did not restore the deleted patrol."
	)
	editor.call("_undo")
	editor.call("_undo")
	_expect(
		editor.draft.find_object(placed_patrol_id).is_empty()
		and editor.draft.find_object(duplicate_patrol_id).is_empty(),
		"Palette regression fixture did not undo cleanly."
	)

	temporary_editor_level_id = (
		"editor_ui_smoke_%d" % Time.get_ticks_usec()
	)
	editor.level_id_edit.text = temporary_editor_level_id
	editor.title_edit.text = "EDITOR UI SAVE"
	editor.call("_save_level")
	var ui_saved: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_editor_level_id
	)
	_expect(
		bool(ui_saved["ok"])
		and ui_saved["data"]["title"] == "EDITOR UI SAVE"
		and not editor.draft.is_dirty(),
		"Editor Save did not persist and mark the current draft clean."
	)
	_expect(
		not _has_auxiliary_storage_files(temporary_editor_level_id),
		"Editor Save left temporary or backup files behind."
	)
	var selected_entry: Dictionary = editor.load_entries[
		editor.load_options.selected
	]
	_expect(
		selected_entry.get("kind", "") == "user"
		and selected_entry.get("id", "") == temporary_editor_level_id,
		"Editor Save did not select the saved user-level entry."
	)
	editor.draft.set_root_value("title", "UNSAVED TITLE")
	editor.call("_load_selected_level")
	_expect(
		editor.discard_dialog.visible,
		"Load did not ask before discarding an unsaved edit."
	)
	editor.discard_dialog.hide()
	editor.call("_on_discard_confirmed")
	_expect(
		editor.draft.to_dictionary()["title"] == "EDITOR UI SAVE"
		and not editor.draft.is_dirty(),
		"Confirmed Load did not restore the saved user level."
	)

	var patrol: Dictionary = (
		editor.draft.find_first_object_of_type("patrol_enemy")
	)
	editor.call("_select_object", patrol["id"])
	await process_frame
	var direction_options: OptionButton
	for row: Node in editor.properties.get_children():
		for child: Node in row.get_children():
			if child is OptionButton:
				direction_options = child as OptionButton
				break
		if is_instance_valid(direction_options):
			break
	_expect(
		is_instance_valid(direction_options),
		"Patrol inspector did not expose a direction selector."
	)
	if is_instance_valid(direction_options):
		direction_options.select(0)
		direction_options.item_selected.emit(0)
		await process_frame
		_expect(
			editor.draft.find_object(patrol["id"])["direction"] == -1
			and bool(editor.validation_result.get("ok", false)),
			(
				"Left patrol direction became invalid in the inspector: "
				+ "direction=%s errors=%s"
			)
			% [
				editor.draft.find_object(patrol["id"])["direction"],
				editor.validation_result.get("errors", []),
			]
		)

	var speed_field := _find_property_editor(
		editor,
		"SPEED"
	) as LineEdit
	_expect(
		is_instance_valid(speed_field),
		"Patrol inspector did not expose its speed field."
	)
	if is_instance_valid(speed_field):
		speed_field.text = "0"
		speed_field.text_submitted.emit("0")
		await process_frame
		_expect(
			bool(editor.validation_result.get("ok", false))
			and editor.validation_result.get("warnings", []).size() >= 1
			and not editor.save_button.disabled
			and not editor.test_button.disabled
			and "zero speed" in editor.problems.text,
			"Zero-speed warning blocked the level or was not shown."
		)
		editor.call("_undo")

	editor.draft.set_root_value("level_id", temporary_level_id)
	editor.draft.set_root_value("title", "OVERWRITE ATTEMPT")
	editor.call("_save_level")
	var untouched_conflict: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	_expect(
		editor.discard_dialog.visible
		and editor.pending_destructive_action == "overwrite"
		and untouched_conflict["data"]["title"]
		== "EDITOR STORAGE RECOVER NEW",
		"Editor overwrote another user level without confirmation."
	)
	editor.discard_dialog.hide()
	editor.call("_on_discard_confirmed")
	var confirmed_overwrite: Dictionary = LEVEL_STORAGE.load_user_level(
		temporary_level_id
	)
	_expect(
		bool(confirmed_overwrite["ok"])
		and confirmed_overwrite["data"]["title"] == "OVERWRITE ATTEMPT"
		and editor.loaded_user_level_id == temporary_level_id,
		"Confirmed overwrite did not save the current draft."
	)

	var player: Dictionary = (
		editor.draft.find_first_object_of_type("player_spawn")
	)
	editor.call("_select_object", player["id"])
	editor.call("_delete_selected")
	_expect(
		not bool(editor.validation_result.get("ok", false))
		and editor.test_button.disabled
		and editor.save_button.disabled,
		"Invalid draft did not block Save and Test."
	)
	editor.call("_start_playtest")
	_expect(
		not is_instance_valid(editor.playtest_runtime),
		"Invalid draft unexpectedly started a playtest."
	)
	editor.call("_undo")
	_expect(
		bool(editor.validation_result.get("ok", false)),
		"Undo did not restore the required player."
	)

	editor.call("_select_object", created_id)
	var draft_before := editor.draft.to_dictionary()
	var selected_before: String = editor.selected_id
	var could_undo_before: bool = editor.draft.can_undo()
	var could_redo_before: bool = editor.draft.can_redo()
	var current_scene_id := editor.get_instance_id()

	editor.canvas.grab_focus()
	await process_frame
	await _press_physical_key(KEY_F5)
	if not _require(
		is_instance_valid(editor.playtest_runtime)
		and not editor.editor_view.visible
		and editor.playtest_overlay.visible,
		"F5 did not enter embedded playtest mode."
	):
		return
	_expect(
		is_instance_valid(current_scene)
		and current_scene.get_instance_id() == current_scene_id,
		"Playtest replaced the editor current scene."
	)
	_expect(
		editor.playtest_runtime.level_loaded
		and editor.playtest_runtime.embedded_mode,
		"Embedded runtime did not load the immutable snapshot."
	)

	var first_runtime_id := editor.playtest_runtime.get_instance_id()
	await _press_physical_key(KEY_R)
	for _frame in 60:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and editor.playtest_runtime.get_instance_id()
			!= first_runtime_id
		):
			break
	_expect(
		is_instance_valid(editor.playtest_runtime)
		and editor.playtest_runtime.get_instance_id() != first_runtime_id,
		"R did not recreate the embedded runtime."
	)

	var fall_runtime_id := editor.playtest_runtime.get_instance_id()
	editor.playtest_runtime.fall_restart_delay = 0.01
	var runtime_player := (
		editor.playtest_runtime.get_level_object(player["id"]) as Player
	)
	runtime_player.global_position = Vector2(480, 530)
	runtime_player.velocity = Vector2.ZERO
	for _frame in 90:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and editor.playtest_runtime.get_instance_id()
			!= fall_runtime_id
		):
			break
	_expect(
		is_instance_valid(editor.playtest_runtime)
		and editor.playtest_runtime.get_instance_id() != fall_runtime_id,
		"Player fall did not restart the same embedded snapshot."
	)

	var clear_runtime_id := editor.playtest_runtime.get_instance_id()
	editor.playtest_runtime.clear_restart_delay = 0.01
	var runtime_enemy := (
		editor.playtest_runtime.get_level_object(patrol["id"])
		as PatrolEnemy
	)
	runtime_enemy.global_position = Vector2(480, 530)
	runtime_enemy.velocity = Vector2.ZERO
	for _frame in 90:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(editor.playtest_runtime)
			and editor.playtest_runtime.get_instance_id()
			!= clear_runtime_id
		):
			break
	_expect(
		is_instance_valid(editor.playtest_runtime)
		and editor.playtest_runtime.get_instance_id() != clear_runtime_id,
		"Clear did not restart the same embedded snapshot."
	)

	var escaping_runtime := editor.playtest_runtime
	escaping_runtime.embedded_restart_requested.emit()
	_expect(
		editor.playtest_transitioning
		and not is_instance_valid(editor.playtest_runtime),
		"Restart did not enter the expected transition window."
	)
	await _press_physical_key(KEY_ESCAPE)
	await process_frame
	_expect(
		not is_instance_valid(editor.playtest_runtime)
		and editor.editor_view.visible
		and not editor.playtest_overlay.visible,
		"Esc did not return from playtest to the editor."
	)
	_expect(
		editor.draft.to_dictionary() == draft_before
		and editor.selected_id == selected_before
		and editor.draft.can_undo() == could_undo_before
		and editor.draft.can_redo() == could_redo_before,
		"Playtest return changed the draft, selection, or Undo history."
	)

	editor.draft.set_root_value("title", "DIRTY EXIT CHECK")
	editor.call("_select_object", "")
	editor.call("_request_return_to_game")
	_expect(
		editor.discard_dialog.visible
		and editor.pending_destructive_action == "exit",
		"Editor exit did not protect an unsaved draft."
	)
	editor.discard_dialog.hide()
	editor.call("_clear_pending_destructive_action")

	await _press_physical_key(KEY_F1)
	_expect(
		not selector.menu.visible and not paused,
		"Suppressed debug selector reacted to F1."
	)

	var expected_return_path := str(
		selector.get_editor_return_scene_path()
	)
	editor.draft.mark_saved()
	editor.exit_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(
		is_instance_valid(current_scene)
		and current_scene.scene_file_path == expected_return_path
		and not selector.context_suppressed
		and selector.hint.visible,
		"Game button did not restore the source arena and debug selector."
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


func _find_property_editor(
	editor: LevelEditor,
	label_text: String
) -> Control:
	for row: Node in editor.properties.get_children():
		if not row is HBoxContainer:
			continue
		var children := row.get_children()
		if (
			children.size() >= 2
			and children[0] is Label
			and (children[0] as Label).text == label_text
			and children[1] is Control
		):
			return children[1] as Control
	return null


func _has_auxiliary_storage_files(level_id: String) -> bool:
	var directory := DirAccess.open("user://levels")
	if not is_instance_valid(directory):
		return false
	directory.include_hidden = true
	for file_name: String in directory.get_files():
		if (
			file_name.begins_with(
				".level_editor.%s." % level_id
			)
			and (
				file_name.ends_with(".tmp")
				or file_name.ends_with(".bak")
			)
		):
			return true
	return false


func _cleanup_temporary_level() -> void:
	var directory := DirAccess.open("user://levels")
	if is_instance_valid(directory):
		directory.include_hidden = true
	for level_id: String in [
		temporary_level_id,
		temporary_editor_level_id,
		temporary_broken_level_id,
	]:
		if level_id.is_empty():
			continue
		var target := ProjectSettings.globalize_path(
			"user://levels/%s.json" % level_id
		)
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target)

		if not is_instance_valid(directory):
			continue
		for file_name: String in directory.get_files():
			if file_name.begins_with(
				".level_editor.%s." % level_id
			):
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path(
						"user://levels/%s" % file_name
					)
				)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _require(condition: bool, message: String) -> bool:
	_expect(condition, message)
	return condition

extends SceneTree

const CAMPAIGN_STORAGE := preload(
	"res://scripts/campaign/campaign_storage.gd"
)
const ARENA_SELECT_SCENE := preload(
	"res://scenes/arena_select.tscn"
)
const MAIN_MENU_SCENE := preload(
	"res://scenes/main_menu.tscn"
)
const ARENA_SELECT_PATH := "res://scenes/arena_select.tscn"
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const CAMPAIGN_PATH := "res://scenes/campaign_runner.tscn"
const EXPECTED_ARENA_COUNT := 16

var failures: Array[String] = []
var progress_store: CampaignProgressStore
var progress_path_configured := false
var campaign_entries: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	progress_store = root.get_node_or_null(
		"CampaignProgress"
	) as CampaignProgressStore
	_expect(
		is_instance_valid(progress_store),
		"Campaign progress autoload is unavailable."
	)
	if not is_instance_valid(progress_store):
		_finish()
		return

	var test_progress_path := (
		"user://campaign_progress_test_arena_select_%d_%d.json"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	progress_path_configured = (
		progress_store.configure_storage_path_for_tests(
			test_progress_path
		)
	)
	_expect(
		progress_path_configured,
		"Could not isolate Arena Select campaign progress."
	)
	if not progress_path_configured:
		_finish()
		return
	progress_store.clear_progress()

	var campaign_result := CAMPAIGN_STORAGE.load_builtin_campaign()
	_expect(
		bool(campaign_result.get("ok", false)),
		"Built-in campaign is unavailable."
	)
	_expect(
		bool(
			ProjectSettings.get_setting(
				"input_devices/pointing/emulate_mouse_from_touch",
				false
			)
		),
		"Project touch-to-mouse UI contract is disabled."
	)
	if not bool(campaign_result.get("ok", false)):
		_finish()
		return
	for raw_entry: Variant in campaign_result.get("entries", []):
		if typeof(raw_entry) == TYPE_DICTIONARY:
			campaign_entries.append(
				(raw_entry as Dictionary).duplicate(true)
			)
	_expect(
		campaign_entries.size() == EXPECTED_ARENA_COUNT
		and str(campaign_entries[-1].get("id", ""))
		== "arena_16_data",
		"Arena Select manifest did not expose Arena 16 as the final entry."
	)

	var started := progress_store.begin_new_game(campaign_entries)
	_expect(
		bool(started.get("ok", false)),
		"Could not create progress for Arena Select."
	)
	progress_store.cancel_launch_request()
	_expect(
		_unlock_range(1, 4),
		"Could not unlock the Arena 05 selector fixture."
	)

	var selector := await _replace_with_arena_select()
	_expect_selector_ready(selector)
	if (
		not is_instance_valid(selector)
		or selector.arena_buttons.size() < 6
	):
		_finish()
		return

	await _press_physical_key(KEY_W)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[1],
		"W did not move selector focus one grid row up."
	)
	await _press_physical_key(KEY_S)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[4],
		"S did not move selector focus one grid row down."
	)
	await _press_physical_key(KEY_A)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[3],
		"A did not move selector focus left."
	)
	await _press_physical_key(KEY_D)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[4],
		"D did not move selector focus right."
	)
	await _press_physical_key(KEY_UP)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[1],
		"Up did not follow the selector focus graph."
	)
	await _press_physical_key(KEY_DOWN)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[4],
		"Down did not follow the selector focus graph."
	)

	await _drag_touch(selector.arena_buttons[1], 10, 13.0)
	var drag_request := progress_store.consume_launch_request()
	await _cancel_touch(selector.arena_buttons[1], 11)
	var canceled_request := progress_store.consume_launch_request()
	_expect(
		current_scene == selector
		and not selector.transitioning
		and str(drag_request.get("level_id", "")).is_empty()
		and str(canceled_request.get("level_id", "")).is_empty(),
		"A scrolling or canceled touch launched an arena."
	)

	await _click_mouse(selector.arena_buttons[5])
	_expect(
		current_scene == selector
		and not selector.transitioning
		and str(
			progress_store.consume_launch_request().get(
				"level_id",
				""
			)
		).is_empty(),
		"A locked arena accepted a mouse launch request."
	)

	await _press_physical_key(KEY_ESCAPE)
	var menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(menu)
		and menu is MainMenu
		and (menu as MainMenu).arena_select_button.visible,
		"Esc did not return Arena Select to a valid main menu."
	)

	selector = await _replace_with_arena_select()
	if not is_instance_valid(selector):
		_finish()
		return
	await _tap_touch(selector.back_button, 12)
	var touch_back_menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(touch_back_menu),
		"Touching Back did not return to the main menu."
	)

	selector = await _replace_with_arena_select()
	if not is_instance_valid(selector):
		_finish()
		return
	selector.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var system_back_menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(system_back_menu),
		"The mobile system Back notification did not return to the menu."
	)

	selector = await _replace_with_arena_select()
	if not is_instance_valid(selector):
		_finish()
		return
	await _click_mouse(selector.arena_buttons[1])
	var mouse_runner := await _wait_for_scene(CAMPAIGN_PATH)
	_expect(
		is_instance_valid(mouse_runner)
		and mouse_runner is CampaignRunner
		and (mouse_runner as CampaignRunner).get_current_level_id()
		== str(campaign_entries[1].get("id", ""))
		and not (mouse_runner as CampaignRunner).is_tracking_progress(),
		"Mouse did not launch the selected arena as replay."
	)

	selector = await _replace_with_arena_select()
	if not is_instance_valid(selector):
		_finish()
		return
	await _tap_touch(selector.arena_buttons[3], 0)
	var touch_runner := await _wait_for_scene(CAMPAIGN_PATH)
	_expect(
		is_instance_valid(touch_runner)
		and touch_runner is CampaignRunner
		and (touch_runner as CampaignRunner).get_current_level_id()
		== str(campaign_entries[3].get("id", ""))
		and not (touch_runner as CampaignRunner).is_tracking_progress(),
		"Touch did not launch the selected arena as replay."
	)

	_expect(
		_unlock_range(5, campaign_entries.size() - 1),
		"Could not unlock the completed-selector fixture."
	)
	var completed := progress_store.mark_completed(campaign_entries)
	_expect(
		bool(completed.get("ok", false)),
		"Could not complete progress for Arena Select."
	)

	selector = await _replace_with_arena_select()
	if is_instance_valid(selector):
		var all_completed: bool = selector.progress_completed
		for button: Button in selector.arena_buttons:
			all_completed = (
				all_completed
				and not button.disabled
				and button.text.contains("ПРОЙДЕНА")
			)
		_expect(
			all_completed
			and root.get_viewport().gui_get_focus_owner()
			== selector.arena_buttons[-1],
			(
				"Completed progress did not expose all arenas "
				+ "or focus the final arena."
			)
		)
		await _test_completed_final_replay(selector)

	var completed_menu := await _replace_with_main_menu()
	_expect(
		is_instance_valid(completed_menu)
		and completed_menu.progress_completed
		and completed_menu.arena_select_button.visible
		and not completed_menu.arena_select_button.disabled
		and root.get_viewport().gui_get_focus_owner()
		== completed_menu.arena_select_button,
		"Completed save did not retain Arena Select in the main menu."
	)

	_finish()


func _test_completed_final_replay(selector: Node) -> void:
	var completed_bytes := FileAccess.get_file_as_bytes(
		progress_store.get_storage_path()
	)
	await _click_mouse(selector.arena_buttons[-1])
	var final_replay := await _wait_for_scene(CAMPAIGN_PATH)
	_expect(
		is_instance_valid(final_replay)
		and final_replay is CampaignRunner
		and (final_replay as CampaignRunner).get_current_level_id()
		== "arena_16_data"
		and (final_replay as CampaignRunner).is_replay_mode()
		and not (final_replay as CampaignRunner).is_tracking_progress()
		and FileAccess.get_file_as_bytes(
			progress_store.get_storage_path()
		) == completed_bytes,
		"Arena 16 replay changed completed campaign progress."
	)


func _expect_selector_ready(selector: Node) -> void:
	_expect(
		is_instance_valid(selector)
		and selector.scene_file_path == ARENA_SELECT_PATH
		and selector.has_valid_progress
		and selector.arena_grid.columns == 3
		and selector.arena_buttons.size() == EXPECTED_ARENA_COUNT
		and selector.arena_buttons.size() == campaign_entries.size(),
		"Arena Select did not build the manifest-driven grid."
	)
	if (
		not is_instance_valid(selector)
		or selector.arena_buttons.size() < 6
	):
		return

	var all_visible := true
	var touch_targets_are_large := true
	for button: Button in selector.arena_buttons:
		all_visible = all_visible and button.visible
		touch_targets_are_large = (
			touch_targets_are_large
			and button.custom_minimum_size.y >= 48.0
		)
	_expect(
		all_visible and touch_targets_are_large,
		"Arena buttons are hidden or too small for touch."
	)
	_expect(
		selector.arena_buttons[0].text.contains("ПРОЙДЕНА")
		and selector.arena_buttons[3].text.contains("ПРОЙДЕНА")
		and selector.arena_buttons[4].text.contains("ТЕКУЩАЯ")
		and not selector.arena_buttons[4].disabled
		and selector.arena_buttons[5].text.contains("ЗАКРЫТА")
		and selector.arena_buttons[5].disabled,
		"Arena Select did not expose completed/current/locked states."
	)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== selector.arena_buttons[4],
		"Arena Select did not focus the current arena initially."
	)


func _unlock_range(first_index: int, last_index: int) -> bool:
	if last_index < first_index:
		return true
	for index in range(first_index, last_index + 1):
		var advanced := progress_store.record_level_started(
			campaign_entries,
			str(campaign_entries[index].get("id", ""))
		)
		if not bool(advanced.get("ok", false)):
			return false
	return true


func _replace_with_arena_select() -> Node:
	await _clear_current_scene()
	var selector := ARENA_SELECT_SCENE.instantiate()
	root.add_child(selector)
	current_scene = selector
	await process_frame
	await process_frame
	return selector


func _replace_with_main_menu() -> MainMenu:
	await _clear_current_scene()
	var menu := MAIN_MENU_SCENE.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	return menu


func _clear_current_scene() -> void:
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited


func _wait_for_scene(scene_path: String) -> Node:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(current_scene)
			and current_scene.scene_file_path == scene_path
		):
			return current_scene
	return null


func _press_physical_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	root.push_input(press)
	await process_frame
	await physics_frame

	var release := InputEventKey.new()
	release.physical_keycode = key
	release.keycode = key
	release.pressed = false
	root.push_input(release)
	await process_frame


func _click_mouse(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame

	var press := InputEventMouseButton.new()
	press.window_id = root.get_window_id()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.pressed = true
	root.push_input(press, true)
	await process_frame

	var release := InputEventMouseButton.new()
	release.window_id = root.get_window_id()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _tap_touch(control: Control, index: int) -> void:
	var position := control.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.window_id = root.get_window_id()
	press.index = index
	press.position = position
	press.pressed = true
	current_scene.call("_input", press)
	await process_frame

	var release := InputEventScreenTouch.new()
	release.window_id = root.get_window_id()
	release.index = index
	release.position = position
	release.pressed = false
	current_scene.call("_input", release)
	await process_frame


func _drag_touch(
	control: Control,
	index: int,
	distance: float
) -> void:
	var start := control.get_global_rect().get_center()
	var end := start + Vector2(distance, 0.0)
	var press := InputEventScreenTouch.new()
	press.window_id = root.get_window_id()
	press.index = index
	press.position = start
	press.pressed = true
	current_scene.call("_input", press)

	var drag := InputEventScreenDrag.new()
	drag.window_id = root.get_window_id()
	drag.index = index
	drag.position = end
	drag.relative = end - start
	current_scene.call("_input", drag)

	var release := InputEventScreenTouch.new()
	release.window_id = root.get_window_id()
	release.index = index
	release.position = end
	release.pressed = false
	current_scene.call("_input", release)
	await process_frame


func _cancel_touch(control: Control, index: int) -> void:
	var position := control.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.window_id = root.get_window_id()
	press.index = index
	press.position = position
	press.pressed = true
	current_scene.call("_input", press)

	var release := InputEventScreenTouch.new()
	release.window_id = root.get_window_id()
	release.index = index
	release.position = position
	release.pressed = false
	release.canceled = true
	current_scene.call("_input", release)
	await process_frame


func _finish() -> void:
	await _clear_current_scene()

	if progress_path_configured and is_instance_valid(progress_store):
		var clear_result := progress_store.clear_progress()
		if not bool(clear_result.get("ok", false)):
			failures.append(
				"Could not clean isolated Arena Select progress."
			)
		progress_store.restore_default_storage_path()

	if failures.is_empty():
		print("ARENA_SELECT_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

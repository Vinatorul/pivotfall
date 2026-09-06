extends SceneTree

const RUNNER_SCENE := preload(
	"res://scenes/campaign_runner.tscn"
)
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"

var failures: Array[String] = []
var progress_store: CampaignProgressStore
var progress_path_configured := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(960, 540)
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
		"user://campaign_progress_test_pause_%d_%d.json"
		% [OS.get_process_id(), Time.get_ticks_usec()]
	)
	progress_path_configured = (
		progress_store.configure_storage_path_for_tests(
			test_progress_path
		)
	)
	_expect(
		progress_path_configured,
		"Could not isolate pause campaign progress."
	)
	if not progress_path_configured:
		_finish()
		return
	progress_store.clear_progress()

	var selector := root.get_node_or_null("DebugLevelSelector")
	_expect(
		is_instance_valid(selector),
		"Debug selector autoload is unavailable."
	)
	if not is_instance_valid(selector):
		_finish()
		return

	selector.call("remember_requested_campaign_level_id", "")
	var runner := RUNNER_SCENE.instantiate() as CampaignRunner
	runner.intro_duration = 0.01
	root.add_child(runner)
	current_scene = runner
	var runtime := await _wait_for_playing_runtime(runner)
	_expect(
		is_instance_valid(runtime)
		and runner.get_current_level_id() == "arena_01_data"
		and not paused and not runner.pause_menu.is_open(),
		"Campaign did not reach playable Arena 01."
	)
	if not is_instance_valid(runtime):
		_finish()
		return

	var enemy := (
		runtime.get_level_object("patrol_1") as PatrolEnemy
	)
	var active_start := enemy.global_position
	await _wait_physics_frames(8)
	_expect(
		enemy.global_position.distance_to(active_start) > 0.5,
		"Patrol fixture did not move before pausing."
	)

	await _test_help_stops_game(runner)
	await _test_hud_help(runner)
	await _test_pause_to_help(runner)
	var runtime_id := runtime.get_instance_id()
	runner.mobile_controls.set_touchscreen_override_for_tests(true, true)
	runner.mobile_controls.set_active(true)
	_expect(
		runner.mobile_controls.is_active(),
		"Forced mobile controls did not appear during gameplay."
	)
	await _tap_ui_button(runner.current_runtime.pause_button, 0)
	await process_frame
	_expect_pause_open(runner, selector, runtime_id)
	_expect_pause_content(runner.pause_menu, true)
	_expect(
		not runner.mobile_controls.is_active()
		and not Input.is_action_pressed("mobile_pause"),
		"Opening pause did not hide and release mobile controls."
	)
	var paused_enemy_position := enemy.global_position
	await _wait_process_frames(8)
	_expect(
		enemy.global_position.distance_to(paused_enemy_position) < 0.001,
		"Gameplay continued moving while the pause menu was open."
	)

	await _press_physical_key(KEY_F1)
	_expect(
		runner.pause_menu.is_open()
		and paused
		and not selector.menu.visible,
		"F1 escaped or overlaid the campaign pause menu."
	)

	await _press_physical_key(KEY_S)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.restart_button,
		"S did not move pause focus to Restart."
	)
	await _press_physical_key(KEY_S)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.main_menu_button,
		"S did not move pause focus to Main Menu."
	)
	await _press_physical_key(KEY_S)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.resume_button,
		"S did not wrap pause focus to Resume."
	)
	await _press_physical_key(KEY_W)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.main_menu_button,
		"W did not wrap pause focus to Main Menu."
	)
	await _press_physical_key(KEY_DOWN)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.resume_button,
		"Down arrow did not wrap pause focus to Resume."
	)
	await _press_physical_key(KEY_UP)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.main_menu_button,
		"Up arrow did not wrap pause focus to Main Menu."
	)

	await _press_physical_key(KEY_ESCAPE)
	await _wait_physics_frames(3)
	_expect_resumed(runner, selector, runtime_id)
	_expect(
		runner.mobile_controls.is_active(),
		"Mobile controls did not return after resuming gameplay."
	)
	var resumed_enemy_position := enemy.global_position
	await _wait_physics_frames(8)
	_expect(
		enemy.global_position.distance_to(resumed_enemy_position) > 0.5,
		"Patrol did not resume after closing the pause menu."
	)

	await _press_physical_key(KEY_ESCAPE)
	runner.pause_menu.resume_button.pressed.emit()
	await _wait_physics_frames(3)
	_expect_resumed(runner, selector, runtime_id)

	var old_runtime_ref: WeakRef = weakref(runner.current_runtime)
	var old_runtime_id := runner.current_runtime.get_instance_id()
	var old_level_id := runner.get_current_level_id()
	var old_level_index := runner.get_current_level_index()
	var gameplay_scale := root.content_scale_size
	root.size = Vector2i(390, 844)
	await _press_physical_key(KEY_ESCAPE)
	runner.pause_menu.restart_button.pressed.emit()
	var restarted_runtime := await _wait_for_restarted_runtime(
		runner,
		old_runtime_id
	)
	_expect(
		is_instance_valid(restarted_runtime)
		and old_runtime_ref.get_ref() == null
		and runner.get_current_level_id() == old_level_id
		and runner.get_current_level_index() == old_level_index
		and runner.runtime_host.get_child_count() == 1
		and runner.phase == CampaignRunner.Phase.PLAYING
		and not runner.intro_active
		and not runner.pause_menu.is_open()
		and not paused
		and root.content_scale_size == gameplay_scale
		and not selector.context_suppressed
		and selector.get_requested_campaign_level_id() == old_level_id,
		"Pause restart did not replace the current arena cleanly."
	)

	root.size = Vector2i(960, 540)
	await _test_long_help(runner)
	await _press_physical_key(KEY_ESCAPE)
	_expect(
		runner.pause_menu.is_open() and paused,
		"Pause menu did not reopen after restarting the arena."
	)
	runner.pause_menu.main_menu_button.pressed.emit()
	var main_menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(main_menu)
		and not paused
		and selector.context_suppressed
		and not selector.menu.visible
		and not selector.hint.visible,
		"Pause menu did not return to a clean main menu."
	)

	_finish()


func _test_help_stops_game(runner: CampaignRunner) -> void:
	await _press_physical_key(KEY_H)
	_expect(runner.pause_menu.is_open() and paused, "Requested help did not pause.")
	if not runner.pause_menu.is_open():
		return
	var runtime := runner.current_runtime
	var enemy := runtime.get_level_object("patrol_1") as PatrolEnemy
	var position_before := enemy.global_position
	await _wait_process_frames(12)
	_expect(
		runner.pause_menu.is_open() and enemy.global_position == position_before,
		"Help expired or gameplay moved during reading."
	)
	_expect(
		(
			str(runtime.level_data["objective"]) in runner.pause_menu.objective_label.text
			and "смерт" in runner.pause_menu.objective_label.text.to_lower()
		),
		"Help omitted the objective or lethal contact."
	)
	_expect_help_content(runner.pause_menu)
	await _press_physical_key(KEY_SPACE)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)


func _test_hud_help(runner: CampaignRunner) -> void:
	var runtime := runner.current_runtime
	_expect(
		(
			runtime.help_button.visible
			and runtime.pause_button.visible
			and runtime.progress_label.text == "1/%d" % runner.get_level_count()
			and "GRAYBOX" not in runtime.title_label.text
			and "DATA" not in runtime.title_label.text
		),
		"Runtime HUD omitted its actions/count or retained service labels."
	)
	await _press_physical_key(KEY_H)
	_expect(runner.pause_menu.is_open() and paused, "H did not open arena help.")
	await _press_physical_key(KEY_H)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)
	await _click_ui_button(runtime.help_button)
	_expect(runner.pause_menu.is_open() and paused, "Mouse ? did not open help.")
	await _press_physical_key(KEY_ESCAPE)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)
	await _test_touch_help(runner)


func _test_touch_help(runner: CampaignRunner) -> void:
	runner.mobile_controls.set_touchscreen_override_for_tests(true, true)
	runner.mobile_controls.set_active(true)
	await _tap_ui_button(runner.current_runtime.help_button, 0)
	_expect(runner.pause_menu.is_open() and paused, "Touch ? did not open help.")
	_expect_help_content(runner.pause_menu)
	await _tap_ui_button(runner.pause_menu.resume_button, 0)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)


func _test_pause_to_help(runner: CampaignRunner) -> void:
	runner.mobile_controls.set_touchscreen_override_for_tests(true, false)
	await _press_physical_key(KEY_ESCAPE)
	_expect_pause_content(runner.pause_menu, false)
	await _press_physical_key(KEY_H)
	_expect(runner.pause_menu.is_open() and paused, "H resumed instead of showing help.")
	_expect_help_content(runner.pause_menu)
	for key: Key in [KEY_S, KEY_W, KEY_DOWN, KEY_UP]:
		await _press_physical_key(key)
		_expect(
			root.gui_get_focus_owner() == runner.pause_menu.resume_button,
			"Help keyboard focus moved to a hidden pause action."
		)
	await _press_physical_key(KEY_H)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)


func _expect_help_content(menu: CampaignPauseMenu) -> void:
	_expect(
		(
			menu.is_help_view()
			and menu.title_label.text == "Подсказка"
			and menu.objective_label.visible
			and not menu.controls_label.visible
			and menu.resume_button.text == "К игре"
			and not menu.restart_button.visible
			and not menu.main_menu_button.visible
		),
		"Help retained controls or pause actions, or hid its objective."
	)


func _expect_pause_content(menu: CampaignPauseMenu, touch: bool) -> void:
	_expect(
		(
			not menu.is_help_view()
			and menu.title_label.text == "Пауза"
			and not menu.objective_label.visible
			and menu.controls_label.visible
			and menu.resume_button.text == "Продолжить"
			and menu.restart_button.visible
			and menu.main_menu_button.visible
		),
		"Pause retained arena help or omitted its three actions and controls."
	)
	_expect(
		("JUMP" in menu.controls_label.text) if touch else ("Пробел" in menu.controls_label.text),
		"Pause shows controls for the wrong input device."
	)


func _test_long_help(runner: CampaignRunner) -> void:
	_expect(runner.open_level_by_id("arena_16_data"), "Could not open Arena 16.")
	await _wait_for_playing_runtime(runner)
	_expect(
		(
			runner.get_current_level_id() == "arena_16_data"
			and not paused
			and not runner.pause_menu.is_open()
		),
		"Arena 16 opened an automatic modal instead of starting gameplay."
	)
	await _press_physical_key(KEY_H)
	var menu := runner.pause_menu
	var objective := str(runner.current_runtime.level_data["objective"])
	_expect(
		(
			menu.is_open()
			and paused
			and objective in menu.objective_label.text
			and menu.objective_label.visible_characters == -1
		),
		"Arena 16 help is unavailable or truncates its existing objective."
	)
	await _test_narrow_help(menu)
	await _wait_physics_frames(3)
	_expect_safe_resume(runner)


func _test_narrow_help(menu: CampaignPauseMenu) -> void:
	var previous_size := root.size
	var previous_scale := root.content_scale_size
	root.size = Vector2i(390, 844)
	await _wait_process_frames(4)
	var viewport_rect := root.get_visible_rect()
	_expect(viewport_rect.size == Vector2(390, 844), "Portrait help does not use window height.")
	_expect(viewport_rect.encloses(menu.panel.get_global_rect()), "Narrow help is clipped.")
	for button: Button in [menu.resume_button, menu.restart_button, menu.main_menu_button]:
		if not button.visible:
			continue
		_expect(
			menu.panel.get_global_rect().encloses(button.get_global_rect()),
			"Narrow pause action is clipped: %s." % button.name
		)
	for _page in 6:
		await _press_physical_key(KEY_PAGEDOWN)
	var scroll_bar := menu.help_scroll.get_v_scroll_bar()
	_expect(
		scroll_bar.value + scroll_bar.page >= scroll_bar.max_value - 1.0,
		"Keyboard could not reach the end of Arena 16 help on a narrow screen."
	)
	await _press_physical_key(KEY_ESCAPE)
	_expect(root.content_scale_size == previous_scale, "Closing help changed gameplay scale.")
	root.size = previous_size
	await _wait_process_frames(4)


func _expect_safe_resume(runner: CampaignRunner) -> void:
	var player := runner.current_runtime.get_level_object("player_start") as Player
	_expect(
		(
			not paused
			and not runner.pause_menu.is_open()
			and not player.jump_requested
			and not player.attack_requested
			and player.attack_time_remaining <= 0.0
			and player.velocity.y >= 0.0
		),
		"Closing help left a window, pause or accidental jump/attack."
	)


func _click_ui_button(button: Button) -> void:
	for is_pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		root.push_input(event, true)
		await process_frame


func _tap_ui_button(button: Button, index: int) -> void:
	for is_pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.window_id = root.get_window_id()
		event.position = root.get_screen_transform() * button.get_global_rect().get_center()
		event.index = index
		event.pressed = is_pressed
		Input.parse_input_event(event)
		await process_frame


func _expect_pause_open(
	runner: CampaignRunner,
	selector: Node,
	runtime_id: int
) -> void:
	_expect(
		runner.pause_menu.is_open()
		and paused
		and runner.phase == CampaignRunner.Phase.PAUSED
		and runner.current_runtime.get_instance_id() == runtime_id
		and runner.runtime_host.get_child_count() == 1
		and root.get_viewport().gui_get_focus_owner()
		== runner.pause_menu.resume_button,
		"Pause request did not open a focused menu over the runtime."
	)
	_expect(
		selector.context_suppressed
		and not selector.menu.visible
		and not selector.hint.visible,
		"Pause menu did not suppress the debug selector."
	)


func _expect_resumed(
	runner: CampaignRunner,
	selector: Node,
	runtime_id: int
) -> void:
	_expect(
		not runner.pause_menu.is_open()
		and not paused
		and runner.phase == CampaignRunner.Phase.PLAYING
		and runner.current_runtime.get_instance_id() == runtime_id,
		"Pause menu did not resume the same runtime."
	)
	_expect(
		not selector.context_suppressed
		and not selector.menu.visible
		and selector.hint.visible,
		"Debug selector did not return after resuming."
	)


func _wait_for_playing_runtime(
	runner: CampaignRunner
) -> LevelRuntimeArena:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(runner.current_runtime)
			and runner.phase == CampaignRunner.Phase.PLAYING
			and not runner.transitioning
		):
			return runner.current_runtime
	return null


func _wait_for_restarted_runtime(
	runner: CampaignRunner,
	old_runtime_id: int
) -> LevelRuntimeArena:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(runner.current_runtime)
			and runner.current_runtime.get_instance_id()
			!= old_runtime_id
			and not runner.transitioning
		):
			return runner.current_runtime
	return null


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


func _wait_process_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _wait_physics_frames(count: int) -> void:
	for _frame in count:
		await physics_frame


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


func _finish() -> void:
	paused = false
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited

	if progress_path_configured and is_instance_valid(progress_store):
		var clear_result := progress_store.clear_progress()
		if not bool(clear_result["ok"]):
			failures.append(
				"Could not clean isolated campaign progress."
			)
		progress_store.restore_default_storage_path()

	if failures.is_empty():
		print("PAUSE_MENU_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

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
		and runner.get_current_level_id() == "arena_01_data",
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

	var runtime_id := runtime.get_instance_id()
	runner.mobile_controls.set_touchscreen_override_for_tests(true, true)
	runner.mobile_controls.set_active(true)
	_expect(
		runner.mobile_controls.is_active(),
		"Forced mobile controls did not appear during gameplay."
	)
	await _tap_touchscreen_button(
		runner.mobile_controls.pause_button,
		0
	)
	await process_frame
	_expect_pause_open(runner, selector, runtime_id)
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
	await process_frame
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
	await process_frame
	_expect_resumed(runner, selector, runtime_id)

	var old_runtime_ref: WeakRef = weakref(runner.current_runtime)
	var old_runtime_id := runner.current_runtime.get_instance_id()
	var old_level_id := runner.get_current_level_id()
	var old_level_index := runner.get_current_level_index()
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
		and not selector.context_suppressed
		and selector.get_requested_campaign_level_id() == old_level_id,
		"Pause restart did not replace the current arena cleanly."
	)

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


func _tap_touchscreen_button(
	button: MobileTouchButton,
	index: int
) -> void:
	var controls := button.get_parent() as MobileControls
	var press := InputEventScreenTouch.new()
	press.window_id = root.get_window_id()
	press.index = index
	press.position = button.get_global_transform_with_canvas().origin
	press.pressed = true
	controls._input(press)
	await process_frame

	var release := InputEventScreenTouch.new()
	release.window_id = root.get_window_id()
	release.index = index
	release.position = button.get_global_transform_with_canvas().origin
	release.pressed = false
	controls._input(release)
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

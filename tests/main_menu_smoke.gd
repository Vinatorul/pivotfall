extends SceneTree

const MAIN_MENU_SCENE := preload(
	"res://scenes/main_menu.tscn"
)
const MAIN_MENU_PATH := "res://scenes/main_menu.tscn"
const CAMPAIGN_PATH := "res://scenes/campaign_runner.tscn"
const LEVEL_EDITOR_PATH := "res://scenes/level_editor.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selector := root.get_node_or_null("DebugLevelSelector")
	_expect(
		is_instance_valid(selector),
		"Debug selector autoload is unavailable."
	)
	if not is_instance_valid(selector):
		_finish()
		return

	selector.call(
		"remember_requested_campaign_level_id",
		"arena_08_data"
	)
	var menu := MAIN_MENU_SCENE.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame

	_expect(
		str(
			ProjectSettings.get_setting(
				"application/run/main_scene",
				""
			)
		) == MAIN_MENU_PATH,
		"Project main scene is not the main menu."
	)
	_expect_menu_ready(menu, selector)

	await _press_physical_key(KEY_S)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== menu.editor_button,
		"S did not move focus to the editor button."
	)
	await _press_physical_key(KEY_W)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== menu.new_game_button,
		"W did not move focus back to New Game."
	)

	menu.new_game_button.pressed.emit()
	var runner := await _wait_for_scene(CAMPAIGN_PATH)
	_expect(
		is_instance_valid(runner)
		and runner is CampaignRunner
		and runner.get_current_level_id() == "arena_01_data"
		and runner.runtime_host.get_child_count() == 1
		and not selector.context_suppressed
		and selector.get_requested_campaign_level_id()
		== "arena_01_data",
		"New Game did not clear debug selection and start Arena 01."
	)
	if not is_instance_valid(runner):
		_finish()
		return

	await _press_physical_key(KEY_F1)
	_expect(
		selector.menu.visible and paused,
		"F1 did not open and pause the debug selector in campaign."
	)
	await _press_physical_key(KEY_ESCAPE)
	_expect(
		current_scene == runner
		and not selector.menu.visible
		and not paused,
		"First Esc did not close only the F1 debug selector."
	)
	_expect(
		await _wait_for_campaign_playing(runner),
		"Campaign did not finish its intro before the pause check."
	)
	await _press_physical_key(KEY_ESCAPE)
	await process_frame
	_expect(
		current_scene == runner
		and runner.pause_menu.is_open()
		and paused,
		"Second Esc did not open the campaign pause menu."
	)
	runner.pause_menu.main_menu_button.pressed.emit()
	var returned_menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(returned_menu)
		and returned_menu.scene_file_path == MAIN_MENU_PATH,
		"Esc from campaign did not return to the main menu."
	)
	if not is_instance_valid(returned_menu):
		_finish()
		return
	_expect_menu_ready(returned_menu, selector)

	returned_menu.editor_button.pressed.emit()
	var editor := await _wait_for_scene(LEVEL_EDITOR_PATH)
	_expect(
		is_instance_valid(editor)
		and editor is LevelEditor
		and selector.context_suppressed
		and selector.get_editor_return_scene_path()
		== MAIN_MENU_PATH,
		"Editor opened from the menu did not remember its return scene."
	)
	if not is_instance_valid(editor):
		_finish()
		return

	(editor as LevelEditor).draft.mark_saved()
	(editor as LevelEditor).exit_button.pressed.emit()
	var final_menu := await _wait_for_scene(MAIN_MENU_PATH)
	_expect(
		is_instance_valid(final_menu)
		and final_menu.scene_file_path == MAIN_MENU_PATH,
		"Editor did not return to the main menu."
	)
	if is_instance_valid(final_menu):
		_expect_menu_ready(final_menu, selector)

	_finish()


func _expect_menu_ready(menu: Node, selector: Node) -> void:
	_expect(
		menu.new_game_button.text == "НОВАЯ ИГРА"
		and menu.editor_button.text == "РЕДАКТОР УРОВНЕЙ"
		and menu.exit_button.text == "ВЫХОД"
		and menu.exit_button.visible != OS.has_feature("web")
		and not menu.transitioning
		and not paused,
		"Main menu buttons or state are incomplete."
	)
	_expect(
		root.get_viewport().gui_get_focus_owner()
		== menu.new_game_button,
		"Main menu did not focus New Game."
	)
	_expect(
		selector.context_suppressed
		and not selector.menu.visible
		and not selector.hint.visible,
		"Main menu did not suppress the debug selector."
	)


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


func _wait_for_campaign_playing(runner: CampaignRunner) -> bool:
	for _frame in 180:
		await process_frame
		await physics_frame
		if (
			is_instance_valid(runner)
			and runner.phase == CampaignRunner.Phase.PLAYING
			and not runner.transitioning
		):
			return true
	return false


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


func _finish() -> void:
	var scene := current_scene
	current_scene = null
	if is_instance_valid(scene):
		scene.queue_free()
		await scene.tree_exited

	if failures.is_empty():
		print("MAIN_MENU_SMOKE_OK")
		quit(0)
		return

	for failure: String in failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

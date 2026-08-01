class_name LevelFileTransfer
extends Node

signal import_selected(file_name: String, bytes: PackedByteArray)
signal import_requested
signal transfer_failed(message: String)
signal export_completed(file_name: String)

const JSON_MIME_TYPE := "application/json"
const JSON_FILTER := "*.json ; Pivotfall level"

var max_import_bytes := 262_144

var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _pending_export_name := ""
var _pending_export_bytes := PackedByteArray()

var _web_file_input = null
var _web_file_chosen_callback = null
var _web_file_cancelled_callback = null
var _web_file_read_callback = null
var _web_file_error_callback = null
var _web_pending_file_name := ""
var _web_canvas = null
var _web_window = null
var _web_file_clicked_callback = null
var _web_resize_callback = null
var _web_import_hit_rect := Rect2()
var _web_base_view_size := Vector2(960.0, 540.0)
var _web_import_overlay_visible := true

var _test_export_handler := Callable()
var _test_import_handler := Callable()


func _ready() -> void:
	_create_desktop_dialogs()


func _exit_tree() -> void:
	if not OS.has_feature("web"):
		return
	if _web_window != null and _web_resize_callback != null:
		_web_window.removeEventListener(
			"resize",
			_web_resize_callback
		)
	if _web_file_input != null:
		_restore_web_canvas_focus()
		_web_file_input.onclick = null
		_web_file_input.onchange = null
		_web_file_input.oncancel = null
		_web_file_input.remove()
	_web_pending_file_name = ""
	_web_file_input = null
	_web_file_chosen_callback = null
	_web_file_cancelled_callback = null
	_web_file_read_callback = null
	_web_file_error_callback = null
	_web_file_clicked_callback = null
	_web_resize_callback = null
	_web_canvas = null
	_web_window = null


func request_import() -> void:
	if _test_import_handler.is_valid():
		_handle_test_import_result(_test_import_handler.call())
		return
	if OS.has_feature("web"):
		_request_web_import()
		return
	_import_dialog.popup_file_dialog()


func export_file(
	file_name: String,
	bytes: PackedByteArray,
	mime_type := JSON_MIME_TYPE
) -> void:
	if file_name.is_empty() or bytes.is_empty():
		transfer_failed.emit("Нет данных для экспорта.")
		return
	if _test_export_handler.is_valid():
		_handle_test_export_result(
			file_name,
			_test_export_handler.call(file_name, bytes, mime_type)
		)
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, file_name, mime_type)
		export_completed.emit(file_name)
		return

	_pending_export_name = file_name
	_pending_export_bytes = bytes.duplicate()
	_export_dialog.current_file = file_name
	_export_dialog.popup_file_dialog()


func configure_web_import_hit_rect(
	hit_rect: Rect2,
	base_view_size: Vector2
) -> void:
	if not OS.has_feature("web"):
		return
	_web_import_hit_rect = hit_rect
	_web_base_view_size = base_view_size
	_ensure_web_file_input()
	var document = JavaScriptBridge.get_interface("document")
	if document == null:
		return
	if _web_canvas == null:
		_web_canvas = document.querySelector("canvas")
	if _web_file_input != null and _web_file_clicked_callback == null:
		_web_file_clicked_callback = JavaScriptBridge.create_callback(
			_on_web_file_clicked
		)
		_web_file_input.onclick = _web_file_clicked_callback
	if _web_window == null:
		_web_window = JavaScriptBridge.get_interface("window")
	if _web_window != null and _web_resize_callback == null:
		_web_resize_callback = JavaScriptBridge.create_callback(
			_on_web_window_resized
		)
		_web_window.addEventListener("resize", _web_resize_callback)
	_update_web_import_overlay()


func set_web_import_overlay_visible(visible: bool) -> void:
	_web_import_overlay_visible = visible
	if OS.has_feature("web"):
		_update_web_import_overlay()


func configure_for_tests(
	export_handler: Callable,
	import_handler: Callable
) -> bool:
	if not OS.is_debug_build():
		return false
	_test_export_handler = export_handler
	_test_import_handler = import_handler
	return true


func clear_test_configuration() -> void:
	if not OS.is_debug_build():
		return
	_test_export_handler = Callable()
	_test_import_handler = Callable()


func _create_desktop_dialogs() -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.name = &"ImportDialog"
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.use_native_dialog = true
	_import_dialog.mode_overrides_title = false
	_import_dialog.title = "Импортировать уровень"
	_import_dialog.filters = PackedStringArray([JSON_FILTER])
	_import_dialog.file_selected.connect(_on_desktop_import_selected)
	add_child(_import_dialog)

	_export_dialog = FileDialog.new()
	_export_dialog.name = &"ExportDialog"
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.use_native_dialog = true
	_export_dialog.mode_overrides_title = false
	_export_dialog.title = "Экспортировать уровень"
	_export_dialog.filters = PackedStringArray([JSON_FILTER])
	_export_dialog.file_selected.connect(_on_desktop_export_selected)
	_export_dialog.canceled.connect(_clear_pending_export)
	add_child(_export_dialog)


func _on_desktop_import_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not is_instance_valid(file):
		transfer_failed.emit(
			"Не удалось открыть файл (ошибка %d)."
			% FileAccess.get_open_error()
		)
		return
	var length := file.get_length()
	if length > max_import_bytes:
		file.close()
		transfer_failed.emit(_file_too_large_message())
		return
	var bytes := file.get_buffer(length)
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		transfer_failed.emit(
			"Не удалось прочитать файл (ошибка %d)."
			% read_error
		)
		return
	if bytes.size() != length:
		transfer_failed.emit(
			"Не удалось прочитать файл полностью."
		)
		return
	import_selected.emit(path.get_file(), bytes)


func _on_desktop_export_selected(path: String) -> void:
	if _pending_export_bytes.is_empty():
		transfer_failed.emit(
			"Данные экспорта уже недоступны."
		)
		_clear_pending_export()
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not is_instance_valid(file):
		transfer_failed.emit(
			"Не удалось записать файл (ошибка %d)."
			% FileAccess.get_open_error()
		)
		_clear_pending_export()
		return
	file.store_buffer(_pending_export_bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		transfer_failed.emit(
			"Не удалось записать файл (ошибка %d)."
			% write_error
		)
		_clear_pending_export()
		return
	var exported_name := (
		path.get_file()
		if not path.get_file().is_empty()
		else _pending_export_name
	)
	_clear_pending_export()
	export_completed.emit(exported_name)


func _clear_pending_export() -> void:
	_pending_export_name = ""
	_pending_export_bytes = PackedByteArray()


func _request_web_import() -> void:
	_ensure_web_file_input()
	if _web_file_input == null:
		transfer_failed.emit(
			"Браузерный выбор файла недоступен."
		)
		return
	_web_file_input.value = ""
	_web_file_input.click()


func _on_web_file_clicked(_arguments: Array) -> void:
	if not is_inside_tree() or _web_file_input == null:
		return
	_web_file_input.value = ""
	import_requested.emit()


func _on_web_window_resized(_arguments: Array) -> void:
	if not is_inside_tree():
		return
	_update_web_import_overlay()


func _update_web_import_overlay() -> void:
	if (
		_web_canvas == null
		or _web_file_input == null
		or _web_import_hit_rect.size.x <= 0.0
		or _web_import_hit_rect.size.y <= 0.0
	):
		return
	if not _web_import_overlay_visible:
		_web_file_input.style.display = "none"
		return
	var canvas_rect = _web_canvas.getBoundingClientRect()
	var canvas_size := Vector2(
		float(canvas_rect.width),
		float(canvas_rect.height)
	)
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return
	var content_scale := minf(
		canvas_size.x / _web_base_view_size.x,
		canvas_size.y / _web_base_view_size.y
	)
	var content_size := _web_base_view_size * content_scale
	var content_origin := Vector2(
		float(canvas_rect.left),
		float(canvas_rect.top)
	) + (canvas_size - content_size) * 0.5
	var overlay_position := (
		content_origin + _web_import_hit_rect.position * content_scale
	)
	var overlay_size := _web_import_hit_rect.size * content_scale
	_web_file_input.style.display = "block"
	_web_file_input.style.position = "fixed"
	_web_file_input.style.left = "%fpx" % overlay_position.x
	_web_file_input.style.top = "%fpx" % overlay_position.y
	_web_file_input.style.width = "%fpx" % overlay_size.x
	_web_file_input.style.height = "%fpx" % overlay_size.y
	_web_file_input.style.opacity = "0"
	_web_file_input.style.zIndex = "1000"
	_web_file_input.style.cursor = "pointer"


func _ensure_web_file_input() -> void:
	if _web_file_input != null:
		return

	_web_file_chosen_callback = JavaScriptBridge.create_callback(
		_on_web_file_chosen
	)
	_web_file_cancelled_callback = JavaScriptBridge.create_callback(
		_on_web_file_cancelled
	)
	_web_file_read_callback = JavaScriptBridge.create_callback(
		_on_web_file_read
	)
	_web_file_error_callback = JavaScriptBridge.create_callback(
		_on_web_file_read_failed
	)

	var document = JavaScriptBridge.get_interface("document")
	if document == null:
		return
	_web_file_input = document.createElement("input")
	_web_file_input.type = "file"
	_web_file_input.accept = ".json,application/json"
	_web_file_input.multiple = false
	_web_file_input.tabIndex = -1
	_web_file_input.setAttribute(
		"aria-label",
		"Import Pivotfall level"
	)
	_web_file_input.onchange = _web_file_chosen_callback
	_web_file_input.oncancel = _web_file_cancelled_callback
	_web_file_input.style.display = "none"
	document.body.appendChild(_web_file_input)


func _on_web_file_chosen(arguments: Array) -> void:
	if not is_inside_tree():
		return
	if arguments.is_empty():
		_restore_web_canvas_focus()
		return
	var event = arguments[0]
	if event == null or int(event.target.files.length) == 0:
		_restore_web_canvas_focus()
		return

	var file = event.target.files[0]
	set_web_import_overlay_visible(false)
	_restore_web_canvas_focus()
	if int(file.size) > max_import_bytes:
		_web_pending_file_name = ""
		transfer_failed.emit(_file_too_large_message())
		return
	_web_pending_file_name = str(file.name)
	file.arrayBuffer().then(
		_web_file_read_callback,
		_web_file_error_callback
	)


func _on_web_file_read(arguments: Array) -> void:
	if not is_inside_tree():
		return
	_restore_web_canvas_focus()
	if (
		arguments.is_empty()
		or not JavaScriptBridge.is_js_buffer(arguments[0])
	):
		_web_pending_file_name = ""
		transfer_failed.emit(
			"Браузер вернул некорректный файл."
		)
		return
	var bytes := JavaScriptBridge.js_buffer_to_packed_byte_array(
		arguments[0]
	)
	if bytes.size() > max_import_bytes:
		_web_pending_file_name = ""
		transfer_failed.emit(_file_too_large_message())
		return
	var file_name := _web_pending_file_name
	_web_pending_file_name = ""
	import_selected.emit(file_name, bytes)


func _on_web_file_read_failed(_arguments: Array) -> void:
	if not is_inside_tree():
		return
	_restore_web_canvas_focus()
	_web_pending_file_name = ""
	transfer_failed.emit(
		"Не удалось прочитать выбранный файл."
	)


func _on_web_file_cancelled(_arguments: Array) -> void:
	if not is_inside_tree():
		return
	_web_pending_file_name = ""
	_restore_web_canvas_focus()


func _restore_web_canvas_focus() -> void:
	if _web_file_input != null:
		_web_file_input.blur()
	if _web_canvas != null:
		_web_canvas.focus()


func _handle_test_export_result(
	file_name: String,
	result: Variant
) -> void:
	if result is Dictionary:
		var result_dictionary := result as Dictionary
		if not bool(result_dictionary.get("ok", false)):
			transfer_failed.emit(
				str(
					result_dictionary.get(
						"error",
						"Тестовый экспорт завершился ошибкой."
					)
				)
			)
			return
	elif result is bool and not bool(result):
		transfer_failed.emit(
			"Тестовый экспорт завершился ошибкой."
		)
		return
	export_completed.emit(file_name)


func _handle_test_import_result(result: Variant) -> void:
	if not result is Dictionary:
		transfer_failed.emit(
			(
				"Тестовый импорт вернул "
				+ "некорректный ответ."
			)
		)
		return
	var result_dictionary := result as Dictionary
	if bool(result_dictionary.get("cancelled", false)):
		return
	if not bool(result_dictionary.get("ok", false)):
		transfer_failed.emit(
			str(
				result_dictionary.get(
					"error",
					"Тестовый импорт завершился ошибкой."
				)
			)
		)
		return
	var bytes: Variant = result_dictionary.get(
		"bytes",
		PackedByteArray()
	)
	if not bytes is PackedByteArray:
		transfer_failed.emit(
			"Тестовый импорт не вернул байты файла."
		)
		return
	import_selected.emit(
		str(result_dictionary.get("file_name", "level.json")),
		bytes as PackedByteArray
	)


func _file_too_large_message() -> String:
	return "Файл уровня превышает лимит %d КБ." % int(
		max_import_bytes / 1024
	)

extends SceneTree

const LEVEL_STORAGE := preload(
	"res://scripts/levels/level_storage.gd"
)
const LEVEL_DATA_CODEC := preload(
	"res://scripts/levels/level_data_codec.gd"
)
const RUNTIME_SCENE := preload(
	"res://scenes/level_runtime_arena.tscn"
)

const EXPECTED_LEVELS: Array[Dictionary] = [
	{
		"id": "jailbreak",
		"path": "res://levels/jailbreak.json",
		"catalog_title": "Arena 09 / Побег",
		"title": "JAILBREAK",
		"objective": "СТОЛКНИ ВРАГА В ЯМУ",
		"enemy_count": 1,
		"object_ids": [
			"bridge",
			"floor",
			"floor_2",
			"hinge",
			"left_floor",
			"player_start",
			"right_floor",
			"shooter_7",
		],
		"type_counts": {
			"hinge": 1,
			"player_spawn": 1,
			"shooter_enemy": 1,
			"solid_rect": 4,
			"toggle_platform": 1,
		},
		"links": [["hinge", "bridge"]],
	},
	{
		"id": "sniper_party",
		"path": "res://levels/sniper_party.json",
		"catalog_title": "Arena 10 / Снайперы",
		"title": "SNIPER PARTY",
		"objective": "СТОЛКНИ ВРАГОВ В ЯМУ",
		"enemy_count": 2,
		"object_ids": [
			"bridge",
			"bridge_2",
			"floor",
			"floor_2",
			"hinge",
			"hinge_2",
			"left_floor",
			"lift",
			"player_start",
			"right_floor",
			"shooter",
			"shooter_2",
		],
		"type_counts": {
			"hinge": 2,
			"player_spawn": 1,
			"shooter_enemy": 2,
			"solid_rect": 4,
			"toggle_platform": 2,
			"vertical_platform": 1,
		},
		"links": [
			["hinge", "lift"],
			["hinge_2", "lift"],
		],
	},
	{
		"id": "tower_assault",
		"path": "res://levels/tower_assault.json",
		"catalog_title": "Arena 11 / Штурм",
		"title": "TOWER ASSAULT",
		"objective": "СТОЛКНИ ВРАГОВ В ЯМУ",
		"enemy_count": 5,
		"object_ids": [
			"bridge_2",
			"hinge",
			"left_floor",
			"lift",
			"lift_2",
			"patrol",
			"patrol_13",
			"player_start",
			"right_floor",
			"shooter",
			"shove",
			"shove_2",
		],
		"type_counts": {
			"hinge": 1,
			"patrol_enemy": 2,
			"player_spawn": 1,
			"shooter_enemy": 1,
			"shove_enemy": 2,
			"solid_rect": 2,
			"toggle_platform": 1,
			"vertical_platform": 2,
		},
		"links": [["hinge", "lift_2"]],
	},
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := LEVEL_STORAGE.list_builtin_levels()
	_expect(
		catalog.size() >= EXPECTED_LEVELS.size(),
		"Built-in catalog is shorter than the community level set."
	)
	if catalog.size() < EXPECTED_LEVELS.size():
		_finish()
		return
	var selector := root.get_node_or_null("DebugLevelSelector")
	if is_instance_valid(selector):
		selector.call("_render_menu")
	var selector_list := (
		selector.get_node_or_null("Menu/Panel/ArenaList") as RichTextLabel
		if is_instance_valid(selector)
		else null
	)
	var selector_entries: Array = (
		selector.get("campaign_entries") as Array
		if is_instance_valid(selector)
		else []
	)
	_expect(
		is_instance_valid(selector)
		and selector_entries.size() == catalog.size()
		and is_instance_valid(selector_list)
		and "[12]" in selector_list.text
		and "Arena 12 / Ворота" in selector_list.text,
		(
			"Debug selector did not expose all twelve built-in arenas: "
			+ "selector=%s entries=%d text=%s"
			% [
				is_instance_valid(selector),
				selector_entries.size(),
				selector_list.text if is_instance_valid(selector_list) else "",
			]
		)
	)

	var catalog_by_id := {}
	for catalog_entry: Dictionary in catalog:
		catalog_by_id[str(catalog_entry.get("id", ""))] = catalog_entry
	for index in EXPECTED_LEVELS.size():
		var expected: Dictionary = EXPECTED_LEVELS[index]
		var catalog_entry: Dictionary = catalog_by_id.get(
			str(expected["id"]),
			{}
		)
		_expect(
			catalog_entry.get("id") == expected["id"]
			and catalog_entry.get("path") == expected["path"]
			and catalog_entry.get("title")
			== expected["catalog_title"],
			"Community catalog entry %d drifted." % index
		)
		await _test_level(expected)

	_finish()


func _test_level(expected: Dictionary) -> void:
	var level_id := str(expected["id"])
	var loaded: Dictionary = LEVEL_STORAGE.load_builtin_level(level_id)
	_expect(
		bool(loaded.get("ok", false)),
		"Could not load community level '%s': %s"
		% [level_id, loaded.get("errors", [])]
	)
	if not bool(loaded.get("ok", false)):
		return

	var data: Dictionary = loaded["data"]
	var object_ids: Array[String] = []
	var type_counts := {}
	for object: Dictionary in data.get("objects", []):
		object_ids.append(str(object.get("id", "")))
		var object_type := str(object.get("type", ""))
		type_counts[object_type] = int(type_counts.get(object_type, 0)) + 1
	object_ids.sort()
	var expected_ids: Array = expected["object_ids"].duplicate()
	expected_ids.sort()

	_expect(
		data.get("level_id") == level_id
		and data.get("title") == expected["title"]
		and data.get("objective") == expected["objective"]
		and object_ids == expected_ids
		and type_counts == expected["type_counts"],
		"Community level '%s' metadata or composition drifted."
		% level_id
	)

	var encoded: Dictionary = LEVEL_DATA_CODEC.encode(data)
	_expect(
		bool(encoded.get("ok", false)),
		"Community level '%s' could not be encoded." % level_id
	)
	if not bool(encoded.get("ok", false)):
		return

	var runtime := RUNTIME_SCENE.instantiate() as LevelRuntimeArena
	runtime.configure_embedded_snapshot(str(encoded["text"]))
	root.add_child(runtime)
	_expect(
		runtime.level_loaded
		and runtime.load_errors.is_empty()
		and runtime.level_objects.size() == object_ids.size()
		and runtime.enemies_remaining == int(expected["enemy_count"])
		and is_instance_valid(
			runtime.get_level_object("player_start")
		),
		"Community level '%s' did not build a complete runtime."
		% level_id
	)

	for raw_link: Variant in expected["links"]:
		var link := raw_link as Array
		var hinge := runtime.get_level_object(str(link[0])) as Hinge
		var target := runtime.get_level_object(str(link[1]))
		_expect(
			is_instance_valid(hinge)
			and is_instance_valid(target)
			and hinge.target == target,
			"Community level '%s' lost link '%s' -> '%s'."
			% [level_id, link[0], link[1]]
		)

	runtime.queue_free()
	await runtime.tree_exited


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("COMMUNITY_LEVELS_SMOKE_OK")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)

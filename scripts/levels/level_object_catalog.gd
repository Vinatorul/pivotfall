class_name LevelObjectCatalog
extends RefCounted

const TYPE_SOLID_RECT: String = "solid_rect"
const TYPE_SPIKE_TRAP: String = "spike_trap"
const TYPE_PLAYER_SPAWN: String = "player_spawn"
const TYPE_PATROL_ENEMY: String = "patrol_enemy"
const TYPE_SHOVE_ENEMY: String = "shove_enemy"
const TYPE_SHOOTER_ENEMY: String = "shooter_enemy"
const TYPE_CATAPULT_PLATFORM: String = "catapult_platform"
const TYPE_VERTICAL_PLATFORM: String = "vertical_platform"
const TYPE_DOUBLE_JUMP_PICKUP: String = "double_jump_pickup"
const TYPE_TOGGLE_PLATFORM: String = "toggle_platform"
const TYPE_TOGGLE_WALL: String = "toggle_wall"
const TYPE_HINGE: String = "hinge"

enum Category {
	RECT,
	POINT,
	ACTOR,
	ENEMY,
	SUPPORT,
	HINGE_TARGET,
	PROJECTILE_BLOCKER,
}

const _SUPPORTED_TYPES: Array[String] = [
	TYPE_SOLID_RECT,
	TYPE_SPIKE_TRAP,
	TYPE_PLAYER_SPAWN,
	TYPE_PATROL_ENEMY,
	TYPE_SHOVE_ENEMY,
	TYPE_SHOOTER_ENEMY,
	TYPE_CATAPULT_PLATFORM,
	TYPE_VERTICAL_PLATFORM,
	TYPE_DOUBLE_JUMP_PICKUP,
	TYPE_TOGGLE_PLATFORM,
	TYPE_TOGGLE_WALL,
	TYPE_HINGE,
]
const _RECT_TYPES: Array[String] = [
	TYPE_SOLID_RECT,
	TYPE_SPIKE_TRAP,
	TYPE_TOGGLE_PLATFORM,
	TYPE_TOGGLE_WALL,
]
const _POINT_TYPES: Array[String] = [
	TYPE_PLAYER_SPAWN,
	TYPE_DOUBLE_JUMP_PICKUP,
	TYPE_PATROL_ENEMY,
	TYPE_SHOVE_ENEMY,
	TYPE_SHOOTER_ENEMY,
	TYPE_CATAPULT_PLATFORM,
	TYPE_VERTICAL_PLATFORM,
	TYPE_HINGE,
]
const _ENEMY_TYPES: Array[String] = [
	TYPE_PATROL_ENEMY,
	TYPE_SHOVE_ENEMY,
	TYPE_SHOOTER_ENEMY,
]
const _SUPPORT_TYPES: Array[String] = [
	TYPE_SOLID_RECT,
	TYPE_TOGGLE_PLATFORM,
	TYPE_TOGGLE_WALL,
	TYPE_CATAPULT_PLATFORM,
	TYPE_VERTICAL_PLATFORM,
]
const _HINGE_TARGET_TYPES: Array[String] = [
	TYPE_TOGGLE_PLATFORM,
	TYPE_TOGGLE_WALL,
	TYPE_CATAPULT_PLATFORM,
	TYPE_VERTICAL_PLATFORM,
]
const _ACTOR_HALF_EXTENTS: Dictionary[String, Vector2i] = {
	TYPE_PLAYER_SPAWN: Vector2i(14, 20),
	TYPE_PATROL_ENEMY: Vector2i(15, 18),
	TYPE_SHOVE_ENEMY: Vector2i(16, 19),
	TYPE_SHOOTER_ENEMY: Vector2i(17, 19),
}


static func supported_types() -> Array[String]:
	return _copy_types(_SUPPORTED_TYPES)


static func is_supported_type(type_id: String) -> bool:
	return _SUPPORTED_TYPES.has(type_id)


static func category_types(category: Category) -> Array[String]:
	match category:
		Category.RECT:
			return _copy_types(_RECT_TYPES)
		Category.POINT:
			return _copy_types(_POINT_TYPES)
		Category.ACTOR:
			return _actor_types()
		Category.ENEMY:
			return _copy_types(_ENEMY_TYPES)
		Category.SUPPORT, Category.PROJECTILE_BLOCKER:
			return _copy_types(_SUPPORT_TYPES)
		Category.HINGE_TARGET:
			return _copy_types(_HINGE_TARGET_TYPES)
	return [] as Array[String]


static func is_in_category(type_id: String, category: Category) -> bool:
	match category:
		Category.RECT:
			return _RECT_TYPES.has(type_id)
		Category.POINT:
			return _POINT_TYPES.has(type_id)
		Category.ACTOR:
			return _ACTOR_HALF_EXTENTS.has(type_id)
		Category.ENEMY:
			return _ENEMY_TYPES.has(type_id)
		Category.SUPPORT, Category.PROJECTILE_BLOCKER:
			return _SUPPORT_TYPES.has(type_id)
		Category.HINGE_TARGET:
			return _HINGE_TARGET_TYPES.has(type_id)
	return false


static func has_actor_half_extents(type_id: String) -> bool:
	return _ACTOR_HALF_EXTENTS.has(type_id)


static func actor_half_extents(type_id: String) -> Vector2i:
	return _ACTOR_HALF_EXTENTS.get(type_id, Vector2i.ZERO)


static func _actor_types() -> Array[String]:
	var result: Array[String] = []
	for type_id: String in _ACTOR_HALF_EXTENTS:
		result.append(type_id)
	return result


static func _copy_types(source: Array[String]) -> Array[String]:
	var result: Array[String] = []
	result.assign(source)
	return result

class_name LevelBehaviorPresets
extends RefCounted

## Closed gameplay presets shared by validation, runtime construction and
## editor previews. Level JSON selects a stable name; individual balance
## values remain trusted project data rather than user-controlled fields.

const STANDARD_PRESET := "standard"
const EXAM_PRESET := "exam"

const _PRESET_NAMES := [
	STANDARD_PRESET,
	EXAM_PRESET,
]
const _SUPPORTED_OBJECT_TYPES := [
	"shove_enemy",
	"shooter_enemy",
	"catapult_platform",
]

const _VALUES := {
	"shove_enemy": {
		STANDARD_PRESET: {
			"patrol_speed": 55.0,
			"detection_range": 180.0,
			"vertical_detection_tolerance": 48.0,
			"telegraph_time": 0.5,
			"lunge_speed": 420.0,
			"lunge_time": 0.28,
			"recovery_time": 0.55,
			"shove_horizontal_impulse": 520.0,
			"shove_vertical_impulse": -140.0,
		},
		EXAM_PRESET: {
			"patrol_speed": 0.0,
			"detection_range": 90.0,
			"vertical_detection_tolerance": 48.0,
			"telegraph_time": 1.4,
			"lunge_speed": 420.0,
			"lunge_time": 0.28,
			"recovery_time": 0.55,
			"shove_horizontal_impulse": 520.0,
			"shove_vertical_impulse": -140.0,
		},
	},
	"shooter_enemy": {
		STANDARD_PRESET: {
			"line_length": 900.0,
			"aim_time": 0.7,
			"aim_lock_time": 0.23,
			"cooldown_time": 1.3,
			"muzzle_flash_time": 0.1,
		},
		EXAM_PRESET: {
			"line_length": 900.0,
			"aim_time": 1.0,
			"aim_lock_time": 0.26,
			"cooldown_time": 1.5,
			"muzzle_flash_time": 0.1,
		},
	},
	"catapult_platform": {
		STANDARD_PRESET: {
			"warning_time": 0.3,
			"swing_out_time": 0.18,
			"swing_hold_time": 0.08,
			"return_time": 0.28,
			"clearance_time": 0.1,
			"clearance_attempts": 2,
			"swing_angle_degrees": 55.0,
			"launch_direction": 1.0,
			"launch_impulse": Vector2(700.0, -280.0),
			"clearance_impulse": Vector2(420.0, -360.0),
		},
		EXAM_PRESET: {
			"warning_time": 0.3,
			"swing_out_time": 0.18,
			"swing_hold_time": 0.08,
			"return_time": 0.28,
			"clearance_time": 0.1,
			"clearance_attempts": 2,
			"swing_angle_degrees": 55.0,
			"launch_direction": 1.0,
			"launch_impulse": Vector2(180.0, -80.0),
			"clearance_impulse": Vector2(420.0, -360.0),
		},
	},
}


static func is_supported_object_type(object_type: String) -> bool:
	return _SUPPORTED_OBJECT_TYPES.has(object_type)


static func is_valid_preset(preset: String) -> bool:
	return _PRESET_NAMES.has(preset)


static func preset_names() -> Array[String]:
	var names: Array[String] = []
	for preset: String in _PRESET_NAMES:
		names.append(preset)
	return names


static func values_for(
	object_type: String,
	preset: String
) -> Dictionary:
	if (
		not is_supported_object_type(object_type)
		or not is_valid_preset(preset)
	):
		return {}

	var values: Dictionary = _VALUES[object_type][preset]
	return values.duplicate(true)


static func shove_detection_half_size(preset: String) -> Vector2:
	var values := values_for("shove_enemy", preset)
	if values.is_empty():
		return Vector2.ZERO
	return Vector2(
		float(values["detection_range"]),
		float(values["vertical_detection_tolerance"])
	)


static func catapult_launch_impulse(preset: String) -> Vector2:
	var values := values_for("catapult_platform", preset)
	if values.is_empty():
		return Vector2.ZERO
	return Vector2(values["launch_impulse"])

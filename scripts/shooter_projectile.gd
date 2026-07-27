class_name ShooterProjectile
extends Node2D

signal impacted(collider: CollisionObject2D)

@export var speed := 760.0
@export var maximum_distance := 1000.0
@export var horizontal_impulse := 520.0
@export var vertical_impulse := -140.0
@export_range(0.0, 16.0, 0.5) var collision_radius := 5.0
@export_flags_2d_physics var collision_mask := 15

var direction := Vector2.LEFT
var distance_travelled := 0.0
var collision_exceptions: Array[RID] = []


func _ready() -> void:
	set_physics_process(false)


func launch(
	origin: Vector2,
	launch_direction: Vector2,
	source: CollisionObject2D
) -> void:
	global_position = origin
	direction = launch_direction.normalized()
	rotation = direction.angle()
	collision_exceptions.append(source.get_rid())
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var remaining_distance := maximum_distance - distance_travelled
	if remaining_distance <= 0.0:
		queue_free()
		return

	var step_distance := minf(speed * delta, remaining_distance)
	var segment_end := global_position + direction * step_distance
	var space_state := get_world_2d().direct_space_state

	for _collision_index in range(8):
		var result := _find_first_collision(
			space_state,
			global_position,
			segment_end
		)
		if result.is_empty():
			distance_travelled += global_position.distance_to(segment_end)
			global_position = segment_end
			return

		var hit_distance: float = result["travel_distance"]
		distance_travelled += hit_distance
		global_position += direction * hit_distance

		var collider := result["collider"] as CollisionObject2D
		if not is_instance_valid(collider):
			queue_free()
			return

		if collider is Area2D:
			_apply_impulse(collider)
			collision_exceptions.append(collider.get_rid())

			var nudge := minf(0.5, global_position.distance_to(segment_end))
			global_position += direction * nudge
			distance_travelled += nudge
			continue

		_apply_impulse(collider)
		impacted.emit(collider)
		queue_free()
		return

	queue_free()


func _find_first_collision(
	space_state: PhysicsDirectSpaceState2D,
	segment_start: Vector2,
	segment_end: Vector2
) -> Dictionary:
	var closest_result: Dictionary = {}
	var closest_distance := INF
	var lateral_direction := direction.orthogonal()
	var segment_length := segment_start.distance_to(segment_end)
	var lateral_offsets: Array[float] = [
		-collision_radius,
		0.0,
		collision_radius,
	]

	for lateral_offset in lateral_offsets:
		var ray_offset: Vector2 = lateral_direction * lateral_offset
		var query := PhysicsRayQueryParameters2D.create(
			segment_start + ray_offset,
			segment_end + ray_offset,
			collision_mask,
			collision_exceptions
		)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.hit_from_inside = true

		var result := space_state.intersect_ray(query)
		if result.is_empty():
			continue

		var hit_position: Vector2 = result["position"]
		var travel_distance := clampf(
			(hit_position - segment_start - ray_offset).dot(direction),
			0.0,
			segment_length
		)
		if travel_distance >= closest_distance:
			continue

		closest_distance = travel_distance
		closest_result = result
		closest_result["travel_distance"] = travel_distance

	return closest_result


func _apply_impulse(target: CollisionObject2D) -> void:
	if not target.has_method("receive_impulse"):
		return

	target.call(
		"receive_impulse",
		direction * horizontal_impulse + Vector2(0.0, vertical_impulse)
	)

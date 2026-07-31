class_name ShoveEnemy
extends PatrolEnemy

enum State {
	PATROL,
	TELEGRAPH,
	LUNGE,
	RECOVERY,
	KNOCKBACK,
}

@export_category("Shove attack")
@export var detection_range := 180.0
@export var vertical_detection_tolerance := 48.0
@export var telegraph_time := 0.5
@export var lunge_speed := 420.0
@export var lunge_time := 0.28
@export var recovery_time := 0.55
@export var shove_horizontal_impulse := 520.0
@export var shove_vertical_impulse := -140.0

@onready var attack_pivot: Node2D = $AttackPivot
@onready var attack_area: Area2D = $AttackPivot/AttackArea
@onready var attack_visual: Polygon2D = $AttackPivot/AttackVisual
@onready var telegraph_visual: Polygon2D = $Telegraph

var state := State.PATROL
var state_time_remaining := 0.0
var lunge_direction := -1.0
var player: Player
var struck_targets: Dictionary[int, bool] = {}


func _ready() -> void:
	super()
	player = _find_player_sibling()
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.area_entered.connect(_on_attack_area_area_entered)
	_enter_patrol()


func _physics_process(delta: float) -> void:
	if _consume_impact_freeze_frame():
		return

	_update_hit_flash(delta)

	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, maximum_fall_speed)

	if knockback_time_remaining > 0.0:
		_process_knockback(delta)
	else:
		if state == State.KNOCKBACK:
			_enter_patrol()

		match state:
			State.PATROL:
				_process_patrol()
			State.TELEGRAPH:
				_process_telegraph(delta)
			State.LUNGE:
				_process_lunge(delta)
			State.RECOVERY:
				_process_recovery(delta)

	move_and_slide()

	if is_on_wall():
		if state == State.LUNGE:
			_begin_recovery()
		elif state == State.PATROL:
			_turn_around()


func receive_impulse(impulse: Vector2) -> void:
	super(impulse)
	_cancel_attack()
	state = State.KNOCKBACK


func _process_knockback(delta: float) -> void:
	knockback_time_remaining = maxf(knockback_time_remaining - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)


func _process_patrol() -> void:
	if _can_attack_player():
		_begin_telegraph()
		return

	if is_on_floor() and not edge_probe.is_colliding():
		_turn_around()

	velocity.x = patrol_direction * patrol_speed


func _process_telegraph(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_begin_lunge()


func _process_lunge(delta: float) -> void:
	velocity.x = lunge_direction * lunge_speed
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_begin_recovery()


func _process_recovery(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, knockback_drag * delta)
	state_time_remaining = maxf(state_time_remaining - delta, 0.0)

	if is_zero_approx(state_time_remaining):
		_enter_patrol()


func _can_attack_player() -> bool:
	if not is_instance_valid(player):
		player = _find_player_sibling()
	if not is_instance_valid(player) or not is_on_floor():
		return false

	var offset := player.global_position - global_position
	return (
		absf(offset.x) <= detection_range
		and absf(offset.y) <= vertical_detection_tolerance
	)


func _find_player_sibling() -> Player:
	var actor_parent := get_parent()
	if not is_instance_valid(actor_parent):
		return null
	for sibling: Node in actor_parent.get_children():
		if sibling is Player:
			return sibling as Player
	return null


func _begin_telegraph() -> void:
	var player_offset := player.global_position.x - global_position.x
	lunge_direction = (
		signf(player_offset)
		if not is_zero_approx(player_offset)
		else patrol_direction
	)
	patrol_direction = lunge_direction
	_sync_direction()
	state = State.TELEGRAPH
	state_time_remaining = telegraph_time
	velocity.x = 0.0
	telegraph_visual.visible = true


func _begin_lunge() -> void:
	state = State.LUNGE
	state_time_remaining = lunge_time
	telegraph_visual.visible = false
	attack_visual.visible = true
	attack_pivot.scale.x = lunge_direction
	struck_targets.clear()
	attack_area.monitoring = true


func _begin_recovery() -> void:
	_cancel_attack()
	state = State.RECOVERY
	state_time_remaining = recovery_time
	velocity.x = 0.0


func _enter_patrol() -> void:
	_cancel_attack()
	state = State.PATROL
	state_time_remaining = 0.0
	_sync_direction()


func _cancel_attack() -> void:
	telegraph_visual.visible = false
	attack_visual.visible = false
	attack_area.set_deferred("monitoring", false)


func _on_attack_area_body_entered(body: Node2D) -> void:
	_try_apply_shove(body)


func _on_attack_area_area_entered(area: Area2D) -> void:
	_try_apply_shove(area)


func _try_apply_shove(target: Node2D) -> void:
	if (
		state != State.LUNGE
		or target == self
		or not target.has_method("receive_impulse")
	):
		return

	var target_id := target.get_instance_id()
	if struck_targets.has(target_id):
		return

	struck_targets[target_id] = true
	target.call(
		"receive_impulse",
		Vector2(
			lunge_direction * shove_horizontal_impulse,
			shove_vertical_impulse
		)
	)

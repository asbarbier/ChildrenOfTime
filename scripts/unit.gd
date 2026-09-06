class_name RTSUnit
extends Node2D

enum Intent {
	IDLE,
	MOVE,
	ATTACK,
	CHASE,
	DEAD,
}

signal intent_changed(previous_intent: int, current_intent: int)

@export var move_speed: float = 190.0
@export var acceleration: float = 900.0
@export var radius: float = 14.0
@export var waypoint_tolerance: float = 22.0
@export var separation_radius: float = 34.0
@export var separation_strength: float = 0.85
@export var obstacle_clearance: float = 4.0

var selected: bool = false
var unit_id: int = 0
var current_intent: Intent = Intent.IDLE
var target_position := Vector2.ZERO
var current_velocity := Vector2.ZERO
var navigation_path := PackedVector2Array()
var path_index: int = 0

func _ready() -> void:
	target_position = global_position
	add_to_group("rts_units")
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func can_receive_commands() -> bool:
	return current_intent != Intent.DEAD

func command_move_to(world_position: Vector2) -> void:
	var fallback_path := PackedVector2Array()
	fallback_path.append(global_position)
	fallback_path.append(world_position)
	command_move_path(fallback_path)

func command_move_path(path: PackedVector2Array) -> void:
	if not can_receive_commands():
		return

	navigation_path = path
	path_index = 0

	if navigation_path.is_empty():
		command_stop()
		return

	target_position = navigation_path[navigation_path.size() - 1]

	while (
		path_index < navigation_path.size()
		and global_position.distance_to(navigation_path[path_index]) <= waypoint_tolerance
	):
		path_index += 1

	if path_index >= navigation_path.size():
		global_position = target_position
		command_stop()
		return

	_set_intent(Intent.MOVE)
	queue_redraw()

func command_stop() -> void:
	navigation_path = PackedVector2Array()
	path_index = 0
	target_position = global_position
	current_velocity = Vector2.ZERO

	if current_intent != Intent.DEAD:
		_set_intent(Intent.IDLE)

	queue_redraw()

func mark_dead() -> void:
	selected = false
	navigation_path = PackedVector2Array()
	path_index = 0
	current_velocity = Vector2.ZERO
	_set_intent(Intent.DEAD)
	queue_redraw()

func get_intent_name() -> String:
	match current_intent:
		Intent.IDLE:
			return "IDLE"
		Intent.MOVE:
			return "MOVE"
		Intent.ATTACK:
			return "ATTACK"
		Intent.CHASE:
			return "CHASE"
		Intent.DEAD:
			return "DEAD"
		_:
			return "UNKNOWN"

func _set_intent(next_intent: Intent) -> void:
	if current_intent == next_intent:
		return

	var previous_intent: int = current_intent
	current_intent = next_intent
	intent_changed.emit(previous_intent, current_intent)

func _process(delta: float) -> void:
	if current_intent != Intent.MOVE:
		return

	_advance_path_if_needed()
	if current_intent != Intent.MOVE:
		return

	var waypoint: Vector2 = navigation_path[path_index]
	var to_waypoint: Vector2 = waypoint - global_position
	var distance: float = to_waypoint.length()

	if distance <= 0.001:
		_advance_path_if_needed()
		return

	var desired_direction: Vector2 = to_waypoint.normalized()
	var separation: Vector2 = _get_separation_force()
	var steering: Vector2 = desired_direction + separation * separation_strength

	if steering == Vector2.ZERO:
		steering = desired_direction
	else:
		steering = steering.normalized()

	var desired_velocity: Vector2 = steering * move_speed
	current_velocity = current_velocity.move_toward(desired_velocity, acceleration * delta)

	if current_velocity.length() > move_speed:
		current_velocity = current_velocity.normalized() * move_speed

	global_position += current_velocity * delta
	_resolve_obstacle_overlap()
	_advance_path_if_needed()
	queue_redraw()

func _advance_path_if_needed() -> void:
	while path_index < navigation_path.size():
		var waypoint: Vector2 = navigation_path[path_index]
		if global_position.distance_to(waypoint) > waypoint_tolerance:
			break
		path_index += 1

	if path_index >= navigation_path.size():
		if global_position.distance_to(target_position) <= waypoint_tolerance:
			global_position = target_position
		command_stop()

func _get_separation_force() -> Vector2:
	var force := Vector2.ZERO

	for node in get_tree().get_nodes_in_group("rts_units"):
		if node == self or not node is RTSUnit:
			continue

		var other := node as RTSUnit
		if other.current_intent == Intent.DEAD:
			continue

		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()

		if distance > 0.001 and distance < separation_radius:
			var weight: float = 1.0 - (distance / separation_radius)
			force += offset.normalized() * weight

	return force

func _resolve_obstacle_overlap() -> void:
	for node in get_tree().get_nodes_in_group("rts_obstacles"):
		if not node is RTSObstacle:
			continue

		var obstacle := node as RTSObstacle
		var offset: Vector2 = global_position - obstacle.global_position
		var distance: float = offset.length()
		var minimum_distance: float = obstacle.radius + radius + obstacle_clearance

		if distance >= minimum_distance:
			continue

		if distance <= 0.001:
			var fallback_angle: float = float(unit_id) * 0.73
			offset = Vector2.RIGHT.rotated(fallback_angle)

		global_position = obstacle.global_position + offset.normalized() * minimum_distance

func contains_point(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= radius + 6.0

func _draw() -> void:
	# Placeholder unit art: readable now, replaceable later.
	draw_circle(Vector2.ZERO, radius, Color("87a96b"))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color("c7d7b5"), 2.0)
	draw_circle(Vector2(5, -4), 2.5, Color("172017"))

	if selected:
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Color("f0d96b"), 3.0)
		_draw_remaining_path()

func _draw_remaining_path() -> void:
	if current_intent != Intent.MOVE or path_index >= navigation_path.size():
		return

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)

	for i in range(path_index, navigation_path.size()):
		points.append(to_local(navigation_path[i]))

	if points.size() >= 2:
		draw_polyline(points, Color(0.95, 0.85, 0.35, 0.45), 2.0)

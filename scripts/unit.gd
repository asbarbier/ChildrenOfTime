class_name RTSUnit
extends Node2D

@export var move_speed: float = 190.0
@export var radius: float = 14.0
@export var separation_radius: float = 34.0
@export var separation_strength: float = 1.35
@export var obstacle_lookahead: float = 240.0
@export var obstacle_clearance: float = 14.0
@export var obstacle_avoidance_strength: float = 2.0

var selected: bool = false
var target_position: Vector2
var has_target: bool = false
var unit_id: int = 0

func _ready() -> void:
	target_position = global_position
	add_to_group("rts_units")
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func set_move_target(world_position: Vector2) -> void:
	target_position = world_position
	has_target = true

func _process(delta: float) -> void:
	if not has_target:
		return

	var to_target: Vector2 = target_position - global_position
	var distance: float = to_target.length()

	if distance <= 2.0:
		global_position = target_position
		has_target = false
		return

	var desired_direction: Vector2 = to_target.normalized()
	var separation: Vector2 = _get_separation_force()
	var obstacle_avoidance: Vector2 = _get_obstacle_avoidance(desired_direction)
	var steering: Vector2 = desired_direction

	if separation != Vector2.ZERO:
		steering += separation * separation_strength
	if obstacle_avoidance != Vector2.ZERO:
		steering += obstacle_avoidance * obstacle_avoidance_strength

	if steering == Vector2.ZERO:
		steering = desired_direction
	else:
		steering = steering.normalized()

	var step: Vector2 = steering * move_speed * delta
	if step.length() > distance and obstacle_avoidance == Vector2.ZERO:
		global_position = target_position
		has_target = false
	else:
		global_position += step
		_resolve_obstacle_overlap()

	queue_redraw()

func _get_separation_force() -> Vector2:
	var force := Vector2.ZERO

	for node in get_tree().get_nodes_in_group("rts_units"):
		if node == self or not node is RTSUnit:
			continue

		var other := node as RTSUnit
		var offset: Vector2 = global_position - other.global_position
		var distance: float = offset.length()

		if distance > 0.001 and distance < separation_radius:
			var weight: float = 1.0 - (distance / separation_radius)
			force += offset.normalized() * weight

	return force

func _get_obstacle_avoidance(forward: Vector2) -> Vector2:
	var force := Vector2.ZERO

	for node in get_tree().get_nodes_in_group("rts_obstacles"):
		if not node is RTSObstacle:
			continue

		var obstacle := node as RTSObstacle
		var to_obstacle: Vector2 = obstacle.global_position - global_position
		var forward_distance: float = to_obstacle.dot(forward)

		if forward_distance <= 0.0 or forward_distance > obstacle_lookahead:
			continue

		var lateral_offset: Vector2 = to_obstacle - forward * forward_distance
		var lateral_distance: float = lateral_offset.length()
		var safe_radius: float = obstacle.radius + radius + obstacle_clearance

		if lateral_distance >= safe_radius:
			continue

		var cross_value: float = forward.cross(to_obstacle)
		var steer_side: float

		if absf(cross_value) < 0.01:
			steer_side = -1.0 if unit_id % 2 == 0 else 1.0
		else:
			steer_side = -1.0 if cross_value > 0.0 else 1.0

		var perpendicular := Vector2(-forward.y, forward.x) * steer_side
		var lateral_weight: float = 1.0 - (lateral_distance / safe_radius)
		var approach_weight: float = 1.0 - (forward_distance / obstacle_lookahead)
		force += perpendicular * (0.75 + lateral_weight + approach_weight)

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

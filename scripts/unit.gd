class_name RTSUnit
extends Node2D

const RTSFactionComponentScript = preload("res://scripts/faction_component.gd")
const RTSCombatComponentScript = preload("res://scripts/combat_component.gd")

enum Intent {
	IDLE,
	MOVE,
	ATTACK,
	CHASE,
	DEAD,
}

signal intent_changed(previous_intent: int, current_intent: int)
signal chase_repath_requested(unit, target)
signal died(unit)

@export var move_speed: float = 190.0
@export var acceleration: float = 900.0
@export var radius: float = 14.0
@export var waypoint_tolerance: float = 22.0
@export var separation_radius: float = 34.0
@export var separation_strength: float = 0.85
@export var obstacle_clearance: float = 4.0
@export var chase_repath_interval: float = 0.35
@export var chase_repath_distance: float = 28.0

var selected: bool = false
var unit_id: int = 0
var current_intent: Intent = Intent.IDLE
var display_color: Color = Color("87a96b")
var body_texture: Texture2D
var visual_size: Vector2 = Vector2(56.0, 56.0)

var faction_component: RTSFactionComponent
var combat_component: RTSCombatComponent
var attack_target: RTSUnit = null

var target_position := Vector2.ZERO
var current_velocity := Vector2.ZERO
var navigation_path := PackedVector2Array()
var path_index: int = 0
var chase_repath_remaining: float = 0.0
var last_chase_target_position := Vector2.ZERO

func _ready() -> void:
	target_position = global_position
	add_to_group("rts_units")
	_build_components()
	queue_redraw()

func _build_components() -> void:
	faction_component = RTSFactionComponentScript.new() as RTSFactionComponent
	faction_component.name = "Faction"
	add_child(faction_component)

	combat_component = RTSCombatComponentScript.new() as RTSCombatComponent
	combat_component.name = "Combat"
	add_child(combat_component)
	combat_component.health_changed.connect(_on_health_changed)
	combat_component.died.connect(_on_combat_died)

func configure_affiliation(team_id: int, color: Color) -> void:
	display_color = color
	if faction_component != null:
		faction_component.configure(team_id)
	queue_redraw()

func configure_visual(texture: Texture2D, size: Vector2) -> void:
	body_texture = texture
	visual_size = Vector2(maxf(8.0, size.x), maxf(8.0, size.y))
	queue_redraw()

func configure_combat(
	health: float,
	damage: float,
	attack_range: float,
	attack_cooldown: float
) -> void:
	if combat_component != null:
		combat_component.configure(health, damage, attack_range, attack_cooldown)
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value and can_receive_commands()
	queue_redraw()

func can_receive_commands() -> bool:
	return current_intent != Intent.DEAD and is_alive()

func is_alive() -> bool:
	return combat_component != null and combat_component.is_alive()

func get_team_id() -> int:
	if faction_component == null:
		return 0
	return faction_component.team_id

func is_on_team(team_id: int) -> bool:
	return get_team_id() == team_id

func is_hostile_to(other: RTSUnit) -> bool:
	if other == null or faction_component == null or other.faction_component == null:
		return false
	return faction_component.is_hostile_to(other.faction_component)

func is_valid_attack_target(other: RTSUnit) -> bool:
	return (
		other != null
		and is_instance_valid(other)
		and other != self
		and other.is_alive()
		and is_hostile_to(other)
	)

func command_move_to(world_position: Vector2) -> void:
	var fallback_path := PackedVector2Array()
	fallback_path.append(global_position)
	fallback_path.append(world_position)
	command_move_path(fallback_path)

func command_move_path(path: PackedVector2Array) -> void:
	if not can_receive_commands():
		return

	attack_target = null
	_set_navigation_path(path, Intent.MOVE)

func command_attack_target(target: RTSUnit, path: PackedVector2Array) -> void:
	if not can_receive_commands() or not is_valid_attack_target(target):
		return

	attack_target = target
	last_chase_target_position = target.global_position
	chase_repath_remaining = 0.0

	if _is_attack_target_in_range():
		_begin_attacking()
		return

	_set_navigation_path(path, Intent.CHASE)
	if navigation_path.is_empty():
		_request_chase_repath()

func command_chase_path(target: RTSUnit, path: PackedVector2Array) -> void:
	if not can_receive_commands() or not is_valid_attack_target(target):
		command_stop()
		return

	attack_target = target
	last_chase_target_position = target.global_position

	if _is_attack_target_in_range():
		_begin_attacking()
		return

	_set_navigation_path(path, Intent.CHASE)

func command_stop() -> void:
	attack_target = null
	_clear_navigation()
	current_velocity = Vector2.ZERO

	if current_intent != Intent.DEAD:
		_set_intent(Intent.IDLE)

	queue_redraw()

func mark_dead() -> void:
	selected = false
	attack_target = null
	_clear_navigation()
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

func _set_navigation_path(path: PackedVector2Array, next_intent: Intent) -> void:
	navigation_path = path
	path_index = 0

	if navigation_path.is_empty():
		current_velocity = Vector2.ZERO
		if next_intent == Intent.MOVE:
			command_stop()
		else:
			_set_intent(next_intent)
		return

	target_position = navigation_path[navigation_path.size() - 1]

	while (
		path_index < navigation_path.size()
		and global_position.distance_to(navigation_path[path_index]) <= waypoint_tolerance
	):
		path_index += 1

	_set_intent(next_intent)

	if path_index >= navigation_path.size():
		_on_navigation_path_finished()
		return

	queue_redraw()

func _clear_navigation() -> void:
	navigation_path = PackedVector2Array()
	path_index = 0
	target_position = global_position

func _process(delta: float) -> void:
	if chase_repath_remaining > 0.0:
		chase_repath_remaining = maxf(0.0, chase_repath_remaining - delta)

	match current_intent:
		Intent.MOVE:
			_process_navigation_movement(delta)
		Intent.CHASE:
			_process_chase(delta)
		Intent.ATTACK:
			_process_attack()

func _process_chase(delta: float) -> void:
	if not _has_valid_attack_target():
		command_stop()
		return

	if _is_attack_target_in_range():
		_begin_attacking()
		return

	if attack_target.global_position.distance_to(last_chase_target_position) >= chase_repath_distance:
		_request_chase_repath()

	if navigation_path.is_empty() or path_index >= navigation_path.size():
		current_velocity = current_velocity.move_toward(Vector2.ZERO, acceleration * delta)
		_request_chase_repath()
		return

	_process_navigation_movement(delta)

	if current_intent == Intent.CHASE and _is_attack_target_in_range():
		_begin_attacking()

func _process_attack() -> void:
	if not _has_valid_attack_target():
		command_stop()
		return

	if not _is_attack_target_in_range():
		_clear_navigation()
		current_velocity = Vector2.ZERO
		_set_intent(Intent.CHASE)
		_request_chase_repath()
		return

	current_velocity = Vector2.ZERO
	if combat_component.try_attack(attack_target.combat_component):
		attack_target.queue_redraw()

func _process_navigation_movement(delta: float) -> void:
	_advance_path_if_needed()
	if current_intent != Intent.MOVE and current_intent != Intent.CHASE:
		return
	if path_index >= navigation_path.size():
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
		_on_navigation_path_finished()

func _on_navigation_path_finished() -> void:
	if current_intent == Intent.MOVE:
		if global_position.distance_to(target_position) <= waypoint_tolerance:
			global_position = target_position
		command_stop()
		return

	if current_intent == Intent.CHASE:
		_clear_navigation()
		current_velocity = Vector2.ZERO
		if _is_attack_target_in_range():
			_begin_attacking()
		else:
			_request_chase_repath()

func _begin_attacking() -> void:
	_clear_navigation()
	current_velocity = Vector2.ZERO
	_set_intent(Intent.ATTACK)
	queue_redraw()

func _request_chase_repath() -> void:
	if chase_repath_remaining > 0.0 or not _has_valid_attack_target():
		return

	chase_repath_remaining = chase_repath_interval
	last_chase_target_position = attack_target.global_position
	chase_repath_requested.emit(self, attack_target)

func _has_valid_attack_target() -> bool:
	return attack_target != null and is_instance_valid(attack_target) and is_valid_attack_target(attack_target)

func _is_attack_target_in_range() -> bool:
	if not _has_valid_attack_target() or combat_component == null:
		return false

	var center_distance: float = global_position.distance_to(attack_target.global_position)
	var edge_distance: float = maxf(0.0, center_distance - radius - attack_target.radius)
	return edge_distance <= combat_component.attack_range

func _get_separation_force() -> Vector2:
	var force := Vector2.ZERO

	for node in get_tree().get_nodes_in_group("rts_units"):
		if node == self or not node is RTSUnit:
			continue

		var other := node as RTSUnit
		if not other.is_alive():
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
	var selection_radius: float = maxf(radius + 6.0, maxf(visual_size.x, visual_size.y) * 0.42)
	return is_alive() and global_position.distance_to(world_point) <= selection_radius

func _on_health_changed(_current_health: float, _max_health: float) -> void:
	queue_redraw()

func _on_combat_died() -> void:
	mark_dead()
	died.emit(self)

func _draw() -> void:
	if body_texture != null:
		var half_size: Vector2 = visual_size * 0.5
		var texture_rect := Rect2(-half_size, visual_size)
		var texture_tint := Color.WHITE if is_alive() else Color(0.42, 0.44, 0.42, 0.82)
		draw_texture_rect(body_texture, texture_rect, false, texture_tint)
	else:
		var body_color: Color = display_color if is_alive() else Color("4a4f49")
		var outline_color: Color = body_color.lightened(0.3) if is_alive() else Color("686d67")
		draw_circle(Vector2.ZERO, radius, body_color)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, outline_color, 2.0)
		draw_circle(Vector2(5, -4), 2.5, Color("172017"))

	if is_alive() and combat_component != null and combat_component.current_health < combat_component.max_health:
		_draw_health_bar()

	if selected and is_alive():
		var selection_radius: float = maxf(radius + 6.0, maxf(visual_size.x, visual_size.y) * 0.42)
		draw_arc(Vector2.ZERO, selection_radius, 0.0, TAU, 32, Color("f0d96b"), 3.0)
		_draw_remaining_path()

func _draw_health_bar() -> void:
	var bar_width: float = maxf(34.0, visual_size.x * 0.68)
	var bar_height: float = 5.0
	var sprite_half_height: float = visual_size.y * 0.5
	var bar_y: float = -maxf(radius, sprite_half_height) - 10.0
	var bar_origin := Vector2(-bar_width * 0.5, bar_y)
	var ratio: float = combat_component.get_health_ratio()

	draw_rect(Rect2(bar_origin, Vector2(bar_width, bar_height)), Color("20241f"), true)
	draw_rect(Rect2(bar_origin, Vector2(bar_width * ratio, bar_height)), display_color.lightened(0.25), true)

func _draw_remaining_path() -> void:
	if (
		(current_intent != Intent.MOVE and current_intent != Intent.CHASE)
		or path_index >= navigation_path.size()
	):
		return

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)

	for i in range(path_index, navigation_path.size()):
		points.append(to_local(navigation_path[i]))

	if points.size() >= 2:
		draw_polyline(points, Color(0.95, 0.85, 0.35, 0.45), 2.0)

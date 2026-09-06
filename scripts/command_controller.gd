class_name RTSCommandController
extends Node

@export var formation_spacing: float = 42.0

var navigation_manager: RTSNavigationManager
var world_size := Vector2.ZERO

func configure(nav_manager: RTSNavigationManager, map_size: Vector2) -> void:
	navigation_manager = nav_manager
	world_size = map_size

func issue_move_order(commanded_units: Array[RTSUnit], destination: Vector2) -> void:
	if navigation_manager == null:
		return

	var active_units := _get_commandable_units(commanded_units)
	if active_units.is_empty():
		return

	var count: int = active_units.size()
	var columns: int = int(ceil(sqrt(float(count))))
	var rows: int = int(ceil(float(count) / float(columns)))
	var formation_width: float = float(columns - 1) * formation_spacing
	var formation_height: float = float(rows - 1) * formation_spacing

	for i in range(count):
		var col: int = i % columns
		var row: int = int(floor(float(i) / float(columns)))
		var offset := Vector2(
			float(col) * formation_spacing - formation_width * 0.5,
			float(row) * formation_spacing - formation_height * 0.5
		)
		var unit: RTSUnit = active_units[i]
		var requested_target: Vector2 = _clamp_to_map(destination + offset)
		var path: PackedVector2Array = navigation_manager.find_navigation_path(
			unit.global_position,
			requested_target
		)

		if path.size() >= 2:
			unit.command_move_path(path)
		else:
			# NavigationServer2D may need a sync immediately after startup.
			# This keeps orders functional without moving pathfinding into the unit.
			unit.command_move_to(requested_target)

func issue_attack_order(commanded_units: Array[RTSUnit], target: RTSUnit) -> void:
	if navigation_manager == null or target == null or not target.is_alive():
		return

	for unit in commanded_units:
		if unit == null or not unit.can_receive_commands():
			continue
		if not unit.is_valid_attack_target(target):
			continue

		_register_chase_repath(unit)
		_assign_attack_route(unit, target)

func issue_stop_order(commanded_units: Array[RTSUnit]) -> void:
	for unit in commanded_units:
		if unit != null and unit.can_receive_commands():
			unit.command_stop()

func _assign_attack_route(unit: RTSUnit, target: RTSUnit) -> void:
	if unit == null or target == null or not unit.is_valid_attack_target(target):
		return

	var destination: Vector2 = _clamp_to_map(target.global_position)
	var path: PackedVector2Array = navigation_manager.find_navigation_path(
		unit.global_position,
		destination
	)

	if path.size() < 2:
		path = PackedVector2Array()
		path.append(unit.global_position)
		path.append(destination)

	unit.command_attack_target(target, path)

func _register_chase_repath(unit: RTSUnit) -> void:
	if not unit.chase_repath_requested.is_connected(_on_chase_repath_requested):
		unit.chase_repath_requested.connect(_on_chase_repath_requested)

func _on_chase_repath_requested(unit: RTSUnit, target: RTSUnit) -> void:
	if navigation_manager == null:
		return
	if unit == null or target == null or not unit.is_valid_attack_target(target):
		return

	var destination: Vector2 = _clamp_to_map(target.global_position)
	var path: PackedVector2Array = navigation_manager.find_navigation_path(
		unit.global_position,
		destination
	)

	if path.size() < 2:
		path = PackedVector2Array()
		path.append(unit.global_position)
		path.append(destination)

	unit.command_chase_path(target, path)

func _get_commandable_units(commanded_units: Array[RTSUnit]) -> Array[RTSUnit]:
	var active_units: Array[RTSUnit] = []
	for unit in commanded_units:
		if unit != null and unit.can_receive_commands():
			active_units.append(unit)
	return active_units

func _clamp_to_map(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, 0.0, world_size.x),
		clampf(point.y, 0.0, world_size.y)
	)

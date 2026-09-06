class_name RTSNavigationManager
extends Node

@export var agent_radius: float = 30.0
@export var nav_cell_size: float = 2.0
@export var obstacle_segments: int = 32

var navigation_map: RID
var navigation_region: RID
var navigation_polygon: NavigationPolygon

func build(world_size: Vector2, obstacles: Array[RTSObstacle]) -> void:
	_cleanup_navigation()

	navigation_map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(navigation_map, nav_cell_size)
	NavigationServer2D.map_set_active(navigation_map, true)

	navigation_region = NavigationServer2D.region_create()
	NavigationServer2D.region_set_enabled(navigation_region, true)
	NavigationServer2D.region_set_map(navigation_region, navigation_map)

	navigation_polygon = NavigationPolygon.new()
	navigation_polygon.agent_radius = agent_radius
	navigation_polygon.cell_size = nav_cell_size

	var source_geometry := NavigationMeshSourceGeometryData2D.new()
	source_geometry.add_traversable_outline(PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(world_size.x, 0.0),
		Vector2(world_size.x, world_size.y),
		Vector2(0.0, world_size.y),
	]))

	for obstacle in obstacles:
		source_geometry.add_obstruction_outline(
			_make_circle_outline(obstacle.global_position, obstacle.radius, obstacle_segments)
		)

	NavigationServer2D.bake_from_source_geometry_data(navigation_polygon, source_geometry)
	NavigationServer2D.region_set_navigation_polygon(navigation_region, navigation_polygon)

func is_ready() -> bool:
	return (
		navigation_map.is_valid()
		and NavigationServer2D.map_get_iteration_id(navigation_map) > 0
	)

func get_path(start: Vector2, destination: Vector2) -> PackedVector2Array:
	if not is_ready():
		return PackedVector2Array()

	var safe_start := NavigationServer2D.map_get_closest_point(navigation_map, start)
	var safe_destination := NavigationServer2D.map_get_closest_point(navigation_map, destination)
	return NavigationServer2D.map_get_path(
		navigation_map,
		safe_start,
		safe_destination,
		true
	)

func _make_circle_outline(center: Vector2, radius: float, segments: int) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var segment_count := maxi(segments, 8)

	for i in range(segment_count):
		var angle := TAU * float(i) / float(segment_count)
		outline.append(center + Vector2(cos(angle), sin(angle)) * radius)

	return outline

func _cleanup_navigation() -> void:
	if navigation_region.is_valid():
		NavigationServer2D.free_rid(navigation_region)
		navigation_region = RID()

	if navigation_map.is_valid():
		NavigationServer2D.free_rid(navigation_map)
		navigation_map = RID()

func _exit_tree() -> void:
	_cleanup_navigation()

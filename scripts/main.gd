extends Node2D

const RTSUnitScript = preload("res://scripts/unit.gd")
const RTSObstacleScript = preload("res://scripts/obstacle.gd")
const RTSNavigationManagerScript = preload("res://scripts/navigation_manager.gd")

const MAP_SIZE := Vector2(3200.0, 1800.0)
const GRID_SIZE := 64.0
const CAMERA_SPEED := 700.0
const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.0
const CLICK_DRAG_THRESHOLD := 8.0
const FORMATION_SPACING := 42.0

@onready var camera: Camera2D = $Camera2D

var units: Array[RTSUnit] = []
var selected_units: Array[RTSUnit] = []
var obstacles: Array[RTSObstacle] = []
var navigation_manager: RTSNavigationManager

var dragging_selection := false
var drag_start_world := Vector2.ZERO
var drag_current_world := Vector2.ZERO
var drag_start_screen := Vector2.ZERO

var middle_dragging := false
var command_marker_position := Vector2.ZERO
var command_marker_time := 0.0

var status_label: Label

func _ready() -> void:
	_spawn_test_obstacles()
	_build_navigation()
	_spawn_test_units()
	_build_ui()
	queue_redraw()

func _process(delta: float) -> void:
	_update_camera_keyboard(delta)

	if command_marker_time > 0.0:
		command_marker_time -= delta
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging_selection = true
			drag_start_world = get_global_mouse_position()
			drag_current_world = drag_start_world
			drag_start_screen = event.position
			queue_redraw()
		else:
			if dragging_selection:
				drag_current_world = get_global_mouse_position()
				var was_click := event.position.distance_to(drag_start_screen) < CLICK_DRAG_THRESHOLD
				_finish_selection(was_click, Input.is_key_pressed(KEY_SHIFT))
				dragging_selection = false
				queue_redraw()

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_move_command(get_global_mouse_position())

	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		middle_dragging = event.pressed

	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_set_camera_zoom(camera.zoom.x * 1.12)

	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_set_camera_zoom(camera.zoom.x / 1.12)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if dragging_selection:
		drag_current_world = get_global_mouse_position()
		queue_redraw()

	if middle_dragging:
		camera.position -= event.relative / camera.zoom.x
		_clamp_camera()

func _finish_selection(was_click: bool, additive: bool) -> void:
	if not additive:
		_clear_selection()

	if was_click:
		var mouse_world := drag_current_world
		var closest: RTSUnit = null
		var closest_distance := INF

		for unit in units:
			if unit.contains_point(mouse_world):
				var distance := unit.global_position.distance_to(mouse_world)
				if distance < closest_distance:
					closest = unit
					closest_distance = distance

		if closest != null:
			if additive and closest.selected:
				_deselect_unit(closest)
			else:
				_select_unit(closest)
	else:
		var selection_rect := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()
		for unit in units:
			if selection_rect.has_point(unit.global_position):
				_select_unit(unit)

	_update_status()

func _select_unit(unit: RTSUnit) -> void:
	if unit.selected:
		return
	unit.set_selected(true)
	selected_units.append(unit)

func _deselect_unit(unit: RTSUnit) -> void:
	unit.set_selected(false)
	selected_units.erase(unit)

func _clear_selection() -> void:
	for unit in selected_units:
		unit.set_selected(false)
	selected_units.clear()

func _issue_move_command(world_position: Vector2) -> void:
	if selected_units.is_empty():
		return

	var count := selected_units.size()
	var columns := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(columns)))
	var formation_width := float(columns - 1) * FORMATION_SPACING
	var formation_height := float(rows - 1) * FORMATION_SPACING

	for i in range(count):
		var col := i % columns
		var row := i / columns
		var offset := Vector2(
			float(col) * FORMATION_SPACING - formation_width * 0.5,
			float(row) * FORMATION_SPACING - formation_height * 0.5
		)
		var unit := selected_units[i]
		var requested_target := _clamp_to_map(world_position + offset)
		var path := navigation_manager.get_path(unit.global_position, requested_target)

		if path.size() >= 2:
			unit.set_navigation_path(path)
		else:
			# The NavigationServer needs at least one physics sync after startup.
			# Direct movement is only a startup fallback, not the normal pathing mode.
			unit.set_move_target(requested_target)

	command_marker_position = world_position
	command_marker_time = 0.7
	queue_redraw()

func _build_navigation() -> void:
	navigation_manager = RTSNavigationManagerScript.new() as RTSNavigationManager
	navigation_manager.name = "NavigationManager"
	add_child(navigation_manager)
	navigation_manager.build(MAP_SIZE, obstacles)

func _spawn_test_obstacles() -> void:
	var rock := RTSObstacleScript.new() as RTSObstacle
	rock.name = "TheRock"
	rock.position = Vector2(1200.0, 700.0)
	rock.radius = 145.0
	add_child(rock)
	obstacles.append(rock)

func _spawn_test_units() -> void:
	var start := Vector2(540.0, 430.0)
	var spacing := 48.0
	var id_counter := 1

	for row in range(3):
		for col in range(4):
			var unit := RTSUnitScript.new() as RTSUnit
			unit.name = "Unit_%02d" % id_counter
			unit.unit_id = id_counter
			unit.position = start + Vector2(col * spacing, row * spacing)
			add_child(unit)
			units.append(unit)
			id_counter += 1

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(430, 0)
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	var title := Label.new()
	title.text = "EVOLUTION RTS — NAVIGATION PROTOTYPE"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var instructions := Label.new()
	instructions.text = "Drag-select • Shift adds/removes • Right-click moves\nWASD/arrows pan • Mouse wheel zoom • Middle-drag camera • R resets\nGlobal route: NavigationServer2D • Local behavior: separation + smooth steering"
	box.add_child(instructions)

	status_label = Label.new()
	box.add_child(status_label)
	_update_status()

func _update_status() -> void:
	if status_label != null:
		status_label.text = "%d / %d units selected" % [selected_units.size(), units.size()]

func _update_camera_keyboard(delta: float) -> void:
	var direction := Vector2.ZERO

	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0

	if direction != Vector2.ZERO:
		camera.position += direction.normalized() * CAMERA_SPEED * delta / camera.zoom.x
		_clamp_camera()

func _set_camera_zoom(value: float) -> void:
	var new_zoom: float = clampf(value, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(new_zoom, new_zoom)

func _clamp_camera() -> void:
	camera.position = _clamp_to_map(camera.position)

func _clamp_to_map(point: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, 0.0, MAP_SIZE.x),
		clampf(point.y, 0.0, MAP_SIZE.y)
	)

func _draw() -> void:
	# Playfield background.
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("152019"), true)

	# Coarse terrain/grid placeholder so movement and camera scale are readable.
	var grid_color := Color("243329")
	var x := 0.0
	while x <= MAP_SIZE.x:
		draw_line(Vector2(x, 0), Vector2(x, MAP_SIZE.y), grid_color, 1.0)
		x += GRID_SIZE

	var y := 0.0
	while y <= MAP_SIZE.y:
		draw_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), grid_color, 1.0)
		y += GRID_SIZE

	# Map edge.
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("526353"), false, 3.0)

	if dragging_selection:
		var rect := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()
		draw_rect(rect, Color(0.9, 0.85, 0.35, 0.12), true)
		draw_rect(rect, Color("f0d96b"), false, 2.0)

	if command_marker_time > 0.0:
		var alpha: float = clampf(command_marker_time / 0.7, 0.0, 1.0)
		draw_arc(command_marker_position, 18.0, 0.0, TAU, 24, Color(0.95, 0.85, 0.35, alpha), 3.0)
		draw_line(command_marker_position + Vector2(-8, 0), command_marker_position + Vector2(8, 0), Color(0.95, 0.85, 0.35, alpha), 2.0)
		draw_line(command_marker_position + Vector2(0, -8), command_marker_position + Vector2(0, 8), Color(0.95, 0.85, 0.35, alpha), 2.0)

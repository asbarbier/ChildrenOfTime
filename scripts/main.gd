extends Node2D

const RTSObstacleScript = preload("res://scripts/obstacle.gd")
const RTSNavigationManagerScript = preload("res://scripts/navigation_manager.gd")
const RTSCommandControllerScript = preload("res://scripts/command_controller.gd")
const RTSAIControllerScript = preload("res://scripts/ai_controller.gd")
const RTSUnitFactoryScript = preload("res://scripts/unit_factory.gd")
const RTSLineageStateScript = preload("res://scripts/lineage_state.gd")
const RTSEncounterControllerScript = preload("res://scripts/encounter_controller.gd")
const PRIMITIVE_HUNTER_DEFINITION: RTSUnitDefinition = preload("res://data/units/primitive_hunter.tres")
const RIVAL_HUNTER_DEFINITION: RTSUnitDefinition = preload("res://data/units/rival_hunter.tres")
const CARAPACE_ADAPTATION: RTSAdaptationDefinition = preload("res://data/adaptations/carapace.tres")
const PREDATORY_LIMBS_ADAPTATION: RTSAdaptationDefinition = preload("res://data/adaptations/predatory_limbs.tres")

const MAP_SIZE := Vector2(3200.0, 1800.0)
const GRID_SIZE := 64.0
const CAMERA_SPEED := 700.0
const MIN_ZOOM := 0.55
const MAX_ZOOM := 2.0
const CLICK_DRAG_THRESHOLD := 8.0
const PLAYER_TEAM_ID := 1
const ENEMY_TEAM_ID := 2

@onready var camera: Camera2D = $Camera2D

var units: Array[RTSUnit] = []
var selected_units: Array[RTSUnit] = []
var obstacles: Array[RTSObstacle] = []
var navigation_manager: RTSNavigationManager
var command_controller: RTSCommandController
var ai_controller: RTSAIController
var unit_factory: RTSUnitFactory
var encounter_controller: RTSEncounterController
var player_lineage: RTSLineageState
var enemy_lineage: RTSLineageState

var dragging_selection: bool = false
var drag_start_world := Vector2.ZERO
var drag_current_world := Vector2.ZERO
var drag_start_screen := Vector2.ZERO

var middle_dragging: bool = false
var command_marker_position := Vector2.ZERO
var command_marker_time: float = 0.0
var adaptation_choice_made: bool = false

var status_label: Label
var adaptation_panel: PanelContainer
var result_panel: PanelContainer
var result_label: Label

func _ready() -> void:
	_spawn_test_obstacles()
	_build_navigation()
	_build_command_controller()
	_build_lineages()
	_build_unit_factory()
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
				var was_click: bool = event.position.distance_to(drag_start_screen) < CLICK_DRAG_THRESHOLD
				_finish_selection(was_click, Input.is_key_pressed(KEY_SHIFT))
				dragging_selection = false
				queue_redraw()

	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_context_command(get_global_mouse_position())

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
		var closest := _find_unit_at_point(drag_current_world, PLAYER_TEAM_ID)
		if closest != null:
			if additive and closest.selected:
				_deselect_unit(closest)
			else:
				_select_unit(closest)
	else:
		var selection_rect := Rect2(drag_start_world, drag_current_world - drag_start_world).abs()
		for unit in units:
			if (
				unit.is_alive()
				and unit.is_on_team(PLAYER_TEAM_ID)
				and selection_rect.has_point(unit.global_position)
			):
				_select_unit(unit)

	_update_status()

func _find_unit_at_point(world_point: Vector2, team_filter: int = 0) -> RTSUnit:
	var closest: RTSUnit = null
	var closest_distance: float = INF

	for unit in units:
		if not unit.is_alive():
			continue
		if team_filter > 0 and not unit.is_on_team(team_filter):
			continue
		if not unit.contains_point(world_point):
			continue

		var distance: float = unit.global_position.distance_to(world_point)
		if distance < closest_distance:
			closest = unit
			closest_distance = distance

	return closest

func _select_unit(unit: RTSUnit) -> void:
	if unit.selected or not unit.can_receive_commands() or not unit.is_on_team(PLAYER_TEAM_ID):
		return
	unit.set_selected(true)
	selected_units.append(unit)

func _deselect_unit(unit: RTSUnit) -> void:
	unit.set_selected(false)
	selected_units.erase(unit)

func _clear_selection() -> void:
	for unit in selected_units:
		if unit != null and is_instance_valid(unit):
			unit.set_selected(false)
	selected_units.clear()

func _issue_context_command(world_position: Vector2) -> void:
	if selected_units.is_empty():
		return

	var target := _find_unit_at_point(world_position)
	if target != null and _selection_can_attack(target):
		command_controller.issue_attack_order(selected_units, target)
	else:
		command_controller.issue_move_order(selected_units, world_position)

	command_marker_position = world_position
	command_marker_time = 0.7
	queue_redraw()

func _selection_can_attack(target: RTSUnit) -> bool:
	if target == null or not target.is_alive():
		return false

	for unit in selected_units:
		if unit != null and unit.is_valid_attack_target(target):
			return true

	return false

func _build_navigation() -> void:
	navigation_manager = RTSNavigationManagerScript.new() as RTSNavigationManager
	navigation_manager.name = "NavigationManager"
	add_child(navigation_manager)
	navigation_manager.build(MAP_SIZE, obstacles)

func _build_command_controller() -> void:
	command_controller = RTSCommandControllerScript.new() as RTSCommandController
	command_controller.name = "CommandController"
	add_child(command_controller)
	command_controller.configure(navigation_manager, MAP_SIZE)

func _build_ai_controller() -> void:
	ai_controller = RTSAIControllerScript.new() as RTSAIController
	ai_controller.name = "EnemyAI"
	add_child(ai_controller)
	ai_controller.configure(command_controller, ENEMY_TEAM_ID)

func _build_encounter_controller() -> void:
	encounter_controller = RTSEncounterControllerScript.new() as RTSEncounterController
	encounter_controller.name = "EncounterController"
	add_child(encounter_controller)
	encounter_controller.encounter_finished.connect(_on_encounter_finished)
	encounter_controller.configure(
		PLAYER_TEAM_ID,
		ENEMY_TEAM_ID,
		player_lineage,
		units
	)

func _build_lineages() -> void:
	player_lineage = RTSLineageStateScript.new() as RTSLineageState
	player_lineage.configure("First Lineage", 1)

	enemy_lineage = RTSLineageStateScript.new() as RTSLineageState
	enemy_lineage.configure("Rival Lineage", 1)

func _build_unit_factory() -> void:
	unit_factory = RTSUnitFactoryScript.new() as RTSUnitFactory
	unit_factory.name = "UnitFactory"
	add_child(unit_factory)

func _spawn_test_obstacles() -> void:
	var rock := RTSObstacleScript.new() as RTSObstacle
	rock.name = "TheRock"
	rock.position = Vector2(1200.0, 700.0)
	rock.radius = 145.0
	add_child(rock)
	obstacles.append(rock)

func _start_encounter(adaptation: RTSAdaptationDefinition) -> void:
	if adaptation_choice_made or adaptation == null:
		return

	player_lineage.add_adaptation(adaptation)
	adaptation_choice_made = true

	if adaptation_panel != null:
		adaptation_panel.hide()

	_spawn_test_units()
	_build_ai_controller()
	_build_encounter_controller()
	_update_status()
	queue_redraw()

func _on_carapace_pressed() -> void:
	_start_encounter(CARAPACE_ADAPTATION)

func _on_predatory_limbs_pressed() -> void:
	_start_encounter(PREDATORY_LIMBS_ADAPTATION)

func _spawn_test_units() -> void:
	var id_counter: int = 1
	var player_start := Vector2(540.0, 430.0)
	var enemy_start := Vector2(1720.0, 700.0)
	var spacing: float = 58.0

	for row in range(3):
		for col in range(4):
			_spawn_unit(
				id_counter,
				PRIMITIVE_HUNTER_DEFINITION,
				player_lineage,
				PLAYER_TEAM_ID,
				Color("87a96b"),
				player_start + Vector2(float(col) * spacing, float(row) * spacing)
			)
			id_counter += 1

	for row in range(2):
		for col in range(4):
			_spawn_unit(
				id_counter,
				RIVAL_HUNTER_DEFINITION,
				enemy_lineage,
				ENEMY_TEAM_ID,
				Color("b8665b"),
				enemy_start + Vector2(float(col) * spacing, float(row) * spacing)
			)
			id_counter += 1

func _spawn_unit(
	id_value: int,
	definition: RTSUnitDefinition,
	lineage: RTSLineageState,
	team_id: int,
	color: Color,
	position_value: Vector2
) -> void:
	var unit: RTSUnit = unit_factory.spawn_unit(
		self,
		definition,
		lineage,
		id_value,
		team_id,
		color,
		position_value
	)
	if unit == null:
		return

	unit.died.connect(_on_unit_died)
	units.append(unit)

func _on_unit_died(unit: RTSUnit) -> void:
	selected_units.erase(unit)
	_update_status()

func _on_encounter_finished(victory: bool, report: Dictionary) -> void:
	_clear_selection()
	_update_status()

	if result_panel == null or result_label == null:
		return

	var friendly_alive: int = int(report.get("friendly_alive", 0))
	var initial_friendly: int = int(report.get("initial_friendly_count", 0))
	var hostiles_defeated: int = int(report.get("hostiles_defeated", 0))
	var initial_hostiles: int = int(report.get("initial_hostile_count", 0))
	var kill_points: int = int(report.get("kill_points", 0))
	var survival_points: int = int(report.get("survival_points", 0))
	var completion_points: int = int(report.get("completion_points", 0))
	var time_points: int = int(report.get("time_points", 0))
	var elapsed_seconds: float = float(report.get("elapsed_seconds", 0.0))
	var encounter_score: int = int(report.get("encounter_score", 0))
	var lineage_score: int = int(report.get("lineage_score", player_lineage.score))
	var outcome_title: String = "EPOCH ENCOUNTER SURVIVED" if victory else "LINEAGE COLLAPSED"

	result_label.text = "%s\n\nEastern Basin • %.1f seconds\nRivals defeated: %d / %d    +%d\nLineage survivors: %d / %d    +%d\nTempo bonus: +%d\nSurvival victory: +%d\n\nENCOUNTER SCORE: +%d\nLINEAGE SCORE: %d\n\nHistory: %s\n\nPress R to begin another lineage." % [
		outcome_title,
		elapsed_seconds,
		hostiles_defeated,
		initial_hostiles,
		kill_points,
		friendly_alive,
		initial_friendly,
		survival_points,
		time_points,
		completion_points,
		encounter_score,
		lineage_score,
		player_lineage.get_latest_history(),
	]
	result_panel.show()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(610, 0)
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
	title.text = "EVOLUTION RTS — ENCOUNTER SCORE"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var instructions := Label.new()
	instructions.text = "Choose an adaptation, survive the eastern basin, and turn the result into lineage history.\nDrag-select • Right-click move/attack • Hostiles aggro nearby • R starts a new lineage"
	box.add_child(instructions)

	status_label = Label.new()
	box.add_child(status_label)

	adaptation_panel = PanelContainer.new()
	adaptation_panel.position = Vector2(16, 150)
	adaptation_panel.custom_minimum_size = Vector2(610, 0)
	canvas.add_child(adaptation_panel)

	var adaptation_margin := MarginContainer.new()
	adaptation_margin.add_theme_constant_override("margin_left", 14)
	adaptation_margin.add_theme_constant_override("margin_right", 14)
	adaptation_margin.add_theme_constant_override("margin_top", 12)
	adaptation_margin.add_theme_constant_override("margin_bottom", 12)
	adaptation_panel.add_child(adaptation_margin)

	var adaptation_box := VBoxContainer.new()
	adaptation_box.add_theme_constant_override("separation", 8)
	adaptation_margin.add_child(adaptation_box)

	var choice_title := Label.new()
	choice_title.text = "ADAPTIVE PRESSURE: Rival hunters occupy the eastern basin."
	choice_title.add_theme_font_size_override("font_size", 16)
	adaptation_box.add_child(choice_title)

	var choice_prompt := Label.new()
	choice_prompt.text = "What does your lineage become?"
	adaptation_box.add_child(choice_prompt)

	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	adaptation_box.add_child(choices)

	var carapace_button := Button.new()
	carapace_button.text = "HARDENED CARAPACE\n150 HP • 156 speed • armored"
	carapace_button.custom_minimum_size = Vector2(285, 70)
	carapace_button.pressed.connect(_on_carapace_pressed)
	choices.add_child(carapace_button)

	var predatory_button := Button.new()
	predatory_button.text = "PREDATORY LIMBS\n85 HP • 29 damage • 224 speed"
	predatory_button.custom_minimum_size = Vector2(285, 70)
	predatory_button.pressed.connect(_on_predatory_limbs_pressed)
	choices.add_child(predatory_button)

	result_panel = PanelContainer.new()
	result_panel.position = Vector2(16, 150)
	result_panel.custom_minimum_size = Vector2(610, 0)
	canvas.add_child(result_panel)

	var result_margin := MarginContainer.new()
	result_margin.add_theme_constant_override("margin_left", 16)
	result_margin.add_theme_constant_override("margin_right", 16)
	result_margin.add_theme_constant_override("margin_top", 14)
	result_margin.add_theme_constant_override("margin_bottom", 14)
	result_panel.add_child(result_margin)

	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 15)
	result_margin.add_child(result_label)
	result_panel.hide()

	_update_status()

func _update_status() -> void:
	if status_label == null:
		return

	var friendly_alive: int = 0
	var enemy_alive: int = 0
	for unit in units:
		if not unit.is_alive():
			continue
		if unit.is_on_team(PLAYER_TEAM_ID):
			friendly_alive += 1
		elif unit.is_on_team(ENEMY_TEAM_ID):
			enemy_alive += 1

	var adaptation_summary: String = player_lineage.get_adaptation_summary()
	status_label.text = "%s • Epoch %d • Evolution: %s • Score %d\n%d selected • %d friendly alive • %d hostile alive" % [
		player_lineage.lineage_name,
		player_lineage.epoch,
		adaptation_summary,
		player_lineage.score,
		selected_units.size(),
		friendly_alive,
		enemy_alive,
	]

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
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color("152019"), true)

	var grid_color := Color("243329")
	var x: float = 0.0
	while x <= MAP_SIZE.x:
		draw_line(Vector2(x, 0), Vector2(x, MAP_SIZE.y), grid_color, 1.0)
		x += GRID_SIZE

	var y: float = 0.0
	while y <= MAP_SIZE.y:
		draw_line(Vector2(0, y), Vector2(MAP_SIZE.x, y), grid_color, 1.0)
		y += GRID_SIZE

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

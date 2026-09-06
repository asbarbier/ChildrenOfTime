class_name RTSEncounterController
extends Node

signal encounter_finished(victory: bool, report: Dictionary)

@export var hostile_kill_points: int = 250
@export var survivor_points: int = 150
@export var victory_bonus: int = 2000
@export var time_bonus_max: int = 1000
@export var time_bonus_window: float = 120.0

var player_team_id: int = 0
var hostile_team_id: int = 0
var lineage: RTSLineageState
var tracked_units: Array[RTSUnit] = []

var active: bool = false
var elapsed_seconds: float = 0.0
var initial_friendly_count: int = 0
var initial_hostile_count: int = 0

func configure(
	player_team: int,
	hostile_team: int,
	player_lineage: RTSLineageState,
	encounter_units: Array[RTSUnit]
) -> void:
	player_team_id = player_team
	hostile_team_id = hostile_team
	lineage = player_lineage
	tracked_units.clear()

	for unit in encounter_units:
		if unit == null:
			continue
		tracked_units.append(unit)
		if not unit.died.is_connected(_on_unit_died):
			unit.died.connect(_on_unit_died)

	initial_friendly_count = _count_alive_units(player_team_id)
	initial_hostile_count = _count_alive_units(hostile_team_id)
	elapsed_seconds = 0.0
	active = initial_friendly_count > 0 and initial_hostile_count > 0

func _process(delta: float) -> void:
	if active:
		elapsed_seconds += delta

func _on_unit_died(_unit: RTSUnit) -> void:
	if not active:
		return
	_evaluate_outcome()

func _evaluate_outcome() -> void:
	var friendly_alive: int = _count_alive_units(player_team_id)
	var hostile_alive: int = _count_alive_units(hostile_team_id)

	if hostile_alive <= 0 and friendly_alive > 0:
		_finish_encounter(true, friendly_alive, hostile_alive)
	elif friendly_alive <= 0:
		_finish_encounter(false, friendly_alive, hostile_alive)

func _finish_encounter(victory: bool, friendly_alive: int, hostile_alive: int) -> void:
	if not active:
		return

	active = false

	var hostiles_defeated: int = maxi(0, initial_hostile_count - hostile_alive)
	var kill_points: int = hostiles_defeated * hostile_kill_points
	var survival_points: int = friendly_alive * survivor_points
	var completion_points: int = victory_bonus if victory else 0
	var time_points: int = _calculate_time_bonus(victory)
	var encounter_score: int = kill_points + survival_points + completion_points + time_points

	if lineage != null:
		lineage.add_score(encounter_score)
		var history_text: String = "Eastern Basin: %s — %d survived, %d rivals defeated, +%d score" % [
			"Victory" if victory else "Extinction",
			friendly_alive,
			hostiles_defeated,
			encounter_score,
		]
		lineage.record_history(history_text)

	var report: Dictionary = {
		"victory": victory,
		"friendly_alive": friendly_alive,
		"initial_friendly_count": initial_friendly_count,
		"hostiles_defeated": hostiles_defeated,
		"initial_hostile_count": initial_hostile_count,
		"kill_points": kill_points,
		"survival_points": survival_points,
		"completion_points": completion_points,
		"time_points": time_points,
		"elapsed_seconds": elapsed_seconds,
		"encounter_score": encounter_score,
		"lineage_score": lineage.score if lineage != null else encounter_score,
	}
	encounter_finished.emit(victory, report)

func _calculate_time_bonus(victory: bool) -> int:
	if not victory or time_bonus_window <= 0.0:
		return 0

	var remaining_ratio: float = 1.0 - clampf(elapsed_seconds / time_bonus_window, 0.0, 1.0)
	return int(round(float(time_bonus_max) * remaining_ratio))

func _count_alive_units(team_id: int) -> int:
	var count: int = 0
	for unit in tracked_units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.is_alive() and unit.is_on_team(team_id):
			count += 1
	return count

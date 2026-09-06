class_name RTSAIController
extends Node

@export var think_interval: float = 0.65
@export var aggro_radius: float = 520.0

var command_controller: RTSCommandController
var controlled_team_id: int = 0
var think_remaining: float = 0.0

func configure(controller: RTSCommandController, team_id: int) -> void:
	command_controller = controller
	controlled_team_id = team_id
	think_remaining = think_interval

func _process(delta: float) -> void:
	if command_controller == null or controlled_team_id <= 0:
		return

	think_remaining = maxf(0.0, think_remaining - delta)
	if think_remaining > 0.0:
		return

	think_remaining = think_interval
	_think()

func _think() -> void:
	for node in get_tree().get_nodes_in_group("rts_units"):
		if not node is RTSUnit:
			continue

		var unit := node as RTSUnit
		if not unit.is_alive() or not unit.is_on_team(controlled_team_id):
			continue

		# Don't stomp an order that is already executing successfully.
		if (
			(unit.current_intent == RTSUnit.Intent.ATTACK or unit.current_intent == RTSUnit.Intent.CHASE)
			and unit.is_valid_attack_target(unit.attack_target)
		):
			continue

		if unit.current_intent != RTSUnit.Intent.IDLE:
			continue

		var target := _find_nearest_hostile(unit)
		if target == null:
			continue

		var attackers: Array[RTSUnit] = [unit]
		command_controller.issue_attack_order(attackers, target)

func _find_nearest_hostile(unit: RTSUnit) -> RTSUnit:
	var nearest: RTSUnit = null
	var nearest_distance: float = aggro_radius

	for node in get_tree().get_nodes_in_group("rts_units"):
		if not node is RTSUnit:
			continue

		var candidate := node as RTSUnit
		if not unit.is_valid_attack_target(candidate):
			continue

		var distance: float = unit.global_position.distance_to(candidate.global_position)
		if distance > nearest_distance:
			continue

		nearest = candidate
		nearest_distance = distance

	return nearest

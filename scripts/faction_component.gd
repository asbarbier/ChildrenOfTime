class_name RTSFactionComponent
extends Node

@export var team_id: int = 0

func configure(value: int) -> void:
	team_id = value

func is_hostile_to(other: RTSFactionComponent) -> bool:
	if other == null:
		return false
	if team_id <= 0 or other.team_id <= 0:
		return false
	return team_id != other.team_id

func is_allied_with(other: RTSFactionComponent) -> bool:
	if other == null:
		return false
	if team_id <= 0 or other.team_id <= 0:
		return false
	return team_id == other.team_id

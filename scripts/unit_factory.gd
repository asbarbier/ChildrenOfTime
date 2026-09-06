class_name RTSUnitFactory
extends Node

const RTSUnitScript = preload("res://scripts/unit.gd")

func spawn_unit(
	parent: Node,
	base_definition: RTSUnitDefinition,
	lineage: RTSLineageState,
	unit_id_value: int,
	team_id: int,
	faction_color: Color,
	world_position: Vector2
) -> RTSUnit:
	if parent == null or base_definition == null:
		return null

	var resolved_definition: RTSUnitDefinition = base_definition
	if lineage != null:
		var lineage_definition: RTSUnitDefinition = lineage.resolve_unit_definition(base_definition)
		if lineage_definition != null:
			resolved_definition = lineage_definition

	var unit := RTSUnitScript.new() as RTSUnit
	unit.name = "%s_%02d" % [resolved_definition.display_name.replace(" ", "_"), unit_id_value]
	unit.unit_id = unit_id_value
	unit.position = world_position
	parent.add_child(unit)

	# This factory is the translation boundary between persistent organism data
	# and the runtime RTS actor. RTSUnit never needs to know about lineage history.
	unit.move_speed = resolved_definition.move_speed
	unit.acceleration = resolved_definition.acceleration
	unit.radius = resolved_definition.radius
	unit.configure_visual(resolved_definition.body_texture, resolved_definition.visual_size)
	unit.configure_combat(
		resolved_definition.max_health,
		resolved_definition.attack_damage,
		resolved_definition.attack_range,
		resolved_definition.attack_cooldown
	)
	unit.configure_affiliation(team_id, faction_color)
	return unit

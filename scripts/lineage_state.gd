class_name RTSLineageState
extends Resource

@export var lineage_name: String = "Unnamed Lineage"
@export var epoch: int = 1
@export var score: int = 0
@export var adaptations: PackedStringArray = PackedStringArray()

func configure(name_value: String, epoch_value: int = 1) -> void:
	lineage_name = name_value
	epoch = maxi(epoch_value, 1)

func add_score(points: int) -> void:
	score += points

func has_adaptation(adaptation_id: String) -> bool:
	return adaptations.has(adaptation_id)

func add_adaptation(adaptation_id: String) -> void:
	if adaptation_id.is_empty() or has_adaptation(adaptation_id):
		return
	adaptations.append(adaptation_id)

func resolve_unit_definition(base_definition: RTSUnitDefinition) -> RTSUnitDefinition:
	if base_definition == null:
		return null

	# Build 9 deliberately resolves to an isolated copy without changing stats yet.
	# Build 10 can apply adaptation/epoch modifiers here without teaching RTSUnit
	# anything about evolutionary history.
	var resolved: RTSUnitDefinition = base_definition.duplicate(true) as RTSUnitDefinition
	return resolved

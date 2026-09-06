class_name RTSLineageState
extends Resource

@export var lineage_name: String = "Unnamed Lineage"
@export var epoch: int = 1
@export var score: int = 0
@export var adaptations: Array[RTSAdaptationDefinition] = []

func configure(name_value: String, epoch_value: int = 1) -> void:
	lineage_name = name_value
	epoch = maxi(epoch_value, 1)

func add_score(points: int) -> void:
	score += points

func has_adaptation(adaptation_id: String) -> bool:
	for adaptation in adaptations:
		if adaptation != null and adaptation.adaptation_id == adaptation_id:
			return true
	return false

func add_adaptation(adaptation: RTSAdaptationDefinition) -> void:
	if adaptation == null or adaptation.adaptation_id.is_empty():
		return
	if has_adaptation(adaptation.adaptation_id):
		return
	adaptations.append(adaptation)

func clear_adaptations() -> void:
	adaptations.clear()

func get_adaptation_summary() -> String:
	if adaptations.is_empty():
		return "Unadapted"

	var names := PackedStringArray()
	for adaptation in adaptations:
		if adaptation != null:
			names.append(adaptation.display_name)
	return ", ".join(names)

func resolve_unit_definition(base_definition: RTSUnitDefinition) -> RTSUnitDefinition:
	if base_definition == null:
		return null

	var resolved: RTSUnitDefinition = base_definition.duplicate(true) as RTSUnitDefinition
	if resolved == null:
		return null

	for adaptation in adaptations:
		if adaptation != null:
			adaptation.apply_to(resolved)

	return resolved

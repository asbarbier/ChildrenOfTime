class_name RTSMacroState
extends Resource

const EASTERN_BASIN_ID := "eastern_basin"
const CRADLE_NEST_ID := "cradle_nest"
const GLASS_FOREST_ID := "glass_forest"

@export var current_turn: int = 1
@export var elapsed_years: int = 0
@export var run_ended: bool = false
@export var regions: Array[RTSMacroRegionState] = []

func configure_epoch_one() -> void:
	current_turn = 1
	elapsed_years = 0
	run_ended = false
	regions.clear()

	_add_region(
		CRADLE_NEST_ID,
		"Cradle Nest",
		"The ancestral basin where the First Lineage became more than prey.",
		RTSMacroRegionState.Status.HOME
	)
	_add_region(
		GLASS_FOREST_ID,
		"Glass Forest",
		"A dense western biome of reflective growths and unknown ecological pressure.",
		RTSMacroRegionState.Status.UNKNOWN
	)
	_add_region(
		EASTERN_BASIN_ID,
		"Eastern Basin",
		"Rich hunting ground occupied by a rival lineage. Expansion will require adaptation.",
		RTSMacroRegionState.Status.CONTESTED
	)

func get_region(region_id: String) -> RTSMacroRegionState:
	for region in regions:
		if region != null and region.region_id == region_id:
			return region
	return null

func can_begin_encounter(region_id: String) -> bool:
	if run_ended:
		return false

	var region: RTSMacroRegionState = get_region(region_id)
	return region != null and region.status == RTSMacroRegionState.Status.CONTESTED

func apply_encounter_result(region_id: String, victory: bool) -> void:
	var region: RTSMacroRegionState = get_region(region_id)
	if region == null:
		return

	if victory:
		region.status = RTSMacroRegionState.Status.SECURED
		current_turn += 1
		elapsed_years += 1200
	else:
		region.status = RTSMacroRegionState.Status.LOST
		run_ended = true
		elapsed_years += 180

func _add_region(
	region_id: String,
	display_name: String,
	description: String,
	status: RTSMacroRegionState.Status
) -> void:
	var region := RTSMacroRegionState.new()
	region.configure(region_id, display_name, description, status)
	regions.append(region)

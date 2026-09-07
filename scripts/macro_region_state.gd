class_name RTSMacroRegionState
extends Resource

enum Status {
	UNKNOWN,
	HOME,
	CONTESTED,
	SECURED,
	LOST,
}

@export var region_id: String = ""
@export var display_name: String = "Region"
@export var description: String = ""
@export var status: Status = Status.UNKNOWN

func configure(
	id_value: String,
	name_value: String,
	description_value: String,
	status_value: Status
) -> void:
	region_id = id_value
	display_name = name_value
	description = description_value
	status = status_value

func get_status_name() -> String:
	match status:
		Status.UNKNOWN:
			return "UNKNOWN"
		Status.HOME:
			return "HOME"
		Status.CONTESTED:
			return "CONTESTED"
		Status.SECURED:
			return "SECURED"
		Status.LOST:
			return "LOST"
		_:
			return "UNKNOWN"

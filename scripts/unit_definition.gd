class_name RTSUnitDefinition
extends Resource

@export var definition_id: String = "unit"
@export var display_name: String = "Unit"

@export_category("Movement")
@export var move_speed: float = 190.0
@export var acceleration: float = 900.0
@export var radius: float = 14.0

@export_category("Combat")
@export var max_health: float = 100.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 72.0
@export var attack_cooldown: float = 0.75

@export_category("Metadata")
@export var tags: PackedStringArray = PackedStringArray()

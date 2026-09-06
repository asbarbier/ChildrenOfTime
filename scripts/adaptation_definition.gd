class_name RTSAdaptationDefinition
extends Resource

@export var adaptation_id: String = "adaptation"
@export var display_name: String = "Adaptation"
@export_multiline var description: String = ""
@export var required_tags: PackedStringArray = PackedStringArray()
@export var added_tags: PackedStringArray = PackedStringArray()

@export_category("Stat Modifiers")
@export var move_speed_multiplier: float = 1.0
@export var acceleration_multiplier: float = 1.0
@export var max_health_multiplier: float = 1.0
@export var attack_damage_multiplier: float = 1.0
@export var attack_range_multiplier: float = 1.0
@export var attack_cooldown_multiplier: float = 1.0
@export var radius_add: float = 0.0

@export_category("Visual")
@export var texture_override: Texture2D
@export var visual_size_multiplier: float = 1.0

func applies_to(definition: RTSUnitDefinition) -> bool:
	if definition == null:
		return false

	for required_tag in required_tags:
		if not definition.tags.has(required_tag):
			return false

	return true

func apply_to(definition: RTSUnitDefinition) -> void:
	if not applies_to(definition):
		return

	definition.move_speed = maxf(1.0, definition.move_speed * move_speed_multiplier)
	definition.acceleration = maxf(1.0, definition.acceleration * acceleration_multiplier)
	definition.max_health = maxf(1.0, definition.max_health * max_health_multiplier)
	definition.attack_damage = maxf(0.0, definition.attack_damage * attack_damage_multiplier)
	definition.attack_range = maxf(1.0, definition.attack_range * attack_range_multiplier)
	definition.attack_cooldown = maxf(0.05, definition.attack_cooldown * attack_cooldown_multiplier)
	definition.radius = maxf(4.0, definition.radius + radius_add)
	definition.visual_size *= maxf(0.25, visual_size_multiplier)

	if texture_override != null:
		definition.body_texture = texture_override

	for added_tag in added_tags:
		if not definition.tags.has(added_tag):
			definition.tags.append(added_tag)

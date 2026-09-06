class_name RTSObstacle
extends Node2D

@export var radius: float = 145.0

func _ready() -> void:
	add_to_group("rts_obstacles")
	queue_redraw()

func _draw() -> void:
	# Placeholder terrain obstacle: ugly on purpose, readable immediately.
	draw_circle(Vector2.ZERO, radius, Color("3b4237"))
	draw_circle(Vector2(-radius * 0.18, -radius * 0.16), radius * 0.72, Color("4c5547"))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color("697261"), 4.0)
	draw_circle(Vector2(radius * 0.28, -radius * 0.24), radius * 0.13, Color("30362d"))
	draw_circle(Vector2(-radius * 0.33, radius * 0.22), radius * 0.09, Color("30362d"))

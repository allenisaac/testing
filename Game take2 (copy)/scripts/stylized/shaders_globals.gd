extends Node
class_name ShaderGlobals

@export var wind_direction: Vector2 = Vector2(1.0, 0.25)
@export var wind_speed: float = 1.0
@export var wind_strength: float = 1.0

@export var main_light_direction: Vector3 = Vector3(-0.4, -1.0, -0.3).normalized()

var wind_time: float = 0.0


func _process(delta: float) -> void:
	wind_time += delta * wind_speed
	update_globals()


func update_globals() -> void:
	RenderingServer.global_shader_parameter_set("wind_time", wind_time)
	RenderingServer.global_shader_parameter_set("wind_direction", wind_direction.normalized())
	RenderingServer.global_shader_parameter_set("wind_strength", wind_strength)
	RenderingServer.global_shader_parameter_set("main_light_direction", main_light_direction.normalized())
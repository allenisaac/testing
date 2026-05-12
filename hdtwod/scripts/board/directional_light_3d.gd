
@tool
extends DirectionalLight3D

@onready var directional_light: DirectionalLight3D = $"."


@export var light_angle_x: float = -15.0:
	set(v):
		light_angle_x = v
		_update_light_rotation()

@export var light_angle_y: float = -50.0:
	set(v):
		light_angle_y = v
		_update_light_rotation()

func _update_light_rotation() -> void:
	rotation_degrees = Vector3(light_angle_x, light_angle_y, 0.0)

func _ready() -> void:
	_update_light_rotation()


# # Function to send directional light information to the shader
# func _process(_delta):
# 	if directional_light:
# 		# Get the world direction of the directional light
# 		var light_direction = directional_light.global_transform.basis.z.normalized()
# 		#print("light dir", light_direction)
		
# 		# Pass the light direction to the shader
# 		RenderingServer.global_shader_parameter_set("light_direction", light_direction)

class_name TerrainDirt
extends TerrainType

@export_group("Tile Surface")
@export var albedo1: Color = Color(0.47, 0.31, 0.17)

@export_subgroup("Albedo 2")
@export var albedo2_hsl: Vector3 = Vector3(-2.443064, -0.477273, 0.125) ## ΔHue°, ΔSaturation, ΔLightness relative to albedo1
@export var albedo2_noise: Texture2D = load("res://art/Albedo2.tres")
@export var albedo2_scale: float = 0.11
@export var albedo2_threshold: float = 0.2

@export_subgroup("Albedo 3")
@export var albedo3_hsl: Vector3 = Vector3(2.834994, -0.505747, 0.12) ## ΔHue°, ΔSaturation, ΔLightness relative to albedo1
@export var albedo3_noise: Texture2D = load("res://art/Albedo3.tres")
@export var albedo3_scale: float = 0.1
@export var albedo3_threshold: float = 0.5

@export_group("Toon Lighting")
@export var cuts: int = 5
@export var wrap: float = 0.0
@export var steepness: float = 1.0
@export var ambient_min: float = 0.15
@export var threshold_gradient_size: float = 0.2

@export_group("Tile Shape")
@export var height_offset: float = -0.05

@export_group("Tile Sides")
@export var side_albedo: Texture2D = load("res://art/grass_side.png")
@export var side_normal: Texture2D

func get_height_offset() -> float:
	return height_offset

func get_tile_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["tile_shader"]
	RenderUtils.apply_common_surface_params(mat, self)
	RenderUtils.attach_edge_detection_pass(mat)

	return mat


func get_side_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["tile_side_shader"]
	RenderUtils.apply_common_surface_params(mat, self)

	if side_albedo != null:
		mat.set_shader_parameter("side_albedo", side_albedo)
	if side_normal != null:
		mat.set_shader_parameter("side_normal", side_normal)

	return mat


func spawn_props(_parent: Node3D, _own_tiles: Dictionary, _shared: Dictionary) -> void:
	pass

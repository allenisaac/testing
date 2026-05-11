class_name RenderUtils
extends RefCounted

static func apply_common_surface_params(mat: ShaderMaterial, terrain: TerrainGrass) -> void:
	mat.set_shader_parameter("albedo1", terrain.albedo1)
	mat.set_shader_parameter("albedo2_hsl", terrain.albedo2_hsl)
	mat.set_shader_parameter("albedo2_noise", terrain.albedo2_noise)
	mat.set_shader_parameter("albedo2_scale", terrain.albedo2_scale)
	mat.set_shader_parameter("albedo2_threshold", terrain.albedo2_threshold)
	mat.set_shader_parameter("albedo3_hsl", terrain.albedo3_hsl)
	mat.set_shader_parameter("albedo3_noise", terrain.albedo3_noise)
	mat.set_shader_parameter("albedo3_scale", terrain.albedo3_scale)
	mat.set_shader_parameter("albedo3_threshold", terrain.albedo3_threshold)
	mat.set_shader_parameter("cuts", terrain.cuts)
	mat.set_shader_parameter("wrap", terrain.wrap)
	mat.set_shader_parameter("steepness", terrain.steepness)
	mat.set_shader_parameter("ambient_min", terrain.ambient_min)
	mat.set_shader_parameter("threshold_gradient_size", terrain.threshold_gradient_size)

static func attach_edge_detection_pass(mat: ShaderMaterial) -> void:
	var edge_mat := ShaderMaterial.new()
	edge_mat.shader = load("res://shaders/edge_detection.gdshader") as Shader
	mat.next_pass = edge_mat
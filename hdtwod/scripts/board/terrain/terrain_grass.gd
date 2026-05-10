## Grass terrain handler.
## Spawns toon-shaded grass tile surfaces and a MultiMesh of billboard grass blades.
## Configure all visual parameters in the inspector by assigning a TerrainGrass resource.
class_name TerrainGrass
extends TerrainType

const _BLADE_SPACING: float = 0.2

@export_group("Tile Surface")
@export var albedo1: Color = Color(0.44, 0.63, 0.0)
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

@export_group("Grass Blades")
@export var albedo_texture: Texture2D
@export var wind_noise: Texture2D
@export var threshold_gradient_size: float = 0.2
@export var blade_width: float = 0.12
@export var blade_height: float = 0.12
@export var blade_height_change: float = -1 * blade_height * 0.5
@export_subgroup("Accent 1")
@export var accent_texture1: Texture2D
@export var accent_albedo1: Color = Color(0.6, 0.71, 0.0) 
@export var accent_frequency1: float = 0.001
@export var accent_scale1: float = 1.3
@export var accent_height1: float = blade_height * accent_scale1 * 0.2
@export_subgroup("Accent 2")
@export var accent_texture2: Texture2D
@export var accent_albedo2: Color = Color(0.42, 0.6, 0.0) 
@export var accent_probability2: float = 0.01
@export var accent_scale2: float = 1.5
@export var accent_height2: float = blade_height * accent_scale2 * 0.2

@export_group("Tile Sides")
@export var side_albedo: Texture2D = load("res://art/grass_side.png")
@export var side_normal: Texture2D

@export_group("Grass Overhangs")
@export var overhang_texture: Texture2D = load("res://art/grass_overhang.png")
@export var overhang_width: float = (HexCoord.RADIUS * 7.0)/5.0
@export var overhang_depth: float = HexCoord.RADIUS * 0.48
@export var overhang_edge_depth: float = HexCoord.RADIUS
@export var overhang_y_lift: float = 0.01
@export var overhang_alpha_scissor_threshold: float = 0.5

func get_tile_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["tile_shader"]
	mat.set_shader_parameter("albedo1",           albedo1)
	mat.set_shader_parameter("albedo2_hsl",       albedo2_hsl)
	mat.set_shader_parameter("albedo2_noise",     albedo2_noise)
	mat.set_shader_parameter("albedo2_scale",     albedo2_scale)
	mat.set_shader_parameter("albedo2_threshold", albedo2_threshold)
	mat.set_shader_parameter("albedo3_hsl",       albedo3_hsl)
	mat.set_shader_parameter("albedo3_noise",     albedo3_noise)
	mat.set_shader_parameter("albedo3_scale",     albedo3_scale)
	mat.set_shader_parameter("albedo3_threshold", albedo3_threshold)
	mat.set_shader_parameter("cuts",              cuts)
	mat.set_shader_parameter("wrap",              wrap)
	mat.set_shader_parameter("steepness",         steepness)
	mat.set_shader_parameter("ambient_min",       ambient_min)
	mat.set_shader_parameter("threshold_gradient_size", threshold_gradient_size)

	var edge_mat := ShaderMaterial.new()
	edge_mat.shader = load("res://shaders/edge_detection.gdshader") as Shader
	mat.next_pass = edge_mat

	return mat


func get_side_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["tile_side_shader"]
	mat.set_shader_parameter("albedo1",           albedo1)
	mat.set_shader_parameter("albedo2_hsl",       albedo2_hsl)
	mat.set_shader_parameter("albedo2_noise",     albedo2_noise)
	mat.set_shader_parameter("albedo2_scale",     albedo2_scale)
	mat.set_shader_parameter("albedo2_threshold", albedo2_threshold)
	mat.set_shader_parameter("albedo3_hsl",       albedo3_hsl)
	mat.set_shader_parameter("albedo3_noise",     albedo3_noise)
	mat.set_shader_parameter("albedo3_scale",     albedo3_scale)
	mat.set_shader_parameter("albedo3_threshold", albedo3_threshold)
	mat.set_shader_parameter("cuts",              cuts)
	mat.set_shader_parameter("wrap",              wrap)
	mat.set_shader_parameter("steepness",         steepness)
	mat.set_shader_parameter("ambient_min",       ambient_min)
	mat.set_shader_parameter("threshold_gradient_size", threshold_gradient_size)
	if side_albedo != null:
		mat.set_shader_parameter("side_albedo", side_albedo)
	if side_normal != null:
		mat.set_shader_parameter("side_normal", side_normal)
	return mat


func spawn_props(parent: Node3D, own_tiles: Dictionary, shared: Dictionary) -> void:
	var blade_tex := albedo_texture
	if blade_tex == null:
		blade_tex = load("res://art/grassleaf.png") as Texture2D
	if blade_tex == null:
		push_error("TerrainGrass: albedo_texture not assigned and fallback path not found.")
		return

	var blade_wind := wind_noise
	if blade_wind == null:
		blade_wind = load("res://art/WindNoise.tres") as Texture2D

	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = shared["grass_shader"]
	grass_mat.set_shader_parameter("albedo_texture",          blade_tex)
	grass_mat.set_shader_parameter("wind_noise",              blade_wind)
	grass_mat.set_shader_parameter("blade_height_change",    blade_height_change)
	grass_mat.set_shader_parameter("albedo1",                 albedo1)
	grass_mat.set_shader_parameter("albedo2_hsl",             albedo2_hsl)
	grass_mat.set_shader_parameter("albedo2_noise",           albedo2_noise)
	grass_mat.set_shader_parameter("albedo2_scale",           albedo2_scale)
	grass_mat.set_shader_parameter("albedo2_threshold",       albedo2_threshold)
	grass_mat.set_shader_parameter("albedo3_hsl",             albedo3_hsl)
	grass_mat.set_shader_parameter("albedo3_noise",           albedo3_noise)
	grass_mat.set_shader_parameter("albedo3_scale",           albedo3_scale)
	grass_mat.set_shader_parameter("albedo3_threshold",       albedo3_threshold)
	grass_mat.set_shader_parameter("cuts",                    cuts)
	grass_mat.set_shader_parameter("wrap",                    wrap)
	grass_mat.set_shader_parameter("steepness",               steepness)
	grass_mat.set_shader_parameter("threshold_gradient_size", threshold_gradient_size)
	grass_mat.set_shader_parameter("accent_texture1",         accent_texture1 if accent_texture1 else load("res://art/accentleaf.png"))
	grass_mat.set_shader_parameter("accent_albedo1",          accent_albedo1)
	grass_mat.set_shader_parameter("accent_frequency1",       accent_frequency1)
	grass_mat.set_shader_parameter("accent_height1",          accent_height1)
	grass_mat.set_shader_parameter("accent_scale1",           accent_scale1)
	grass_mat.set_shader_parameter("accent_texture2",         accent_texture2 if accent_texture2 else load("res://art/accentleaf.png"))
	grass_mat.set_shader_parameter("accent_albedo2",          accent_albedo2)
	grass_mat.set_shader_parameter("accent_probability2",     accent_probability2)
	grass_mat.set_shader_parameter("accent_height2",          accent_height2)
	grass_mat.set_shader_parameter("accent_scale2",           accent_scale2)
	grass_mat.set_shader_parameter("ambient_min", ambient_min)

	GrassSpawner.new().spawn_for_board(parent, own_tiles, _BLADE_SPACING, grass_mat, blade_width, blade_height)

	var overhang_tex := overhang_texture
	if overhang_tex == null:
		overhang_tex = load("res://art/grass_overhang.png") as Texture2D

	if overhang_tex == null:
		push_warning("TerrainGrass: overhang_texture not assigned and fallback path not found; skipping overhangs.")
		return

	var overhang_mat := ShaderMaterial.new()
	overhang_mat.shader = shared["grass_overhang_shader"]
	overhang_mat.set_shader_parameter("albedo_texture", overhang_tex)
	overhang_mat.set_shader_parameter("albedo1", albedo1)
	overhang_mat.set_shader_parameter("albedo2_hsl", albedo2_hsl)
	overhang_mat.set_shader_parameter("albedo2_noise", albedo2_noise)
	overhang_mat.set_shader_parameter("albedo2_scale", albedo2_scale)
	overhang_mat.set_shader_parameter("albedo2_threshold", albedo2_threshold)
	overhang_mat.set_shader_parameter("albedo3_hsl", albedo3_hsl)
	overhang_mat.set_shader_parameter("albedo3_noise", albedo3_noise)
	overhang_mat.set_shader_parameter("albedo3_scale", albedo3_scale)
	overhang_mat.set_shader_parameter("albedo3_threshold", albedo3_threshold)
	overhang_mat.set_shader_parameter("cuts", cuts)
	overhang_mat.set_shader_parameter("wrap", wrap)
	overhang_mat.set_shader_parameter("steepness", steepness)
	overhang_mat.set_shader_parameter("ambient_min", ambient_min)
	overhang_mat.set_shader_parameter("threshold_gradient_size", threshold_gradient_size)
	overhang_mat.set_shader_parameter("alpha_scissor_threshold", overhang_alpha_scissor_threshold)

	OverhangSpawner.new().spawn_for_board(
		parent,
		own_tiles,
		overhang_mat,
		overhang_width,
		overhang_depth,
		overhang_edge_depth,
		overhang_y_lift
	)

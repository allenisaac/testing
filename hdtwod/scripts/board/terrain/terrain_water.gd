## Water terrain handler.
## Surface 0 = flat hex water surface  → water_surface.gdshader (get_tile_material)
## Surface 1 = irregular seafloor      → tile_surface.gdshader  (get_side_material)
## Collision is built from surface 1 only so raycasts reach the seafloor.
class_name TerrainWater
extends TerrainType

# ---------------------------------------------------------------------------
# Seafloor surface — shares the same @export properties read by
# RenderUtils.apply_common_surface_params(), so the seafloor looks like any
# other terrain type (dirt/rock palette, toon shading, etc.)
# ---------------------------------------------------------------------------

@export_group("Seafloor Surface")
@export var albedo1: Color = Color(0.28, 0.22, 0.14)

@export_subgroup("Albedo 2")
@export var albedo2_hsl: Vector3 = Vector3(5.0, -0.15, 0.08)
@export var albedo2_noise: Texture2D = load("res://art/Albedo2.tres")
@export var albedo2_scale: float = 0.18
@export var albedo2_threshold: float = 0.35

@export_subgroup("Albedo 3")
@export var albedo3_hsl: Vector3 = Vector3(-3.0, -0.10, -0.06)
@export var albedo3_noise: Texture2D = load("res://art/Albedo3.tres")
@export var albedo3_scale: float = 0.14
@export var albedo3_threshold: float = 0.6

@export_group("Seafloor Lighting")
@export var cuts: int = 4
@export var wrap: float = 0.0
@export var steepness: float = 1.0
@export var ambient_min: float = 0.1
@export var threshold_gradient_size: float = 0.2

# ---------------------------------------------------------------------------
# Water surface
# ---------------------------------------------------------------------------

@export_group("Water Surface")
@export var color_shallow: Color = Color(0.43, 0.74, 0.60, 0.50)
@export var color_deep:    Color = Color(0.29, 0.47, 0.42, 0.68)
@export var depth_max:     float = 1.2

@export_subgroup("Foam")
@export var foam_color:        Color = Color(0.95, 0.97, 1.0, .2)
@export var shoreline_foam_color:        Color = Color(0.72, 0.88, 0.82, 1.0)
@export var foam_max_distance: float = 0.4
@export var foam_min_distance: float = 0.3

@export_subgroup("Waves")
@export var surface_noise:        Texture2D = load("res://art/WaterNoise.tres")
@export var noise_scale:          float     = 0.9
@export var noise_cutoff:         float     = 0.57
@export var edge_noise_cutoff_min:  float   = 0.45
@export var edge_noise_cutoff_max:  float   = 0.55
@export var noise_scroll:           Vector2 = Vector2(0.03, 0.001)
@export var shoreline_noise_scroll: Vector2 = Vector2(0.03, 0.03)
@export var noise_distortion:     Texture2D = load("res://art/WaterDistortion.tres")
@export var noise_distortion_amt: float     = 0.5

@export_subgroup("Water Lighting")
@export var water_cuts:      int   = 3
@export var water_wrap:      float = 0.2
@export var water_steepness: float = 1.0
@export var water_ambient_min: float = 0.3

# ---------------------------------------------------------------------------
# Water decorators
# ---------------------------------------------------------------------------

@export_group("Water Decorators")
@export_subgroup("Reeds")
@export var reed_texture:      Texture2D = load("res://art/reed.png")
@export var reed_wind_noise:   Texture2D = load("res://art/WaterNoise.tres")
@export var reed_tint:         Color     = Color(0.55, 0.60, 0.22, 1.0)
@export var reed_spacing:      float     = 0.3
@export var reed_width:        float     = 0.2
@export var reed_height:       float     = 0.64
@export var reed_sway_angle:   float     = 3.0
@export var reed_idle_speed:   float     = 0.03
@export var reed_cast_shadows: bool      = true

# ---------------------------------------------------------------------------
# Tile shape
# ---------------------------------------------------------------------------

@export_group("Tile Shape")
@export var height_offset: float = -0.3
# ---------------------------------------------------------------------------
# TerrainType overrides
# ---------------------------------------------------------------------------

func get_height_offset() -> float:
	return height_offset


func use_seafloor_collision() -> bool:
	return true


func build_custom_tile_mesh(tiles: Dictionary, coord: Vector2i, shared: Dictionary) -> ArrayMesh:
	var elevation: int = int(tiles[coord].get("elevation", 0))
	var cache: Dictionary = shared.get("water_corner_cache", {})
	return WaterMeshBuilder.new().build_water_mesh(tiles, coord, elevation, height_offset, cache)


## Surface 0 — water surface (transparent, animated)
func get_tile_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["water_shader"] as Shader

	mat.set_shader_parameter("color_shallow",         color_shallow)
	mat.set_shader_parameter("color_deep",            color_deep)
	mat.set_shader_parameter("depth_max",             depth_max)
	mat.set_shader_parameter("foam_color",            foam_color)
	mat.set_shader_parameter("shoreline_foam_color",  shoreline_foam_color)
	mat.set_shader_parameter("foam_max_distance",     foam_max_distance)
	mat.set_shader_parameter("foam_min_distance",     foam_min_distance)
	mat.set_shader_parameter("surface_noise",       surface_noise)
	mat.set_shader_parameter("noise_scale",         noise_scale)
	mat.set_shader_parameter("noise_cutoff",           noise_cutoff)
	mat.set_shader_parameter("edge_noise_cutoff_min",  edge_noise_cutoff_min)
	mat.set_shader_parameter("edge_noise_cutoff_max",  edge_noise_cutoff_max)
	mat.set_shader_parameter("noise_scroll",           noise_scroll)
	mat.set_shader_parameter("shoreline_noise_scroll", shoreline_noise_scroll)
	mat.set_shader_parameter("noise_distortion",    noise_distortion)
	mat.set_shader_parameter("noise_distortion_amt", noise_distortion_amt)
	mat.set_shader_parameter("cuts",                water_cuts)
	mat.set_shader_parameter("wrap",                water_wrap)
	mat.set_shader_parameter("steepness",           water_steepness)
	mat.set_shader_parameter("ambient_min",         water_ambient_min)

	return mat


## Surface 1 — seafloor (opaque, uses standard terrain shader pipeline)
func get_side_material(shared: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared["tile_shader"] as Shader
	RenderUtils.apply_common_surface_params(mat, self)
	return mat


func spawn_props(parent: Node3D, own_tiles: Dictionary, shared: Dictionary) -> void:
	if reed_texture == null:
		return
	var billboard_shader := load("res://shaders/water_billboard.gdshader") as Shader
	if billboard_shader == null:
		push_error("TerrainWater: water_billboard.gdshader not found")
		return
	var mat := ShaderMaterial.new()
	mat.shader = billboard_shader
	mat.set_shader_parameter("albedo_texture",    reed_texture)
	mat.set_shader_parameter("albedo_tint",       reed_tint)
	mat.set_shader_parameter("wind_noise",        reed_wind_noise)
	mat.set_shader_parameter("sway_angle",        reed_sway_angle)
	mat.set_shader_parameter("idle_speed",        reed_idle_speed)
	mat.set_shader_parameter("cuts",              water_cuts)
	mat.set_shader_parameter("wrap",              water_wrap)
	mat.set_shader_parameter("steepness",         water_steepness)
	mat.set_shader_parameter("ambient_min",       water_ambient_min)

	var spawner := BillboardSpawner.new()
	spawner.spacing      = reed_spacing
	spawner.width        = reed_width
	spawner.height       = reed_height
	spawner.cast_shadows = reed_cast_shadows
	spawner.node_name    = "WaterReeds"
	spawner.spawn(parent, own_tiles, mat, shared["terrain_collision_mask"])

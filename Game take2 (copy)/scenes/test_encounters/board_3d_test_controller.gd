extends Node3D
class_name Board3DTestController


## --- data paths ---
@export var board_data_path: String = "res://data/boards/frog_village_test_01.json"
@export var terrain_defs_path: String = "res://data/terrain/terrain_definitions.json"
@export var biome_defs_path: String = "res://data/biomes/biome_definitions.json"

## --- generation config ---
@export var config: WorldGenVisualConfig
@export var hex_size: float = 48.0
@export var samples_per_hex: int = 4

## --- debug ---
@export var debug_mode: String = "height"
@export var show_debug_field: bool = true
@export var use_layered_terrain: bool = true

## --- material / mesh resources (old pipeline — kept for reference) ---
@export var terrain_material: ShaderMaterial
@export var grass_material: ShaderMaterial
@export var grass_mesh: Mesh

## --- scene references ---
@onready var board_3d_root: Node3D = $Board3DRoot
@onready var generated_terrain: MeshInstance3D = $Board3DRoot/GeneratedTerrain
@onready var generated_water: MeshInstance3D = $Board3DRoot/GeneratedWater
@onready var props_root: Node3D = $Board3DRoot/Props
@onready var debug_field_root: Node3D = $Board3DRoot/DebugField
@onready var debug_info_label: Label = $CanvasLayer/DebugInfoLabel

## --- new layered-terrain mesh nodes ---
var generated_water_floor: MeshInstance3D
var generated_mud: MeshInstance3D
var generated_grass: MeshInstance3D
var generated_water_surface: MeshInstance3D

## --- helpers (field / debug — kept) ---
var map_loader: MapLoader = MapLoader.new()
var terrain_field_builder: TerrainFieldBuilder = TerrainFieldBuilder.new()
var field_debug_visualizer: FieldDebugVisualizer = FieldDebugVisualizer.new()

## --- old pipeline helpers (kept for reference, not called when layered) ---
var terrain_mesh_generator: TerrainMeshGenerator = TerrainMeshGenerator.new()
var water_mesh_generator: WaterMeshGenerator = WaterMeshGenerator.new()
var terrain_control_map_builder: TerrainControlMapBuilder = TerrainControlMapBuilder.new()
var grass_scatter: GrassScatter = GrassScatter.new()

## --- new layered pipeline helpers ---
var region_mask_builder: RegionMaskBuilder = RegionMaskBuilder.new()
var region_contour_builder: RegionContourBuilder = RegionContourBuilder.new()
var layered_terrain_builder: LayeredTerrainBuilder = LayeredTerrainBuilder.new()
var water_surface_builder: WaterSurfaceBuilder = WaterSurfaceBuilder.new()

## --- runtime data ---
var board_data: Dictionary = {}
var field_data: Dictionary = {}
var mask_data: Dictionary = {}
var contour_data: Dictionary = {}


func _ready() -> void:
	print("controller ready")

	setup_systems()

	load_board_data()
	print("board loaded: ", not board_data.is_empty())
	if board_data.is_empty():
		push_error("Board data failed to load.")
		return

	build_field()
	print("post-build sample count: ", field_data.get("samples", []).size())
	print("post-build grid: ", field_data.get("grid_width", 0), " x ", field_data.get("grid_height", 0))
	if field_data.is_empty():
		push_error("Field data failed to build.")
		return

	if use_layered_terrain:
		build_layered_terrain()
	else:
		## Old pipeline path — kept for reference / comparison.
		build_terrain_mesh()
		build_water_mesh()
		apply_terrain_control_map()
		apply_config_to_materials()

	render_debug_field()
	update_debug_label()


func setup_systems() -> void:
	map_loader = MapLoader.new()
	terrain_field_builder = TerrainFieldBuilder.new(config)
	field_debug_visualizer = FieldDebugVisualizer.new()

	## Old pipeline (kept for fallback / reference).
	terrain_mesh_generator = TerrainMeshGenerator.new()
	water_mesh_generator = WaterMeshGenerator.new()
	terrain_control_map_builder = TerrainControlMapBuilder.new(config)
	grass_scatter = GrassScatter.new(config)

	## New layered pipeline.
	region_mask_builder = RegionMaskBuilder.new(config)
	region_contour_builder = RegionContourBuilder.new(config)
	layered_terrain_builder = LayeredTerrainBuilder.new(config)
	water_surface_builder = WaterSurfaceBuilder.new(config)

	apply_config_to_generators()
	_ensure_layer_nodes()


func apply_config_to_generators() -> void:
	if config == null:
		return

	terrain_field_builder.set_config(config)
	terrain_control_map_builder.set_config(config)
	grass_scatter.set_config(config)

	## Old pipeline generators.
	terrain_mesh_generator.height_visual_scale = config.height_visual_scale
	terrain_mesh_generator.uv_scale = config.terrain_uv_scale
	terrain_mesh_generator.min_inside_corners_to_render = config.min_inside_corners_to_render
	terrain_mesh_generator.skip_degenerate_triangles = true

	water_mesh_generator.main_water_weight_threshold = config.main_water_weight_threshold
	water_mesh_generator.waterline_height = config.waterline_height * config.height_visual_scale
	water_mesh_generator.waterline_tolerance = config.waterline_tolerance * config.height_visual_scale
	water_mesh_generator.mud_pool_weight_threshold = config.mud_pool_weight_threshold
	water_mesh_generator.mud_pool_height_tolerance = config.mud_pool_height_tolerance * config.height_visual_scale
	water_mesh_generator.mud_pool_max_water_weight = config.mud_pool_max_water_weight
	water_mesh_generator.mud_pool_negative_pocket_threshold = config.mud_pool_negative_pocket_threshold
	water_mesh_generator.mud_pool_bonus_strength = config.mud_pool_bonus_strength
	water_mesh_generator.allow_muddy_pools = config.allow_muddy_pools
	water_mesh_generator.iso_level = config.water_iso_level
	water_mesh_generator.uv_scale = config.water_uv_scale

	## New layered pipeline generators.
	region_mask_builder.set_config(config)
	region_contour_builder.set_config(config)
	layered_terrain_builder.set_config(config)
	water_surface_builder.set_config(config)

	field_debug_visualizer.marker_size = config.debug_marker_size
	field_debug_visualizer.draw_stride = config.debug_draw_stride
	field_debug_visualizer.height_visual_scale = config.height_visual_scale


func load_board_data() -> void:
	print("board path: ", board_data_path)
	print("terrain defs path: ", terrain_defs_path)
	print("biome defs path: ", biome_defs_path)

	board_data = map_loader.load_board_data_from_files(
		board_data_path,
		terrain_defs_path,
		biome_defs_path
	)

	print("loaded board_data: ", board_data)


func build_field() -> void:
	field_data = terrain_field_builder.build_field(
		board_data,
		hex_size,
		samples_per_hex
	)


func build_terrain_mesh() -> void:
	## OLD PIPELINE — kept for reference / fallback comparison.
	print("[old] building terrain mesh")
	if generated_terrain == null:
		push_error("GeneratedTerrain node not found.")
		return

	var terrain_mesh: ArrayMesh = terrain_mesh_generator.generate_terrain_mesh(field_data)
	generated_terrain.mesh = terrain_mesh
	print("[old] terrain mesh surfaces: ", terrain_mesh.get_surface_count())

	if terrain_material != null:
		generated_terrain.material_override = terrain_material
	else:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.25, 0.7, 0.25)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		generated_terrain.material_override = material


func build_water_mesh() -> void:
	## OLD PIPELINE — kept for reference / fallback comparison.
	print("[old] building water mesh")
	if generated_water == null:
		push_error("GeneratedWater node not found.")
		return

	var water_mesh: ArrayMesh = water_mesh_generator.generate_water_mesh(field_data, board_data)
	generated_water.mesh = water_mesh
	print("[old] water mesh surfaces: ", water_mesh.get_surface_count())

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.4, 0.8, 0.75)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	generated_water.material_override = material


# ===========================================================================
#  NEW LAYERED TERRAIN PIPELINE
# ===========================================================================

## Ensure the four new MeshInstance3D nodes exist under Board3DRoot.
## They are created at runtime so we don't have to modify the .tscn by hand.
func _ensure_layer_nodes() -> void:
	if board_3d_root == null:
		return

	generated_water_floor = _ensure_mesh_node("GeneratedWaterFloor")
	generated_mud = _ensure_mesh_node("GeneratedMud")
	generated_grass = _ensure_mesh_node("GeneratedGrass")
	generated_water_surface = _ensure_mesh_node("GeneratedWaterSurface")


func _ensure_mesh_node(node_name: String) -> MeshInstance3D:
	if board_3d_root.has_node(node_name):
		return board_3d_root.get_node(node_name) as MeshInstance3D

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	board_3d_root.add_child(mi)
	return mi


## Full layered-terrain generation pipeline.
func build_layered_terrain() -> void:
	print("")
	print("========================================")
	print("  LAYERED TERRAIN PIPELINE — START")
	print("========================================")

	## Hide old pipeline meshes when using layered path.
	if generated_terrain != null:
		generated_terrain.mesh = null
	if generated_water != null:
		generated_water.mesh = null

	## Step 1 — Region masks from the sample field.
	var sample_count: int = field_data.get("samples", []).size()
	var grid_w_pre: int = int(field_data.get("grid_width", 0))
	var grid_h_pre: int = int(field_data.get("grid_height", 0))
	print("")
	print("[Step 1] Building region masks from field (%d samples, %dx%d grid)" % [
		sample_count, grid_w_pre, grid_h_pre])
	mask_data = region_mask_builder.build_all_masks(field_data)
	var grid_w: int = int(mask_data.get("grid_width", 0))
	var grid_h: int = int(mask_data.get("grid_height", 0))

	## Step 2 — Extract contour polygons for each mask.
	print("")
	print("[Step 2] Extracting contour polygons via marching squares")
	var water_contours: Array[Dictionary] = region_contour_builder.build_contours(
		mask_data.get("water", []), field_data
	)
	var mud_contours: Array[Dictionary] = region_contour_builder.build_contours(
		mask_data.get("mud", []), field_data
	)
	var grass_contours: Array[Dictionary] = region_contour_builder.build_contours(
		mask_data.get("grass", []), field_data
	)
	contour_data = {
		"water": water_contours,
		"mud": mud_contours,
		"grass": grass_contours,
	}
	_log_contour_stats("water", water_contours)
	_log_contour_stats("mud", mud_contours)
	_log_contour_stats("grass", grass_contours)

	## Step 3 — Build layered meshes.
	print("")
	print("[Step 3] Building flat layer meshes at configured Y heights")
	var layer_meshes: Dictionary = layered_terrain_builder.build_all_layers(contour_data)

	_apply_layer_mesh(generated_water_floor, layer_meshes.get("water_floor"),
		_layer_color("layer_water_floor_color", Color(0.12, 0.18, 0.26, 1.0)))
	_log_mesh_assignment("GeneratedWaterFloor", generated_water_floor)

	_apply_layer_mesh(generated_mud, layer_meshes.get("mud"),
		_layer_color("layer_mud_color", Color(0.38, 0.28, 0.16, 1.0)))
	_log_mesh_assignment("GeneratedMud", generated_mud)

	_apply_layer_mesh(generated_grass, layer_meshes.get("grass"),
		_layer_color("layer_grass_color", Color(0.30, 0.52, 0.22, 1.0)))
	_log_mesh_assignment("GeneratedGrass", generated_grass)

	## Step 4 — Build water surface.
	print("")
	print("[Step 4] Building water surface mesh")
	var water_surface_mesh: ArrayMesh = water_surface_builder.build_water_surface(water_contours)
	if generated_water_surface != null:
		generated_water_surface.mesh = water_surface_mesh
		generated_water_surface.material_override = water_surface_builder.make_water_surface_material()
	_log_mesh_assignment("GeneratedWaterSurface", generated_water_surface)

	print("")
	print("========================================")
	print("  LAYERED TERRAIN PIPELINE — COMPLETE")
	print("  Layers: water_floor, mud, grass, water_surface")
	print("========================================")
	print("")


func _apply_layer_mesh(node: MeshInstance3D, mesh: ArrayMesh, color: Color) -> void:
	if node == null:
		return
	node.mesh = mesh
	var double_sided: bool = true
	if config != null:
		double_sided = not config.layer_backface_cull
	node.material_override = LayeredTerrainBuilder.make_placeholder_material(color, double_sided)


func _layer_color(property_name: String, fallback: Color) -> Color:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback


func _log_contour_stats(layer_name: String, contours: Array[Dictionary]) -> void:
	var total_verts: int = 0
	for c in contours:
		var verts: PackedVector2Array = c.get("vertices", PackedVector2Array())
		total_verts += verts.size()
	print("  [contours] %s: %d region(s), %d total vertices" % [
		layer_name, contours.size(), total_verts])


func _log_mesh_assignment(node_name: String, node: MeshInstance3D) -> void:
	if node == null:
		print("  [mesh] %s: NODE MISSING" % node_name)
		return
	if node.mesh == null:
		print("  [mesh] %s: no mesh assigned (empty layer)" % node_name)
		return
	var mesh: ArrayMesh = node.mesh as ArrayMesh
	if mesh == null:
		print("  [mesh] %s: mesh is not ArrayMesh" % node_name)
		return
	var surface_count: int = mesh.get_surface_count()
	var has_material: bool = node.material_override != null
	print("  [mesh] %s: %d surface(s), material=%s" % [
		node_name, surface_count, "yes" if has_material else "NO"])


# ===========================================================================
#  OLD PIPELINE — control map / materials (kept for fallback)
# ===========================================================================

func apply_terrain_control_map() -> void:
	if field_data.is_empty():
		return

	var control_texture: ImageTexture = terrain_control_map_builder.build_control_texture(field_data)
	var bounds: Dictionary = field_data.get("bounds", {})

	if terrain_material != null:
		terrain_material.set_shader_parameter("control_map", control_texture)
		terrain_material.set_shader_parameter(
			"field_min_xz",
			Vector2(bounds.get("min_x", 0.0), bounds.get("min_z", 0.0))
		)
		terrain_material.set_shader_parameter(
			"field_max_xz",
			Vector2(bounds.get("max_x", 1.0), bounds.get("max_z", 1.0))
		)

	if grass_material != null:
		grass_material.set_shader_parameter("control_map", control_texture)
		grass_material.set_shader_parameter(
			"field_min_xz",
			Vector2(bounds.get("min_x", 0.0), bounds.get("min_z", 0.0))
		)
		grass_material.set_shader_parameter(
			"field_max_xz",
			Vector2(bounds.get("max_x", 1.0), bounds.get("max_z", 1.0))
		)


func apply_config_to_materials() -> void:
	if config == null:
		return

	if terrain_material != null:
		terrain_material.set_shader_parameter("grass_color_a", config.terrain_grass_color_a)
		terrain_material.set_shader_parameter("grass_color_b", config.terrain_grass_color_b)
		terrain_material.set_shader_parameter("mud_color_a", config.terrain_mud_color_a)
		terrain_material.set_shader_parameter("mud_color_b", config.terrain_mud_color_b)
		terrain_material.set_shader_parameter("clearing_color_a", config.terrain_clearing_color_a)
		terrain_material.set_shader_parameter("clearing_color_b", config.terrain_clearing_color_b)

		terrain_material.set_shader_parameter("wet_tint_color", config.terrain_wet_tint_color)
		terrain_material.set_shader_parameter("wet_tint_strength", config.terrain_wet_tint_strength)

		terrain_material.set_shader_parameter("patch_noise_scale", config.terrain_patch_noise_scale)
		terrain_material.set_shader_parameter("patch_noise_strength", config.terrain_patch_noise_strength)
		terrain_material.set_shader_parameter("zone_edge_noise_scale", config.terrain_zone_edge_noise_scale)
		terrain_material.set_shader_parameter("zone_blend_strength", config.terrain_zone_blend_strength)
		terrain_material.set_shader_parameter("secondary_blend_threshold", config.terrain_secondary_blend_threshold)

		terrain_material.set_shader_parameter("light_wrap", config.terrain_light_wrap)
		terrain_material.set_shader_parameter("shadow_strength", config.terrain_shadow_strength)
		terrain_material.set_shader_parameter("roughness_value", config.terrain_roughness_value)
		terrain_material.set_shader_parameter("cel_steps", config.terrain_cel_steps)
		terrain_material.set_shader_parameter("cel_softness", config.terrain_cel_softness)

	if grass_material != null:
		grass_material.set_shader_parameter("grass_tint_a", config.grass_tint_a)
		grass_material.set_shader_parameter("grass_tint_b", config.grass_tint_b)
		grass_material.set_shader_parameter("mud_tint", config.grass_mud_tint)
		grass_material.set_shader_parameter("clearing_tint", config.grass_clearing_tint)

		grass_material.set_shader_parameter("alpha_cutoff", config.grass_alpha_cutoff)
		grass_material.set_shader_parameter("wind_amplitude", config.grass_wind_amplitude)
		grass_material.set_shader_parameter("wind_frequency", config.grass_wind_frequency)
		grass_material.set_shader_parameter("height_sway_bias", config.grass_height_sway_bias)
		grass_material.set_shader_parameter("color_noise_scale", config.grass_color_noise_scale)
		grass_material.set_shader_parameter("color_variation_strength", config.grass_color_variation_strength)


# ===========================================================================
#  OLD PIPELINE — grass scatter (kept for fallback)
# ===========================================================================

func ensure_debug_grass_mesh() -> void:
	if grass_mesh == null:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2(0.35, 0.8)
		grass_mesh = quad


func build_grass_scatter() -> void:
	print("building grass scatter")

	if props_root == null:
		push_warning("No Props root found.")
		return

	ensure_debug_grass_mesh()

	if grass_mesh == null:
		push_warning("Grass scatter skipped: missing grass mesh.")
		return

	if grass_material == null:
		push_warning("Grass scatter skipped: missing grass material.")
		return

	grass_scatter.scatter_grass(
		field_data,
		props_root,
		grass_mesh,
		grass_material
	)

	print("props children after scatter: ", props_root.get_child_count())


# ===========================================================================
#  DEBUG / UI
# ===========================================================================

func render_debug_field() -> void:
	if debug_field_root == null:
		return

	field_debug_visualizer.clear_debug(debug_field_root)

	if show_debug_field:
		field_debug_visualizer.render_field(
			field_data,
			debug_field_root,
			debug_mode
		)


func update_debug_label() -> void:
	if debug_info_label == null:
		return

	var sample_count: int = field_data.get("samples", []).size()
	var mode_label: String = "LAYERED" if use_layered_terrain else "OLD"
	debug_info_label.text = (
		"Pipeline: " + mode_label + "\n" +
		"Debug Mode: " + debug_mode + "\n" +
		"Samples: " + str(sample_count) + "\n" +
		"Marker Size: " + str(field_debug_visualizer.marker_size) + "\n" +
		"Stride: " + str(field_debug_visualizer.draw_stride) + "\n" +
		"Show Debug Field: " + str(show_debug_field) + "\n" +
		"Keys: 1-6 mode, [ ] size, - = stride, 0 toggle debug, L toggle pipeline"
	)


func rebuild_visuals() -> void:
	if use_layered_terrain:
		build_layered_terrain()
	else:
		build_terrain_mesh()
		build_water_mesh()
		apply_terrain_control_map()
		apply_config_to_materials()

	render_debug_field()
	update_debug_label()


func clear_grass() -> void:
	if props_root == null:
		return

	for child in props_root.get_children():
		if child is MultiMeshInstance3D and child.name == "GrassBillboards":
			child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_1:
		debug_mode = "inside_board"
	elif event.keycode == KEY_2:
		debug_mode = "nearest_coord"
	elif event.keycode == KEY_3:
		debug_mode = "weight:water_weight"
	elif event.keycode == KEY_4:
		debug_mode = "weight:mud_weight"
	elif event.keycode == KEY_5:
		debug_mode = "weight:grass_weight"
	elif event.keycode == KEY_6:
		debug_mode = "height"
	elif event.keycode == KEY_BRACKETLEFT:
		field_debug_visualizer.marker_size = max(0.05, field_debug_visualizer.marker_size - 0.05)
	elif event.keycode == KEY_BRACKETRIGHT:
		field_debug_visualizer.marker_size += 0.05
	elif event.keycode == KEY_MINUS:
		field_debug_visualizer.draw_stride += 1
	elif event.keycode == KEY_EQUAL:
		field_debug_visualizer.draw_stride = max(1, field_debug_visualizer.draw_stride - 1)
	elif event.keycode == KEY_0:
		show_debug_field = not show_debug_field
	elif event.keycode == KEY_L:
		use_layered_terrain = not use_layered_terrain
		rebuild_visuals()
		return
	else:
		return

	render_debug_field()
	update_debug_label()
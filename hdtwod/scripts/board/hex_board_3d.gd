class_name HexBoard3D
extends Node3D
const TERRAIN_PLACEMENT_LAYER: int = 2
const TERRAIN_COLLISION_MASK: int = 1 << 1

@export var map_file: String = "res://data/maps/test_map.json"

@export var show_debug_directions: bool = false
@export var debug_direction_tile: Vector2i = Vector2i(0, 0)
@export var debug_marker_height: float = 2.5
@export var debug_marker_scale: float = 0.15

@export_group("Terrain")
@export var grass_terrain: TerrainGrass
@export var dirt_terrain: TerrainDirt
@export_group("")

@onready var tiles_root: Node3D = $Tiles

var mesh_builder := HexMeshBuilder.new()

var _tile_shader: Shader
var _grass_shader: Shader
var _tile_side_shader: Shader
var _grass_overhang_shader: Shader

var tiles: Dictionary = {}

# Registry mapping terrain_type string → handler instance.
var _terrain_types: Dictionary = {}

func _ready() -> void:
	_tile_shader = load("res://shaders/tile_surface.gdshader") as Shader
	_grass_shader = load("res://shaders/grass_billboard.gdshader") as Shader
	_tile_side_shader = load("res://shaders/tile_side.gdshader") as Shader
	_grass_overhang_shader = load("res://shaders/grass_overhang.gdshader") as Shader

	_terrain_types["grass"] = grass_terrain if grass_terrain else TerrainGrass.new()
	_terrain_types["dirt"] = dirt_terrain if dirt_terrain else TerrainDirt.new()
	_clear_tiles()
	_load_map_data()
	_spawn_board()

	if show_debug_directions:
		_spawn_debug_directions()

func _load_map_data() -> void:
	tiles.clear()

	if not FileAccess.file_exists(map_file):
		push_error("Map file not found: %s" % map_file)
		return

	var file := FileAccess.open(map_file, FileAccess.READ)
	if file == null:
		push_error("Failed to open map file: %s" % map_file)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_text)
	if parse_result != OK:
		push_error("Failed to parse JSON in map file: %s" % map_file)
		return

	var data = json.data
	if not data.has("tiles"):
		push_error("Map JSON missing 'tiles' array: %s" % map_file)
		return

	for tile_entry in data["tiles"]:
		var q: int = tile_entry["q"]
		var r: int = tile_entry["r"]
		var elevation: int = tile_entry.get("elevation", 0)
		var terrain_type: String = tile_entry.get("terrain_type", "grass")

		var raw_ramp_edges: Array = tile_entry.get("ramp_edges", [false, false, false, false, false, false])
		var ramp_edges: Array[bool] = []
		for value in raw_ramp_edges:
			ramp_edges.append(bool(value))

		tiles[Vector2i(q, r)] = {
			"elevation": elevation,
			"terrain_type": terrain_type,
			"ramp_edges": ramp_edges,
		}

func _spawn_board() -> void:
	var shared := _make_shared_params()
	shared["terrain_placement_layer"] = TERRAIN_PLACEMENT_LAYER

	var tiles_by_terrain: Dictionary = {}
	for coord in tiles.keys():
		var ttype: String = tiles[coord]["terrain_type"]
		if not tiles_by_terrain.has(ttype):
			tiles_by_terrain[ttype] = {}
		tiles_by_terrain[ttype][coord] = tiles[coord]

	for coord in tiles.keys():
		var tile_data: Dictionary = tiles[coord]
		var elevation: int = tile_data["elevation"]
		var terrain_type: String = tile_data["terrain_type"]
		var handler: TerrainType = _terrain_types.get(terrain_type, _terrain_types["grass"])

		var neighbor_elevations := BoardUtils.get_neighbor_elevations(tiles, coord)
		var neighbor_presence := BoardUtils.get_neighbor_presence(tiles, coord)
		var edge_types := BoardUtils.get_edge_types(tiles, coord)

		var mesh := mesh_builder.build_tile_mesh(
			elevation,
			neighbor_elevations,
			neighbor_presence,
			edge_types,
			handler.get_height_offset()
		)

		var mesh_instance := TileDebugInfo.new()
		mesh_instance.q = coord.x
		mesh_instance.r = coord.y
		mesh_instance.name = "Tile_%s_%s" % [coord.x, coord.y]
		mesh_instance.mesh = mesh
		mesh_instance.position = HexCoord.axial_to_world(coord, HexCoord.RADIUS)
		mesh_instance.set_surface_override_material(0, handler.get_tile_material(shared))

		var side_mat := handler.get_side_material(shared)
		if side_mat != null and mesh.get_surface_count() > 1:
			mesh_instance.set_surface_override_material(1, side_mat)

		tiles_root.add_child(mesh_instance)
		var body := StaticBody3D.new()
		body.name = "TileCollision_%s_%s" % [coord.x, coord.y]
		body.collision_layer = TERRAIN_COLLISION_MASK
		body.collision_mask = 0
		body.position = mesh_instance.position

		var collision_shape := CollisionShape3D.new()
		collision_shape.shape = mesh.create_trimesh_shape()
		body.add_child(collision_shape)

		tiles_root.add_child(body)

	for ttype in tiles_by_terrain.keys():
		var handler: TerrainType = _terrain_types.get(ttype, _terrain_types["grass"])
		handler.spawn_props(tiles_root, tiles_by_terrain[ttype], shared)

func _make_shared_params() -> Dictionary:
	return {
		"tile_shader": _tile_shader,
		"grass_shader": _grass_shader,
		"grass_overhang_shader": _grass_overhang_shader,
		"tile_side_shader": _tile_side_shader,
		"terrain_collision_mask": TERRAIN_COLLISION_MASK,
	}

func _clear_tiles() -> void:
	for child in tiles_root.get_children():
		child.queue_free()

func _spawn_debug_directions() -> void:
	if not tiles.has(debug_direction_tile):
		return

	var center_world := HexCoord.axial_to_world(debug_direction_tile, HexCoord.RADIUS)

	for i in range(6):
		var dir_world := HexCoord.axial_to_world(HexCoord.DIRECTION_VECTORS[i], HexCoord.RADIUS)
		var dir_flat := Vector2(dir_world.x, dir_world.z).normalized()
		var local_pos := Vector3(dir_flat.x, 0.0, dir_flat.y) * HexCoord.RADIUS * 0.75

		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(debug_marker_scale, debug_marker_scale, debug_marker_scale)
		marker.mesh = mesh
		marker.position = center_world + Vector3(local_pos.x, debug_marker_height, local_pos.z)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = _debug_direction_color(i)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mat
		marker.name = "DebugDir_%d" % i
		$Debug.add_child(marker)

		var label := Label3D.new()
		label.text = _debug_direction_name(i)
		label.position = center_world + Vector3(local_pos.x, debug_marker_height + 0.25, local_pos.z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 32
		$Debug.add_child(label)

func _debug_direction_name(i: int) -> String:
	match i:
		0: return "0 E"
		1: return "1 NE"
		2: return "2 NW"
		3: return "3 W"
		4: return "4 SW"
		5: return "5 SE"
		_: return str(i)

func _debug_direction_color(i: int) -> Color:
	match i:
		0: return Color.RED
		1: return Color.ORANGE
		2: return Color.YELLOW
		3: return Color.GREEN
		4: return Color.CYAN
		5: return Color.BLUE
		_: return Color.WHITE

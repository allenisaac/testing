class_name HexBoard3D
extends Node3D

@export var map_file: String = "res://data/maps/test_map.json"
@export var show_debug_directions: bool = false
@export var debug_direction_tile: Vector2i = Vector2i(0, 0)
@export var debug_marker_height: float = 2.5
@export var debug_marker_scale: float = 0.15

@export_group("Terrain")
@export var grass_terrain: TerrainGrass

@export_group("")
@onready var tiles_root: Node3D = $Tiles

var mesh_builder := HexMeshBuilder.new()
var _tile_shader : Shader
var _grass_shader: Shader
var _tile_side_shader: Shader
var _grass_overhang_shader: Shader
var tiles: Dictionary = {}

# Registry mapping terrain_type string → handler instance.
# Add new terrain types here as they are created.
var _terrain_types: Dictionary = {}


func _ready() -> void:
	_tile_shader  = load("res://shaders/tile_surface.gdshader") as Shader
	_grass_shader = load("res://shaders/grass_billboard.gdshader") as Shader
	_tile_side_shader = load("res://shaders/tile_side.gdshader") as Shader
	_grass_overhang_shader = load("res://shaders/grass_overhang.gdshader") as Shader
	_terrain_types["grass"] = grass_terrain if grass_terrain else TerrainGrass.new()
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

	# Group tiles by terrain_type so each handler can also batch its props.
	var tiles_by_terrain: Dictionary = {}
	for coord in tiles.keys():
		var ttype: String = tiles[coord]["terrain_type"]
		if not tiles_by_terrain.has(ttype):
			tiles_by_terrain[ttype] = {}
		tiles_by_terrain[ttype][coord] = tiles[coord]

	for coord in tiles.keys():
		var tile_data: Dictionary = tiles[coord]
		var elevation: int = tile_data["elevation"]
		var ramp_edges: Array[bool] = tile_data["ramp_edges"]
		var terrain_type: String = tile_data["terrain_type"]

		var handler: TerrainType = _terrain_types.get(terrain_type, _terrain_types["grass"])

		var mesh := mesh_builder.build_tile_mesh(
			elevation,
			_get_neighbor_elevations(coord),
			_get_neighbor_presence(coord),
			ramp_edges
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

	# Let each terrain handler spawn its own props (grass blades, rocks, etc.)
	# passing only the tiles that belong to it.
	for ttype in tiles_by_terrain.keys():
		var handler: TerrainType = _terrain_types.get(ttype, _terrain_types["grass"])
		handler.spawn_props(tiles_root, tiles_by_terrain[ttype], shared)


## Build the shared parameter dictionary passed to every terrain handler.
## Terrain-specific params (colors, textures, lighting) live on the terrain resource itself.
func _make_shared_params() -> Dictionary:
	return {
		"tile_shader":      _tile_shader,
		"grass_shader":     _grass_shader,
		"grass_overhang_shader": _grass_overhang_shader,
		"tile_side_shader": _tile_side_shader,
	}


func _get_neighbor_elevations(coord: Vector2i) -> Array[int]:
	var result: Array[int] = []

	for dir in range(6):
		var neighbor_coord := HexCoord.get_neighbor(coord, dir)

		if tiles.has(neighbor_coord):
			result.append(tiles[neighbor_coord]["elevation"])
		else:
			result.append(0)

	return result


func _get_neighbor_presence(coord: Vector2i) -> Array[bool]:
	var result: Array[bool] = []

	for dir in range(6):
		var neighbor_coord := HexCoord.get_neighbor(coord, dir)
		result.append(tiles.has(neighbor_coord))

	return result


func _clear_tiles() -> void:
	for child in tiles_root.get_children():
		child.queue_free()

func _spawn_debug_directions() -> void:
	if not tiles.has(debug_direction_tile):
		return

	var center_world := HexCoord.axial_to_world(debug_direction_tile, HexCoord.RADIUS)

	for i in range(6):
		# Place markers in the actual neighbor direction, not at hex corners.
		# axial_to_world of the direction vector gives the world-space offset to
		# the neighbour; normalize it and scale to the desired display radius.
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

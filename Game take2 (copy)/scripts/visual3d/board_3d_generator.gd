extends Node3D
class_name Board3DGenerator

@onready var props_root: Node3D = $Board3DRoot/Props
@onready var generated_terrain: MeshInstance3D = $Board3DRoot/GeneratedTerrain
var terrain_chunk_library: TerrainChunkLibrary = TerrainChunkLibrary.new()


func generate_board(board_data: Dictionary, board_root: Node3D, hex_size: float) -> void:
	clear_board(board_root)

	var terrain_layer: Node3D = get_required_layer(board_root, "TerrainChunks")
	var water_layer: Node3D = get_required_layer(board_root, "WaterRegions")
	var props_layer: Node3D = get_required_layer(board_root, "Props")
	var features_layer: Node3D = get_required_layer(board_root, "Features")

	spawn_terrain_chunks(board_data, terrain_layer, hex_size)

	# These are placeholders for later systems
	apply_water_region_pass(board_data, water_layer, hex_size)
	apply_anchor_feature_pass(board_data, features_layer, hex_size)
	apply_prop_pass(board_data, props_layer, hex_size)


func clear_board(board_root: Node3D) -> void:
	var layer_names: Array[String] = ["TerrainChunks", "WaterRegions", "Props", "Features"]

	for layer_name in layer_names:
		if board_root.has_node(layer_name):
			var layer: Node3D = board_root.get_node(layer_name) as Node3D
			for child in layer.get_children():
				child.queue_free()


func get_required_layer(board_root: Node3D, layer_name: String) -> Node3D:
	if board_root.has_node(layer_name):
		return board_root.get_node(layer_name) as Node3D

	push_error("Board3DRoot is missing required layer: " + layer_name)
	return null


func spawn_terrain_chunks(board_data: Dictionary, terrain_layer: Node3D, hex_size: float) -> void:
	if terrain_layer == null:
		return

	var tiles: Array = board_data.get("tiles", [])
	for tile_data in tiles:
		if not (tile_data is Dictionary):
			continue

		spawn_chunk_for_tile(tile_data, terrain_layer, hex_size)


func spawn_chunk_for_tile(tile_data: Dictionary, terrain_layer: Node3D, hex_size: float) -> void:
	var chunk_scene: PackedScene = terrain_chunk_library.get_chunk_scene_for_tile(tile_data)
	if chunk_scene == null:
		return

	var chunk_instance: Node3D = chunk_scene.instantiate() as Node3D
	if chunk_instance == null:
		push_error("Failed to instantiate terrain chunk for tile: " + str(tile_data))
		return

	var coord: Vector2i = tile_data.get("coord", Vector2i.ZERO)
	var world_pos: Vector3 = HexCoords.to_world_3d(coord, hex_size)

	chunk_instance.position = world_pos
	chunk_instance.name = str(tile_data.get("terrain_id", "chunk")) + "_" + str(coord.x) + "_" + str(coord.y)

	terrain_layer.add_child(chunk_instance)


func apply_water_region_pass(_board_data: Dictionary, water_layer: Node3D, _hex_size: float) -> void:
	if water_layer == null:
		return

	# Placeholder for future:
	# - build connected water regions
	# - place shared water surfaces
	# - add lily pads or ripple overlays
	pass


func apply_anchor_feature_pass(board_data: Dictionary, features_layer: Node3D, _hex_size: float) -> void:
	if features_layer == null:
		return

	var anchors: Array = board_data.get("anchors", [])
	for anchor in anchors:
		if not (anchor is Dictionary):
			continue

		# Placeholder for future:
		# - place village center
		# - place hut clusters
		# - place pond features
		pass


func apply_prop_pass(_board_data: Dictionary, props_layer: Node3D, _hex_size: float) -> void:
	if props_layer == null:
		return

	# Placeholder for future:
	# - scatter reeds
	# - scatter mushrooms
	# - add decorative props
	pass
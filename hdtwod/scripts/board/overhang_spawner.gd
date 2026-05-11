class_name OverhangSpawner
extends RefCounted

const EDGE_TO_DIR := [0, 5, 4, 3, 2, 1]
const OVERHANG_NAME := "GrassOverhangs"

func spawn_for_board(
	parent: Node3D,
	tiles: Dictionary,
	material: Material,
	quad_width: float,
	quad_depth: float,
	edge_depth: float,
	y_lift: float = 0.01
) -> void:
	if tiles.is_empty():
		return
	if quad_width <= 0.0 or quad_depth <= 0.0 or edge_depth <= 0.0:
		return

	var positions: Array[Vector3] = []
	var y_rotations: Array[float] = []

	for coord in tiles.keys():
		var tile_data: Dictionary = tiles[coord]
		var tile_elevation: int = tile_data.get("elevation", 0)
		var tile_world: Vector3 = HexCoord.axial_to_world(coord, HexCoord.RADIUS)
		var top_y: float = HexCoord.elevation_to_height(tile_elevation) + y_lift

		var corners: Array[Vector3] = HexCoord.get_corner_positions(HexCoord.RADIUS)

		for edge_i in range(6):
			var dir: int = EDGE_TO_DIR[edge_i]
			var edge_type := BoardUtils.get_edge_type(tiles, coord, dir)
			if edge_type != BoardUtils.EdgeType.CLIFF:
				continue

			var next_i: int = (edge_i + 1) % 6
			var outer_a: Vector3 = corners[edge_i]
			var outer_b: Vector3 = corners[next_i]
			var edge_mid: Vector3 = (outer_a + outer_b) * 0.5
			var outward: Vector3 = Vector3(edge_mid.x, 0.0, edge_mid.z).normalized()

			var yaw: float = atan2(outward.x, outward.z)

			var inward_portion: float = edge_depth
			var outward_portion: float = quad_depth - edge_depth
			var center_shift: float = (outward_portion - inward_portion) * 0.5

			var origin: Vector3 = tile_world + Vector3(edge_mid.x, top_y, edge_mid.z)
			positions.append(origin)
			y_rotations.append(yaw)

	if positions.is_empty():
		return

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_width, quad_depth)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = positions.size()
	mm.mesh = quad

	for i in range(positions.size()):
		var flat_basis := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
		var yaw_basis := Basis(Vector3.UP, y_rotations[i])
		var basis := yaw_basis * flat_basis
		mm.set_instance_transform(i, Transform3D(basis, positions[i]))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = OVERHANG_NAME
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mmi)





func _is_cliff_edge(
	tiles: Dictionary,
	coord: Vector2i,
	dir: int,
	tile_elevation: int
) -> bool:
	var neighbor_coord := HexCoord.get_neighbor(coord, dir)
	if not tiles.has(neighbor_coord):
		return true

	var neighbor_elevation: int = tiles[neighbor_coord].get("elevation", 0)
	return neighbor_elevation < tile_elevation
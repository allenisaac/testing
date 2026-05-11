class_name BoardUtils
extends RefCounted

enum EdgeType {
	FLAT,
	RAMP,
	CLIFF,
}

static func get_neighbor_coord(coord: Vector2i, dir: int) -> Vector2i:
	return HexCoord.get_neighbor(coord, dir)

static func has_neighbor(tiles: Dictionary, coord: Vector2i, dir: int) -> bool:
	return tiles.has(get_neighbor_coord(coord, dir))

static func get_neighbor_elevation(
	tiles: Dictionary,
	coord: Vector2i,
	dir: int,
	default_value: int = 0
) -> int:
	var neighbor_coord := get_neighbor_coord(coord, dir)
	if not tiles.has(neighbor_coord):
		return default_value
	return int(tiles[neighbor_coord].get("elevation", 0))

static func get_neighbor_presence(tiles: Dictionary, coord: Vector2i) -> Array[bool]:
	var result: Array[bool] = []
	for dir in range(6):
		result.append(has_neighbor(tiles, coord, dir))
	return result

static func get_neighbor_elevations(tiles: Dictionary, coord: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for dir in range(6):
		result.append(get_neighbor_elevation(tiles, coord, dir, 0))
	return result

static func is_ramp_edge(tile_data: Dictionary, dir: int) -> bool:
	var ramp_edges: Array = tile_data.get("ramp_edges", [])
	return dir >= 0 and dir < ramp_edges.size() and bool(ramp_edges[dir])

static func get_edge_type_from_values(
	tile_elevation: int,
	neighbor_elevation: int,
	has_neighbor: bool,
	is_ramp: bool
) -> int:
	if not has_neighbor:
		return EdgeType.CLIFF

	if neighbor_elevation < tile_elevation:
		if is_ramp:
			return EdgeType.RAMP
		return EdgeType.CLIFF

	return EdgeType.FLAT

static func get_edge_type(tiles: Dictionary, coord: Vector2i, dir: int) -> int:
	var tile_data: Dictionary = tiles[coord]
	var tile_elevation: int = int(tile_data.get("elevation", 0))
	var has_n := has_neighbor(tiles, coord, dir)
	var neighbor_elevation := get_neighbor_elevation(tiles, coord, dir, 0)
	var is_ramp := is_ramp_edge(tile_data, dir)

	return get_edge_type_from_values(
		tile_elevation,
		neighbor_elevation,
		has_n,
		is_ramp
	)

static func get_edge_types(tiles: Dictionary, coord: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for dir in range(6):
		result.append(get_edge_type(tiles, coord, dir))
	return result


static func get_edge_corner_indices(dir: int) -> Vector2i:
	match dir:
		0:
			return Vector2i(0, 1)
		5:
			return Vector2i(1, 2)
		4:
			return Vector2i(2, 3)
		3:
			return Vector2i(3, 4)
		2:
			return Vector2i(4, 5)
		1:
			return Vector2i(5, 0)
		_:
			return Vector2i(0, 1)


static func _point_in_quad(p: Vector2, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	return _point_in_triangle(p, a, b, c) or _point_in_triangle(p, a, c, d)

static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var v0: Vector2 = c - a
	var v1: Vector2 = b - a
	var v2: Vector2 = p - a

	var dot00: float = v0.dot(v0)
	var dot01: float = v0.dot(v1)
	var dot02: float = v0.dot(v2)
	var dot11: float = v1.dot(v1)
	var dot12: float = v1.dot(v2)

	var denom: float = dot00 * dot11 - dot01 * dot01
	if abs(denom) < 0.000001:
		return false

	var inv_denom: float = 1.0 / denom
	var u: float = (dot11 * dot02 - dot01 * dot12) * inv_denom
	var v: float = (dot00 * dot12 - dot01 * dot02) * inv_denom

	return u >= 0.0 and v >= 0.0 and (u + v) <= 1.0


static func get_surface_y_for_local_point(
	tiles: Dictionary,
	coord: Vector2i,
	local_xz: Vector2
) -> float:
	var tile_data: Dictionary = tiles[coord]
	var tile_elevation: int = int(tile_data.get("elevation", 0))
	var top_y: float = HexCoord.elevation_to_height(tile_elevation)

	var ramp_edges: Array = tile_data.get("ramp_edges", [])
	var ramp_dir: int = -1
	for dir in range(6):
		if dir < ramp_edges.size() and bool(ramp_edges[dir]):
			ramp_dir = dir
			break

	if ramp_dir == -1:
		return top_y

	var neighbor_coord: Vector2i = HexCoord.get_neighbor(coord, ramp_dir)
	if not tiles.has(neighbor_coord):
		return top_y

	var neighbor_elevation: int = int(tiles[neighbor_coord].get("elevation", tile_elevation))
	var neighbor_y: float = HexCoord.elevation_to_height(neighbor_elevation)

	if neighbor_y >= top_y:
		return top_y

	var outer: Array[Vector3] = HexCoord.get_corner_positions(HexCoord.RADIUS)
	var inner: Array[Vector3] = HexCoord.get_corner_positions(HexCoord.TOP_INSET)

	var edge_indices: Vector2i = get_edge_corner_indices(ramp_dir)
	var i0: int = edge_indices.x
	var i1: int = edge_indices.y

	var inner_a: Vector2 = Vector2(inner[i0].x, inner[i0].z)
	var inner_b: Vector2 = Vector2(inner[i1].x, inner[i1].z)
	var outer_a: Vector2 = Vector2(outer[i0].x, outer[i0].z)
	var outer_b: Vector2 = Vector2(outer[i1].x, outer[i1].z)

	if not _point_in_quad(local_xz, inner_a, inner_b, outer_b, outer_a):
		return top_y

	var edge_mid_3d: Vector3 = (outer[i0] + outer[i1]) * 0.5
	var outward: Vector2 = Vector2(edge_mid_3d.x, edge_mid_3d.z).normalized()

	var inner_mid: Vector2 = (inner_a + inner_b) * 0.5
	var outer_mid: Vector2 = (outer_a + outer_b) * 0.5

	var inner_d: float = inner_mid.dot(outward)
	var outer_d: float = outer_mid.dot(outward)
	var point_d: float = local_xz.dot(outward)

	if abs(outer_d - inner_d) < 0.000001:
		return top_y

	var t_raw: float = (point_d - inner_d) / (outer_d - inner_d)
	var t: float = clampf(t_raw, 0.0, 1.0)
	return lerpf(top_y, neighbor_y, t)

static func sample_surface_position(
	root: Node3D,
	world_x: float,
	world_z: float,
	collision_mask: int,
	cast_height: float = 1000.0
) -> Dictionary:
	var from: Vector3 = Vector3(world_x, cast_height, world_z)
	var to: Vector3 = Vector3(world_x, -cast_height, world_z)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	query.hit_from_inside = true

	var space_state: PhysicsDirectSpaceState3D = root.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)

	return result
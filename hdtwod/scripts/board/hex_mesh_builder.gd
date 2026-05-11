class_name HexMeshBuilder
extends RefCounted

const BORDER_WALL_DEPTH: float = HexCoord.ELEVATION_STEP

var _has_side := false

func build_tile_mesh(
	tile_elevation: int,
	neighbor_elevations: Array[int],
	neighbor_presence: Array[bool],
	edge_types: Array[int],
	height_offset: float = 0.0
) -> ArrayMesh:
	_has_side = false

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var st_side := SurfaceTool.new()
	st_side.begin(Mesh.PRIMITIVE_TRIANGLES)

	var top_y := HexCoord.elevation_to_height(tile_elevation) + height_offset
	var outer := HexCoord.get_corner_positions(HexCoord.RADIUS)
	var inner := HexCoord.get_corner_positions(HexCoord.TOP_INSET)

	_add_inner_top(st, inner, top_y)

	for i in range(6):
		var next_i := (i + 1) % 6

		# Corner-edge i (between corner[i] and corner[i+1]) faces direction (6 - i) % 6.
		var dir := (6 - i) % 6

		var neighbor_elevation := neighbor_elevations[dir]
		var has_neighbor := neighbor_presence[dir]
		var neighbor_y := HexCoord.elevation_to_height(neighbor_elevation)
		var edge_type := edge_types[dir]

		match edge_type:
			BoardUtils.EdgeType.FLAT:
				_add_flat_edge_sector(
					st,
					inner[i], inner[next_i],
					outer[i], outer[next_i],
					top_y
				)

			BoardUtils.EdgeType.CLIFF:
				var wall_bottom_y := neighbor_y if has_neighbor else top_y - BORDER_WALL_DEPTH
				_add_cliff_edge_sector(
					st,
					st_side,
					inner[i], inner[next_i],
					outer[i], outer[next_i],
					top_y,
					wall_bottom_y
				)

			BoardUtils.EdgeType.RAMP:
				# Previous corner-edge faces dir (7 - i) % 6
				# Next corner-edge faces dir (5 - i + 6) % 6
				var skip_left := edge_types[(7 - i) % 6] == BoardUtils.EdgeType.RAMP
				var skip_right := edge_types[(5 - i + 6) % 6] == BoardUtils.EdgeType.RAMP

				_add_ramp_edge_sector(
					st,
					st_side,
					inner[i], inner[next_i],
					outer[i], outer[next_i],
					top_y,
					neighbor_y,
					skip_left,
					skip_right
				)

	var mesh := st.commit()

	if _has_side:
		st_side.generate_tangents()
		st_side.commit(mesh)

	return mesh


func _add_inner_top(st: SurfaceTool, inner: Array[Vector3], top_y: float) -> void:
	var center := Vector3(0.0, top_y, 0.0)

	for i in range(6):
		var next_i := (i + 1) % 6
		var a := Vector3(inner[i].x, top_y, inner[i].z)
		var b := Vector3(inner[next_i].x, top_y, inner[next_i].z)

		_add_oriented_triangle(
			st,
			center, Vector2(0.5, 0.5),
			a, _top_uv(a, HexCoord.RADIUS),
			b, _top_uv(b, HexCoord.RADIUS),
			Vector3.UP
		)


func _add_flat_edge_sector(
	st: SurfaceTool,
	inner_a: Vector3,
	inner_b: Vector3,
	outer_a: Vector3,
	outer_b: Vector3,
	top_y: float
) -> void:
	var ia := Vector3(inner_a.x, top_y, inner_a.z)
	var ib := Vector3(inner_b.x, top_y, inner_b.z)
	var oa := Vector3(outer_a.x, top_y, outer_a.z)
	var ob := Vector3(outer_b.x, top_y, outer_b.z)

	_add_oriented_quad(
		st,
		ia, Vector2(0.0, 0.0),
		ib, Vector2(1.0, 0.0),
		ob, Vector2(1.0, 1.0),
		oa, Vector2(0.0, 1.0),
		Vector3.UP
	)


func _add_cliff_edge_sector(
	st: SurfaceTool,
	st_side: SurfaceTool,
	inner_a: Vector3,
	inner_b: Vector3,
	outer_a: Vector3,
	outer_b: Vector3,
	top_y: float,
	bottom_y: float
) -> void:
	var ia := Vector3(inner_a.x, top_y, inner_a.z)
	var ib := Vector3(inner_b.x, top_y, inner_b.z)
	var oa_top := Vector3(outer_a.x, top_y, outer_a.z)
	var ob_top := Vector3(outer_b.x, top_y, outer_b.z)
	var oa_bottom := Vector3(outer_a.x, bottom_y, outer_a.z)
	var ob_bottom := Vector3(outer_b.x, bottom_y, outer_b.z)

	_add_oriented_quad(
		st,
		ia, Vector2(0.0, 0.0),
		ib, Vector2(1.0, 0.0),
		ob_top, Vector2(1.0, 1.0),
		oa_top, Vector2(0.0, 1.0),
		Vector3.UP
	)

	var edge_mid := (outer_a + outer_b) * 0.5
	var outward := Vector3(edge_mid.x, 0.0, edge_mid.z).normalized()
	var wall_uv_v := (top_y - bottom_y) / HexCoord.ELEVATION_STEP

	_add_oriented_quad(
		st_side,
		oa_top, Vector2(0.0, 0.0),
		ob_top, Vector2(1.0, 0.0),
		ob_bottom, Vector2(1.0, wall_uv_v),
		oa_bottom, Vector2(0.0, wall_uv_v),
		outward
	)

	_has_side = true


func _add_ramp_edge_sector(
	st: SurfaceTool,
	st_side: SurfaceTool,
	inner_a: Vector3,
	inner_b: Vector3,
	outer_a: Vector3,
	outer_b: Vector3,
	top_y: float,
	bottom_y: float,
	skip_left_seam: bool,
	skip_right_seam: bool
) -> void:
	var ia := Vector3(inner_a.x, top_y, inner_a.z)
	var ib := Vector3(inner_b.x, top_y, inner_b.z)
	var oa := Vector3(outer_a.x, bottom_y, outer_a.z)
	var ob := Vector3(outer_b.x, bottom_y, outer_b.z)

	_add_oriented_quad(
		st,
		ia, _top_uv(ia, HexCoord.RADIUS),
		ib, _top_uv(ib, HexCoord.RADIUS),
		ob, _top_uv(ob, HexCoord.RADIUS),
		oa, _top_uv(oa, HexCoord.RADIUS),
		Vector3.UP
	)

	var seam_uv_v := (top_y - bottom_y) / HexCoord.ELEVATION_STEP

	if not skip_left_seam:
		var oa_top := Vector3(outer_a.x, top_y, outer_a.z)
		var left_outward := Vector3(-outer_a.z, 0.0, outer_a.x).normalized()

		_add_oriented_triangle(
			st_side,
			ia, Vector2(0.0, 0.0),
			oa_top, Vector2(1.0, 0.0),
			oa, Vector2(1.0, seam_uv_v),
			left_outward
		)

		_has_side = true

	if not skip_right_seam:
		var ob_top := Vector3(outer_b.x, top_y, outer_b.z)
		var right_outward := Vector3(outer_b.z, 0.0, -outer_b.x).normalized()

		_add_oriented_triangle(
			st_side,
			ib, Vector2(0.0, 0.0),
			ob_top, Vector2(1.0, 0.0),
			ob, Vector2(1.0, seam_uv_v),
			right_outward
		)

		_has_side = true


func _add_oriented_triangle(
	st: SurfaceTool,
	v0: Vector3, uv0: Vector2,
	v1: Vector3, uv1: Vector2,
	v2: Vector3, uv2: Vector2,
	target_normal: Vector3
) -> void:
	var normal := (v1 - v0).cross(v2 - v0)

	if normal.dot(target_normal) >= 0.0:
		_add_triangle(st, v0, uv0, v2, uv2, v1, uv1, target_normal)
	else:
		_add_triangle(st, v0, uv0, v1, uv1, v2, uv2, target_normal)


func _add_oriented_quad(
	st: SurfaceTool,
	v0: Vector3, uv0: Vector2,
	v1: Vector3, uv1: Vector2,
	v2: Vector3, uv2: Vector2,
	v3: Vector3, uv3: Vector2,
	target_normal: Vector3
) -> void:
	_add_oriented_triangle(st, v0, uv0, v1, uv1, v2, uv2, target_normal)
	_add_oriented_triangle(st, v0, uv0, v2, uv2, v3, uv3, target_normal)


func _add_triangle(
	st: SurfaceTool,
	v0: Vector3, uv0: Vector2,
	v1: Vector3, uv1: Vector2,
	v2: Vector3, uv2: Vector2,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	st.set_uv(uv0)
	st.add_vertex(v0)

	st.set_normal(normal)
	st.set_uv(uv1)
	st.add_vertex(v1)

	st.set_normal(normal)
	st.set_uv(uv2)
	st.add_vertex(v2)


func _top_uv(v: Vector3, radius: float) -> Vector2:
	var u := (v.x / (radius * 2.0)) + 0.5
	var vv := (v.z / (radius * 2.0)) + 0.5
	return Vector2(u, vv)
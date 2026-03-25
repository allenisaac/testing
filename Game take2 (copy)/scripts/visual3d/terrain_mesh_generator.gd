extends RefCounted
class_name TerrainMeshGenerator
## Converts a terrain field into an ArrayMesh.  All tunable knobs are read
## from a WorldGenVisualConfig resource via apply_config().


var height_visual_scale: float = 0.7
var uv_scale: float = 0.05
var min_inside_corners_to_render: int = 3
var cull_back_faces: bool = false
var skip_degenerate_triangles: bool = true
var degenerate_triangle_epsilon: float = 0.0001


## Copies relevant knobs from the centralised config resource.
func apply_config(config: WorldGenVisualConfig) -> void:
	height_visual_scale = config.height_visual_scale
	uv_scale = config.terrain_uv_scale
	min_inside_corners_to_render = config.min_inside_corners_to_render
	skip_degenerate_triangles = config.skip_degenerate_triangles
	degenerate_triangle_epsilon = config.degenerate_triangle_epsilon


func generate_terrain_mesh(field_data: Dictionary) -> ArrayMesh:
	var sample_lookup: Dictionary = build_sample_lookup(field_data)
	var grid_width: int = int(field_data.get("grid_width", 0))
	var grid_height: int = int(field_data.get("grid_height", 0))

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in range(grid_height - 1):
		for x in range(grid_width - 1):
			var a_key: Vector2i = Vector2i(x, z)
			var b_key: Vector2i = Vector2i(x + 1, z)
			var c_key: Vector2i = Vector2i(x, z + 1)
			var d_key: Vector2i = Vector2i(x + 1, z + 1)

			if not sample_lookup.has(a_key):
				continue
			if not sample_lookup.has(b_key):
				continue
			if not sample_lookup.has(c_key):
				continue
			if not sample_lookup.has(d_key):
				continue

			var a: Dictionary = sample_lookup[a_key]
			var b: Dictionary = sample_lookup[b_key]
			var c: Dictionary = sample_lookup[c_key]
			var d: Dictionary = sample_lookup[d_key]

			if not should_render_quad(a, b, c, d):
				continue

			var a_pos: Vector3 = sample_to_vertex(a)
			var b_pos: Vector3 = sample_to_vertex(b)
			var c_pos: Vector3 = sample_to_vertex(c)
			var d_pos: Vector3 = sample_to_vertex(d)

			var a_uv: Vector2 = sample_to_uv(a)
			var b_uv: Vector2 = sample_to_uv(b)
			var c_uv: Vector2 = sample_to_uv(c)
			var d_uv: Vector2 = sample_to_uv(d)

			# Triangle 1: a -> b -> c
			add_triangle(st, a_pos, b_pos, c_pos, a_uv, b_uv, c_uv)

			# Triangle 2: b -> d -> c
			add_triangle(st, b_pos, d_pos, c_pos, b_uv, d_uv, c_uv)

	st.generate_normals()
	st.generate_tangents()

	var mesh: ArrayMesh = st.commit()
	return mesh


func build_sample_lookup(field_data: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var samples: Array = field_data.get("samples", [])

	for sample in samples:
		if not (sample is Dictionary):
			continue

		var grid_x: int = int(sample.get("grid_x", -1))
		var grid_z: int = int(sample.get("grid_z", -1))

		if grid_x < 0 or grid_z < 0:
			continue

		lookup[Vector2i(grid_x, grid_z)] = sample

	return lookup


func should_render_quad(a: Dictionary, b: Dictionary, c: Dictionary, d: Dictionary) -> bool:
	var inside_count: int = 0

	if bool(a.get("is_inside_board", false)):
		inside_count += 1
	if bool(b.get("is_inside_board", false)):
		inside_count += 1
	if bool(c.get("is_inside_board", false)):
		inside_count += 1
	if bool(d.get("is_inside_board", false)):
		inside_count += 1

	return inside_count >= min_inside_corners_to_render


func sample_to_vertex(sample: Dictionary) -> Vector3:
	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	var height: float = float(sample.get("height", 0.0))

	return Vector3(
		world_pos.x,
		height * height_visual_scale,
		world_pos.z
	)


func sample_to_uv(sample: Dictionary) -> Vector2:
	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	return Vector2(world_pos.x * uv_scale, world_pos.z * uv_scale)


func add_triangle(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2
) -> void:
	if skip_degenerate_triangles:
		if is_degenerate_triangle(p0, p1, p2):
			return

	st.set_uv(uv0)
	st.add_vertex(p0)

	st.set_uv(uv1)
	st.add_vertex(p1)

	st.set_uv(uv2)
	st.add_vertex(p2)


func is_degenerate_triangle(a: Vector3, b: Vector3, c: Vector3) -> bool:
	var ab: Vector3 = b - a
	var ac: Vector3 = c - a
	var cross_result: Vector3 = ab.cross(ac)
	return cross_result.length() <= degenerate_triangle_epsilon
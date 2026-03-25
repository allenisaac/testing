extends RefCounted
class_name WaterMeshGenerator
## Generates a marching-squares water surface mesh from the terrain field.
## All tunable knobs are read from a WorldGenVisualConfig resource via
## apply_config().


# --- main water fill ---
var main_water_weight_threshold: float = 0.25
var waterline_height: float = -4.0
var waterline_tolerance: float = 0.6

# --- muddy pool fill ---
var mud_pool_weight_threshold: float = 0.15
var mud_pool_height_tolerance: float = 1.0
var mud_pool_max_water_weight: float = 0.5
var mud_pool_negative_pocket_threshold: float = -0.08
var mud_pool_bonus_strength: float = 0.35
var allow_muddy_pools: bool = true

# --- contour extraction ---
var iso_level: float = 0.5
var uv_scale: float = 0.05

# --- board constraints ---
var require_inside_board: bool = true


## Copies relevant knobs from the centralised config resource.
func apply_config(config: WorldGenVisualConfig) -> void:
	main_water_weight_threshold = config.main_water_weight_threshold
	waterline_height = config.waterline_height
	waterline_tolerance = config.waterline_tolerance

	mud_pool_weight_threshold = config.mud_pool_weight_threshold
	mud_pool_height_tolerance = config.mud_pool_height_tolerance
	mud_pool_max_water_weight = config.mud_pool_max_water_weight
	mud_pool_negative_pocket_threshold = config.mud_pool_negative_pocket_threshold
	mud_pool_bonus_strength = config.mud_pool_bonus_strength
	allow_muddy_pools = config.allow_muddy_pools

	iso_level = config.water_iso_level
	uv_scale = config.water_uv_scale
	require_inside_board = config.require_water_inside_board


func generate_water_mesh(field_data: Dictionary, board_data: Dictionary) -> ArrayMesh:
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

			if require_inside_board:
				if not is_inside_board(a) and not is_inside_board(b) and not is_inside_board(c) and not is_inside_board(d):
					continue

			var a_fill: float = compute_water_fill_value(a)
			var b_fill: float = compute_water_fill_value(b)
			var c_fill: float = compute_water_fill_value(c)
			var d_fill: float = compute_water_fill_value(d)

			var a_inside: bool = a_fill >= iso_level
			var b_inside: bool = b_fill >= iso_level
			var c_inside: bool = c_fill >= iso_level
			var d_inside: bool = d_fill >= iso_level

			if not a_inside and not b_inside and not c_inside and not d_inside:
				continue

			var a_pos: Vector3 = sample_to_water_vertex(a)
			var b_pos: Vector3 = sample_to_water_vertex(b)
			var c_pos: Vector3 = sample_to_water_vertex(c)
			var d_pos: Vector3 = sample_to_water_vertex(d)

			var polygon: Array[Vector3] = build_cell_polygon(
				a_pos, b_pos, c_pos, d_pos,
				a_fill, b_fill, c_fill, d_fill
			)

			if polygon.size() < 3:
				continue

			add_polygon_as_fan(st, polygon)

	st.generate_normals()
	return st.commit()


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


func compute_water_fill_value(sample: Dictionary) -> float:
	var water_weight: float = get_weight(sample, "water_weight")
	var mud_weight: float = get_weight(sample, "mud_weight")
	var height: float = get_height(sample)
	var mud_pocket_contrib: float = get_component(sample, "mud_pocket_contrib")

	var main_fill: float = 0.0
	if water_weight >= main_water_weight_threshold:
		var height_factor: float = 1.0
		if height > waterline_height:
			var over_height: float = height - waterline_height
			height_factor = clamp(1.0 - (over_height / max(0.0001, waterline_tolerance)), 0.0, 1.0)

		main_fill = water_weight * height_factor

	var puddle_fill: float = 0.0
	if allow_muddy_pools:
		if mud_weight >= mud_pool_weight_threshold and water_weight <= mud_pool_max_water_weight:
			var puddle_height_factor: float = 1.0
			if height > waterline_height:
				var over_height: float = height - waterline_height
				puddle_height_factor = clamp(1.0 - (over_height / max(0.0001, mud_pool_height_tolerance)), 0.0, 1.0)

			if mud_pocket_contrib <= mud_pool_negative_pocket_threshold:
				puddle_fill = mud_weight * puddle_height_factor * mud_pool_bonus_strength

	return clamp(max(main_fill, puddle_fill), 0.0, 1.0)


func build_cell_polygon(
	a_pos: Vector3, b_pos: Vector3, c_pos: Vector3, d_pos: Vector3,
	a_fill: float, b_fill: float, c_fill: float, d_fill: float
) -> Array[Vector3]:
	# Corner order around the cell polygon:
	# a -> b -> d -> c
	var corners: Array[Dictionary] = [
		{"pos": a_pos, "fill": a_fill},
		{"pos": b_pos, "fill": b_fill},
		{"pos": d_pos, "fill": d_fill},
		{"pos": c_pos, "fill": c_fill}
	]

	var polygon: Array[Vector3] = []

	for i in range(corners.size()):
		var current: Dictionary = corners[i]
		var next: Dictionary = corners[(i + 1) % corners.size()]

		var current_pos: Vector3 = current["pos"]
		var next_pos: Vector3 = next["pos"]
		var current_fill: float = float(current["fill"])
		var next_fill: float = float(next["fill"])

		var current_inside: bool = current_fill >= iso_level
		var next_inside: bool = next_fill >= iso_level

		if current_inside:
			polygon.append(current_pos)

		if current_inside != next_inside:
			var edge_point: Vector3 = interpolate_iso_crossing(
				current_pos, next_pos,
				current_fill, next_fill
			)
			polygon.append(edge_point)

	return polygon


func interpolate_iso_crossing(
	p1: Vector3,
	p2: Vector3,
	v1: float,
	v2: float
) -> Vector3:
	if abs(v2 - v1) < 0.0001:
		return p1.lerp(p2, 0.5)

	var t: float = (iso_level - v1) / (v2 - v1)
	t = clamp(t, 0.0, 1.0)
	return p1.lerp(p2, t)


func add_polygon_as_fan(st: SurfaceTool, polygon: Array[Vector3]) -> void:
	if polygon.size() < 3:
		return

	var center: Vector3 = Vector3.ZERO
	for point in polygon:
		center += point
	center /= float(polygon.size())

	var center_uv: Vector2 = world_to_uv(center)

	for i in range(1, polygon.size() - 1):
		var p0: Vector3 = center
		var p1: Vector3 = polygon[i]
		var p2: Vector3 = polygon[i + 1]

		st.set_uv(center_uv)
		st.add_vertex(p0)

		st.set_uv(world_to_uv(p1))
		st.add_vertex(p1)

		st.set_uv(world_to_uv(p2))
		st.add_vertex(p2)


func world_to_uv(world_pos: Vector3) -> Vector2:
	return Vector2(world_pos.x * uv_scale, world_pos.z * uv_scale)


func sample_to_water_vertex(sample: Dictionary) -> Vector3:
	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	return Vector3(world_pos.x, waterline_height, world_pos.z)


func is_inside_board(sample: Dictionary) -> bool:
	return bool(sample.get("is_inside_board", false))


func get_height(sample: Dictionary) -> float:
	return float(sample.get("height", 0.0))


func get_weight(sample: Dictionary, key: String) -> float:
	var weights: Dictionary = sample.get("terrain_weights", {})
	return float(weights.get(key, 0.0))


func get_component(sample: Dictionary, key: String) -> float:
	var components: Dictionary = sample.get("height_components", {})
	return float(components.get(key, 0.0))
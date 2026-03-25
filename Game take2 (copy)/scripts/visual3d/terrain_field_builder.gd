extends RefCounted
class_name TerrainFieldBuilder


const INVALID_COORD: Vector2i = Vector2i(-9999, -9999)

var config: WorldGenVisualConfig

var macro_noise: FastNoiseLite
var micro_noise: FastNoiseLite
var mud_pocket_noise: FastNoiseLite
var mud_crater_noise: FastNoiseLite


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource
	setup_noises()


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource
	setup_noises()


func setup_noises() -> void:
	macro_noise = FastNoiseLite.new()
	macro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	macro_noise.frequency = get_cfg("macro_noise_frequency", 0.015)

	micro_noise = FastNoiseLite.new()
	micro_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	micro_noise.frequency = get_cfg("micro_noise_frequency", 0.06)

	mud_pocket_noise = FastNoiseLite.new()
	mud_pocket_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mud_pocket_noise.frequency = get_cfg("mud_pocket_noise_frequency", 0.045)

	mud_crater_noise = FastNoiseLite.new()
	mud_crater_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mud_crater_noise.frequency = get_cfg("mud_crater_noise_frequency", 0.09)


func build_field(board_data: Dictionary, hex_size: float, samples_per_hex: int) -> Dictionary:
	var tile_lookup: Dictionary = build_tile_lookup(board_data)
	var bounds: Dictionary = compute_board_bounds(board_data, hex_size)

	var sample_spacing: float = hex_size / float(samples_per_hex)
	var min_x: float = bounds.get("min_x", 0.0)
	var max_x: float = bounds.get("max_x", 0.0)
	var min_z: float = bounds.get("min_z", 0.0)
	var max_z: float = bounds.get("max_z", 0.0)

	var grid_width: int = int(ceil((max_x - min_x) / sample_spacing)) + 1
	var grid_height: int = int(ceil((max_z - min_z) / sample_spacing)) + 1

	var samples: Array = []

	for z_index in range(grid_height):
		for x_index in range(grid_width):
			var world_x: float = min_x + float(x_index) * sample_spacing
			var world_z: float = min_z + float(z_index) * sample_spacing
			var world_pos: Vector3 = Vector3(world_x, 0.0, world_z)

			var influence: Dictionary = sample_board_influence(world_pos, hex_size, tile_lookup)
			var weights: Dictionary = influence.get("weights", {})
			var nearest_coord: Vector2i = influence.get("nearest_coord", INVALID_COORD)
			var is_inside_board: bool = influence.get("is_inside_board", false)

			var noise_values: Dictionary = compute_noise_values(world_pos)
			var shape_values: Dictionary = compute_shape_values(weights, noise_values)

			var height_parts: Dictionary = compute_height_layers(weights, noise_values, shape_values)

			var macro_height: float = float(height_parts.get("macro_height", 0.0))
			var detail_height: float = float(height_parts.get("detail_height", 0.0))
			var final_height: float = macro_height + detail_height

			samples.append({
				"grid_x": x_index,
				"grid_z": z_index,
				"world_pos": world_pos,
				"nearest_coord": nearest_coord,
				"is_inside_board": is_inside_board,
				"terrain_weights": weights,
				"noise": noise_values,
				"shape": shape_values,
				"height_components": height_parts.get("height_components", {}),
				"macro_height": macro_height,
				"detail_height": detail_height,
				"height": final_height
			})

	var field_data: Dictionary = {
		"bounds": bounds,
		"samples_per_hex": samples_per_hex,
		"sample_spacing": sample_spacing,
		"grid_width": grid_width,
		"grid_height": grid_height,
		"samples": samples
	}

	if get_cfg("enable_post_smoothing", true):
		apply_post_smoothing(field_data)

	return field_data


func build_tile_lookup(board_data: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var tiles: Array = board_data.get("tiles", [])

	for tile in tiles:
		if not (tile is Dictionary):
			continue

		var coord: Vector2i = tile.get("coord", INVALID_COORD)
		if coord == INVALID_COORD:
			continue

		lookup[coord] = tile

	return lookup


func compute_board_bounds(board_data: Dictionary, hex_size: float) -> Dictionary:
	var tiles: Array = board_data.get("tiles", [])

	if tiles.is_empty():
		return {
			"min_x": 0.0,
			"max_x": 0.0,
			"min_z": 0.0,
			"max_z": 0.0
		}

	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for tile in tiles:
		if not (tile is Dictionary):
			continue

		var coord: Vector2i = tile.get("coord", INVALID_COORD)
		if coord == INVALID_COORD:
			continue

		var world_pos: Vector3 = HexCoords.to_world_3d(coord, hex_size)
		min_x = min(min_x, world_pos.x)
		max_x = max(max_x, world_pos.x)
		min_z = min(min_z, world_pos.z)
		max_z = max(max_z, world_pos.z)

	var padding: float = hex_size * get_cfg("board_padding_multiplier", 1.5)

	return {
		"min_x": min_x - padding,
		"max_x": max_x + padding,
		"min_z": min_z - padding,
		"max_z": max_z + padding
	}


func sample_board_influence(world_pos: Vector3, hex_size: float, tile_lookup: Dictionary) -> Dictionary:
	var weights: Dictionary = {
		"water_weight": 0.0,
		"mud_weight": 0.0,
		"grass_weight": 0.0,
		"clearing_weight": 0.0,
		"structure_block_weight": 0.0
	}

	var nearest_coord: Vector2i = INVALID_COORD
	var nearest_distance: float = INF
	var total_influence: float = 0.0

	var influence_radius: float = hex_size * get_cfg("influence_radius_multiplier", 2.0)
	var board_membership_radius: float = hex_size * get_cfg("board_membership_radius_multiplier", 1.2)

	for coord in tile_lookup.keys():
		var tile_data: Dictionary = tile_lookup[coord]
		var tile_world: Vector3 = HexCoords.to_world_3d(coord, hex_size)
		var distance: float = world_pos.distance_to(tile_world)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_coord = coord

		if distance > influence_radius:
			continue

		var influence: float = max(0.0, 1.0 - (distance / influence_radius))
		if influence <= 0.0:
			continue

		total_influence += influence
		apply_tile_influence(weights, tile_data, influence)

	var is_inside_board: bool = nearest_distance <= board_membership_radius

	if total_influence > 0.0:
		for key in weights.keys():
			weights[key] = float(weights[key]) / total_influence

	return {
		"weights": weights,
		"nearest_coord": nearest_coord,
		"is_inside_board": is_inside_board
	}


func apply_tile_influence(weights: Dictionary, tile_data: Dictionary, influence: float) -> void:
	var terrain_id: String = str(tile_data.get("terrain_id", ""))
	var terrain_class: String = str(tile_data.get("terrain_class", ""))

	if terrain_class == "water":
		weights["water_weight"] += influence

	if terrain_id == "mud_flat":
		weights["mud_weight"] += influence

	if terrain_id == "marsh_grass" or terrain_id == "reed_bank":
		weights["grass_weight"] += influence

	if terrain_id == "village_clearing":
		weights["clearing_weight"] += influence
		weights["grass_weight"] += influence * 0.35

	if terrain_class == "structure" or terrain_id == "boardwalk" or terrain_id == "hut_platform":
		weights["structure_block_weight"] += influence


func compute_noise_values(world_pos: Vector3) -> Dictionary:
	return {
		"macro": macro_noise.get_noise_2d(world_pos.x, world_pos.z),
		"micro": micro_noise.get_noise_2d(world_pos.x, world_pos.z),
		"mud_pocket": mud_pocket_noise.get_noise_2d(world_pos.x, world_pos.z),
		"mud_crater": mud_crater_noise.get_noise_2d(world_pos.x, world_pos.z)
	}


func compute_shape_values(weights: Dictionary, noise_values: Dictionary) -> Dictionary:
	var water_weight: float = float(weights.get("water_weight", 0.0))
	var mud_weight: float = float(weights.get("mud_weight", 0.0))

	var water_depth_power: float = get_cfg("water_depth_power", 2.0)
	var water_depth_bias: float = pow(water_weight, water_depth_power)

	var mud_depth_bias: float = mud_weight * get_cfg("mud_depth_bias_strength", 0.7)

	var mud_pocket_noise_value: float = float(noise_values.get("mud_pocket", 0.0))
	var mud_pocket_threshold: float = get_cfg("mud_pocket_threshold", -0.2)
	var mud_pocket_bias: float = 0.0
	if mud_pocket_noise_value < mud_pocket_threshold:
		mud_pocket_bias = abs(mud_pocket_noise_value - mud_pocket_threshold)

	var mud_crater_noise_value: float = float(noise_values.get("mud_crater", 0.0))
	var mud_crater_threshold: float = get_cfg("mud_crater_threshold", 0.35)
	var mud_crater_bias: float = 0.0
	if mud_crater_noise_value > mud_crater_threshold:
		var t: float = (mud_crater_noise_value - mud_crater_threshold) / max(0.0001, 1.0 - mud_crater_threshold)
		mud_crater_bias = t * t

	var cliff_bias: float = 0.0
	var cliff_start_threshold: float = get_cfg("cliff_start_threshold", 0.45)
	if water_weight > cliff_start_threshold:
		cliff_bias = (water_weight - cliff_start_threshold) / max(0.0001, 1.0 - cliff_start_threshold)

	return {
		"water_depth_bias": water_depth_bias,
		"mud_depth_bias": mud_depth_bias,
		"mud_pocket_bias": mud_pocket_bias,
		"mud_crater_bias": clamp(mud_crater_bias, 0.0, 1.0),
		"cliff_bias": clamp(cliff_bias, 0.0, 1.0)
	}


func compute_height_layers(weights: Dictionary, noise_values: Dictionary, shape_values: Dictionary) -> Dictionary:
	var water_weight: float = float(weights.get("water_weight", 0.0))
	var mud_weight: float = float(weights.get("mud_weight", 0.0))
	var grass_weight: float = float(weights.get("grass_weight", 0.0))
	var clearing_weight: float = float(weights.get("clearing_weight", 0.0))
	var structure_block_weight: float = float(weights.get("structure_block_weight", 0.0))

	var macro_noise_value: float = float(noise_values.get("macro", 0.0))
	var micro_noise_value: float = float(noise_values.get("micro", 0.0))

	var water_depth_bias: float = float(shape_values.get("water_depth_bias", 0.0))
	var mud_depth_bias: float = float(shape_values.get("mud_depth_bias", 0.0))
	var mud_pocket_bias: float = float(shape_values.get("mud_pocket_bias", 0.0))
	var mud_crater_bias: float = float(shape_values.get("mud_crater_bias", 0.0))
	var cliff_bias: float = float(shape_values.get("cliff_bias", 0.0))

	# --- macro terrain layer ---
	var base_height: float = get_cfg("base_height_strength", 0.0)
	var macro_contrib: float = macro_noise_value * get_cfg("macro_noise_strength", 0.30) * (1.0 - clearing_weight * 0.7)
	var grass_contrib: float = grass_weight * get_cfg("grass_height_strength", 0.06)
	var clearing_contrib: float = clearing_weight * get_cfg("clearing_height_strength", 0.02)
	var mud_contrib: float = -mud_depth_bias * get_cfg("mud_depth_strength", 0.75)
	var water_contrib: float = -water_depth_bias * get_cfg("water_depth_strength", 1.35)
	var cliff_contrib: float = -cliff_bias * water_weight * get_cfg("cliff_depth_strength", 0.8)

	var macro_height: float = (
		base_height +
		macro_contrib +
		grass_contrib +
		clearing_contrib +
		mud_contrib +
		water_contrib +
		cliff_contrib
	)

	# flatten structures and clearings only on macro layer
	if structure_block_weight > 0.0:
		var structure_target_height: float = get_cfg("structure_target_height", -0.05)
		macro_height = lerp(macro_height, structure_target_height, structure_block_weight)

	if clearing_weight > 0.0:
		var clearing_target_height: float = get_cfg("clearing_target_height", 0.02)
		macro_height = lerp(macro_height, clearing_target_height, clearing_weight * 0.85)

	# --- detail layer ---
	var micro_contrib: float = micro_noise_value * (
		get_cfg("micro_noise_base_strength", 0.02) +
		mud_weight * get_cfg("micro_noise_mud_bonus_strength", 0.06)
	) * (1.0 - clearing_weight * 0.85)

	var mud_pocket_contrib: float = -mud_weight * mud_pocket_bias * get_cfg("mud_pocket_depth_strength", 1.0)
	var mud_crater_contrib: float = -mud_weight * mud_crater_bias * get_cfg("mud_crater_depth_strength", 1.35)

	var detail_height: float = micro_contrib + mud_pocket_contrib + mud_crater_contrib

	return {
		"macro_height": macro_height,
		"detail_height": detail_height,
		"height_components": {
			"base_height": base_height,
			"macro_contrib": macro_contrib,
			"grass_contrib": grass_contrib,
			"clearing_contrib": clearing_contrib,
			"mud_contrib": mud_contrib,
			"water_contrib": water_contrib,
			"cliff_contrib": cliff_contrib,
			"micro_contrib": micro_contrib,
			"mud_pocket_contrib": mud_pocket_contrib,
			"mud_crater_contrib": mud_crater_contrib
		}
	}


func apply_post_smoothing(field_data: Dictionary) -> void:
	var lookup: Dictionary = build_sample_lookup_from_field(field_data)
	var samples: Array = field_data.get("samples", [])

	for sample in samples:
		if not (sample is Dictionary):
			continue
		if not bool(sample.get("is_inside_board", false)):
			continue

		var grid_x: int = int(sample.get("grid_x", -1))
		var grid_z: int = int(sample.get("grid_z", -1))
		var coord_key: Vector2i = Vector2i(grid_x, grid_z)

		var current_macro: float = float(sample.get("macro_height", 0.0))
		var avg_neighbor_macro: float = get_average_neighbor_macro(coord_key, lookup, current_macro)

		var weights: Dictionary = sample.get("terrain_weights", {})
		var grass_weight: float = float(weights.get("grass_weight", 0.0))
		var clearing_weight: float = float(weights.get("clearing_weight", 0.0))
		var mud_weight: float = float(weights.get("mud_weight", 0.0))
		var water_weight: float = float(weights.get("water_weight", 0.0))

		var smoothing_strength: float = 0.0
		smoothing_strength += grass_weight * get_cfg("grass_smoothing_strength", 0.55)
		smoothing_strength += clearing_weight * get_cfg("clearing_smoothing_strength", 0.85)
		smoothing_strength += mud_weight * get_cfg("mud_smoothing_strength", 0.03)
		smoothing_strength += water_weight * get_cfg("water_smoothing_strength", 0.10)
		smoothing_strength = clamp(smoothing_strength, 0.0, 1.0)

		var smoothed_macro: float = lerp(current_macro, avg_neighbor_macro, smoothing_strength)

		if clearing_weight > 0.0:
			smoothed_macro = lerp(smoothed_macro, get_cfg("clearing_target_height", 0.02), clearing_weight * 0.65)

		sample["macro_height"] = smoothed_macro
		sample["height"] = smoothed_macro + float(sample.get("detail_height", 0.0))


func build_sample_lookup_from_field(field_data: Dictionary) -> Dictionary:
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


func get_average_neighbor_macro(coord_key: Vector2i, lookup: Dictionary, fallback_height: float) -> float:
	var total: float = 0.0
	var count: int = 0

	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var neighbor_key: Vector2i = Vector2i(coord_key.x + dx, coord_key.y + dz)
			if not lookup.has(neighbor_key):
				continue

			var sample: Dictionary = lookup[neighbor_key]
			if not bool(sample.get("is_inside_board", false)):
				continue

			total += float(sample.get("macro_height", fallback_height))
			count += 1

	if count == 0:
		return fallback_height

	return total / float(count)


func get_cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	return config.get(property_name) if config.get(property_name) != null else fallback
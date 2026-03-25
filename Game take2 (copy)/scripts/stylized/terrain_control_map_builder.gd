extends RefCounted
class_name TerrainControlMapBuilder


var config: WorldGenVisualConfig


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource


func build_control_texture(field_data: Dictionary) -> ImageTexture:
	var grid_width: int = int(field_data.get("grid_width", 0))
	var grid_height: int = int(field_data.get("grid_height", 0))
	var samples: Array = field_data.get("samples", [])

	var image: Image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	for sample in samples:
		if not (sample is Dictionary):
			continue

		var x: int = int(sample.get("grid_x", -1))
		var z: int = int(sample.get("grid_z", -1))

		if x < 0 or z < 0 or x >= grid_width or z >= grid_height:
			continue

		var raw_weights: Dictionary = sample.get("terrain_weights", {})
		var sharpened: Dictionary = sharpen_weights(raw_weights)

		var grass_weight: float = clamp(float(sharpened.get("grass_weight", 0.0)), 0.0, 1.0)
		var mud_weight: float = clamp(float(sharpened.get("mud_weight", 0.0)), 0.0, 1.0)
		var clearing_weight: float = clamp(float(sharpened.get("clearing_weight", 0.0)), 0.0, 1.0)
		var water_weight: float = clamp(float(sharpened.get("water_weight", 0.0)), 0.0, 1.0)

		image.set_pixel(x, z, Color(grass_weight, mud_weight, clearing_weight, water_weight))

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	return texture


func sharpen_weights(weights: Dictionary) -> Dictionary:
	var sharpness: float = get_cfg("control_map_sharpness", 2.75)
	var result: Dictionary = {}
	var total: float = 0.0

	var keys: Array[String] = [
		"grass_weight",
		"mud_weight",
		"clearing_weight",
		"water_weight"
	]

	for key in keys:
		var value: float = max(float(weights.get(key, 0.0)), 0.0)
		value = pow(value, sharpness)
		result[key] = value
		total += value

	if total > 0.0:
		for key in keys:
			result[key] = float(result[key]) / total

	# optional dominance boost so one terrain family owns a patch more clearly
	var dominant_boost: float = get_cfg("control_map_dominant_boost", 0.18)
	if dominant_boost > 0.0:
		apply_dominant_boost(result, dominant_boost)

	return result


func apply_dominant_boost(weights: Dictionary, boost_strength: float) -> void:
	var dominant_key: String = ""
	var dominant_value: float = -INF

	for key in weights.keys():
		var value: float = float(weights[key])
		if value > dominant_value:
			dominant_value = value
			dominant_key = str(key)

	if dominant_key == "":
		return

	weights[dominant_key] = float(weights[dominant_key]) + boost_strength

	var total: float = 0.0
	for key in weights.keys():
		total += float(weights[key])

	if total > 0.0:
		for key in weights.keys():
			weights[key] = float(weights[key]) / total


func get_cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	return config.get(property_name) if config.get(property_name) != null else fallback
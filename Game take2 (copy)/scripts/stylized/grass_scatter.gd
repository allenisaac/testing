extends RefCounted
class_name GrassScatter


var config: WorldGenVisualConfig
var placement_noise: FastNoiseLite


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource
	setup_noise()


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource
	setup_noise()


func setup_noise() -> void:
	placement_noise = FastNoiseLite.new()
	placement_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	placement_noise.frequency = get_cfg("grass_placement_noise_frequency", 0.12)


func scatter_grass(
	field_data: Dictionary,
	parent: Node3D,
	grass_mesh: Mesh,
	grass_material: Material
) -> MultiMeshInstance3D:
	if grass_mesh == null:
		push_warning("GrassScatter: grass_mesh is null.")
		return null

	if grass_material == null:
		push_warning("GrassScatter: grass_material is null.")
		return null

	clear_existing_grass(parent)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = grass_mesh

	var transforms: Array[Transform3D] = []
	var samples: Array = field_data.get("samples", [])

	var density_step: int = int(get_cfg("grass_density_step", 2))
	var index: int = 0

	for sample in samples:
		if not (sample is Dictionary):
			continue

		if density_step > 1 and (index % density_step) != 0:
			index += 1
			continue

		if not should_place_grass(sample):
			index += 1
			continue

		var transform: Transform3D = build_instance_transform(sample, index)
		transforms.append(transform)

		index += 1

	multimesh.instance_count = transforms.size()

	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "GrassBillboards"
	instance.multimesh = multimesh
	instance.material_override = grass_material
	parent.add_child(instance)

	return instance


func clear_existing_grass(parent: Node3D) -> void:
	for child in parent.get_children():
		if child is MultiMeshInstance3D and child.name == "GrassBillboards":
			child.queue_free()


func should_place_grass(sample: Dictionary) -> bool:
	if not bool(sample.get("is_inside_board", false)):
		return false

	var weights: Dictionary = sample.get("terrain_weights", {})

	var grass_weight: float = float(weights.get("grass_weight", 0.0))
	var clearing_weight: float = float(weights.get("clearing_weight", 0.0))
	var water_weight: float = float(weights.get("water_weight", 0.0))
	var mud_weight: float = float(weights.get("mud_weight", 0.0))

	if grass_weight < get_cfg("grass_weight_threshold", 0.45):
		return false

	if clearing_weight > get_cfg("grass_clearing_weight_max", 0.55):
		return false

	if water_weight > get_cfg("grass_water_weight_max", 0.35):
		return false

	if mud_weight > get_cfg("grass_mud_weight_max", 0.85):
		return false

	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	var noise_value: float = placement_noise.get_noise_2d(world_pos.x, world_pos.z)

	if noise_value < get_cfg("grass_placement_noise_threshold", -0.05):
		return false

	return true


func build_instance_transform(sample: Dictionary, seed_index: int) -> Transform3D:
	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	var height: float = float(sample.get("height", 0.0))
	var height_visual_scale: float = float(get_cfg("height_visual_scale", 0.35))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(str(world_pos) + "_" + str(seed_index))

	var scale_min: float = float(get_cfg("grass_scale_min", 0.75))
	var scale_max: float = float(get_cfg("grass_scale_max", 1.35))
	var scale_value: float = rng.randf_range(scale_min, scale_max)

	var basis: Basis = Basis.IDENTITY

	if bool(get_cfg("grass_random_y_rotation", true)):
		var rotation_angle: float = rng.randf_range(0.0, TAU)
		basis = Basis(Vector3.UP, rotation_angle)

	basis = basis.scaled(Vector3(scale_value, scale_value, scale_value))

	var y_offset: float = float(get_cfg("grass_y_offset", 0.02))
	var origin: Vector3 = Vector3(world_pos.x, (height * height_visual_scale) + y_offset, world_pos.z)

	return Transform3D(basis, origin)


func get_cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	return config.get(property_name) if config.get(property_name) != null else fallback
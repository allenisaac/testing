extends RefCounted
class_name FieldDebugVisualizer


var marker_size: float = 1.0
var marker_y_offset: float = 0.08
var draw_stride: int = 1
var height_visual_scale: float = 1.0


func render_field(field_data: Dictionary, parent: Node3D, debug_mode: String = "height") -> void:
	clear_debug(parent)

	var samples: Array = field_data.get("samples", [])
	var index: int = 0

	for sample in samples:
		if not (sample is Dictionary):
			continue

		if draw_stride > 1 and (index % draw_stride) != 0:
			index += 1
			continue

		var marker: MeshInstance3D = create_marker(sample, debug_mode)
		if marker != null:
			parent.add_child(marker)

		index += 1


func clear_debug(parent: Node3D) -> void:
	for child in parent.get_children():
		child.queue_free()


func create_marker(sample: Dictionary, debug_mode: String) -> MeshInstance3D:
	var world_pos: Vector3 = sample.get("world_pos", Vector3.ZERO)
	var height: float = float(sample.get("height", 0.0))

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = marker_size
	sphere_mesh.height = marker_size * 2.0
	mesh_instance.mesh = sphere_mesh

	mesh_instance.position = Vector3(
		world_pos.x,
		(height * height_visual_scale) + marker_y_offset,
		world_pos.z
	)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = get_sample_color(sample, debug_mode)
	mesh_instance.material_override = material

	return mesh_instance


func get_sample_color(sample: Dictionary, debug_mode: String) -> Color:
	if debug_mode == "height":
		return get_height_color(float(sample.get("height", 0.0)))

	if debug_mode == "inside_board":
		var is_inside_board: bool = bool(sample.get("is_inside_board", false))
		if is_inside_board:
			return Color(0.15, 0.95, 0.25)
		return Color(0.12, 0.12, 0.12)

	if debug_mode == "nearest_coord":
		return get_coord_hash_color(sample.get("nearest_coord", Vector2i.ZERO))

	if debug_mode.begins_with("weight:"):
		var key: String = debug_mode.trim_prefix("weight:")
		var value: float = get_nested_float(sample, "terrain_weights", key)
		return get_named_gradient_color("weight", key, value)

	if debug_mode.begins_with("noise:"):
		var key: String = debug_mode.trim_prefix("noise:")
		var value: float = get_nested_float(sample, "noise", key)
		return get_named_gradient_color("noise", key, value)

	if debug_mode.begins_with("shape:"):
		var key: String = debug_mode.trim_prefix("shape:")
		var value: float = get_nested_float(sample, "shape", key)
		return get_named_gradient_color("shape", key, value)

	if debug_mode.begins_with("component:"):
		var key: String = debug_mode.trim_prefix("component:")
		var value: float = get_nested_float(sample, "height_components", key)
		return get_named_gradient_color("component", key, value)

	return Color(1.0, 0.0, 1.0)


func get_nested_float(sample: Dictionary, section_name: String, key: String) -> float:
	var section: Variant = sample.get(section_name, {})
	if not (section is Dictionary):
		return 0.0

	return float(section.get(key, 0.0))


func get_height_color(height: float) -> Color:
	if height <= -1.2:
		return Color(0.05, 0.15, 0.65)
	if height <= -0.7:
		return Color(0.08, 0.35, 0.85)
	if height <= -0.25:
		return Color(0.20, 0.60, 0.90)
	if height <= 0.05:
		return Color(0.15, 0.72, 0.30)
	if height <= 0.25:
		return Color(0.50, 0.78, 0.25)
	return Color(0.78, 0.68, 0.35)


func get_named_gradient_color(section_type: String, key: String, value: float) -> Color:
	if section_type == "weight":
		return get_weight_color(key, value)

	if section_type == "noise":
		return get_noise_color(key, value)

	if section_type == "shape":
		return get_shape_color(key, value)

	if section_type == "component":
		return get_component_color(key, value)

	return Color(1.0, 0.0, 1.0)


func get_weight_color(key: String, value: float) -> Color:
	var clamped_value: float = clamp(value, 0.0, 1.0)

	if key == "water_weight":
		return Color(0.05, 0.20 + 0.60 * clamped_value, 0.90 * clamped_value + 0.10)

	if key == "mud_weight":
		return Color(0.25 + 0.45 * clamped_value, 0.16 + 0.25 * clamped_value, 0.08)

	if key == "grass_weight":
		return Color(0.10 + 0.25 * clamped_value, 0.35 + 0.55 * clamped_value, 0.10)

	if key == "structure_block_weight":
		return Color(0.40 + 0.45 * clamped_value, 0.40 + 0.30 * clamped_value, 0.12)

	return Color(clamped_value, clamped_value, clamped_value)


func get_noise_color(key: String, value: float) -> Color:
	var remapped: float = (clamp(value, -1.0, 1.0) + 1.0) * 0.5

	if key == "macro":
		return Color(0.15 + remapped * 0.75, 0.15 + remapped * 0.75, 0.95)

	if key == "micro":
		return Color(0.95, 0.15 + remapped * 0.75, 0.15 + remapped * 0.75)

	if key == "mud_pocket":
		return Color(0.35 + remapped * 0.45, 0.20 + remapped * 0.25, 0.10)

	return Color(remapped, remapped, remapped)


func get_shape_color(key: String, value: float) -> Color:
	var clamped_value: float = clamp(value, 0.0, 1.0)

	if key == "water_depth_bias":
		return Color(0.05, 0.25 + 0.50 * clamped_value, 0.80 + 0.20 * clamped_value)

	if key == "mud_depth_bias":
		return Color(0.30 + 0.40 * clamped_value, 0.18 + 0.20 * clamped_value, 0.08)

	if key == "mud_pocket_bias":
		return Color(0.60 + 0.35 * clamped_value, 0.25 + 0.25 * clamped_value, 0.10)

	if key == "cliff_bias":
		return Color(0.50 + 0.50 * clamped_value, 0.10, 0.10)

	return Color(clamped_value, clamped_value, clamped_value)


func get_component_color(key: String, value: float) -> Color:
	var remapped: float = (clamp(value, -2.0, 2.0) + 2.0) / 4.0

	if key == "water_contrib":
		return Color(0.05, 0.20 + remapped * 0.50, 0.90)

	if key == "mud_contrib":
		return Color(0.35 + remapped * 0.35, 0.20 + remapped * 0.20, 0.10)

	if key == "grass_contrib":
		return Color(0.10, 0.40 + remapped * 0.50, 0.10)

	if key == "mud_pocket_contrib":
		return Color(0.55 + remapped * 0.35, 0.20, 0.10)

	if key == "cliff_contrib":
		return Color(0.75 + remapped * 0.25, 0.10, 0.10)

	if key == "macro_contrib":
		return Color(0.25 + remapped * 0.65, 0.25 + remapped * 0.65, 0.95)

	if key == "micro_contrib":
		return Color(0.95, 0.25 + remapped * 0.65, 0.25 + remapped * 0.65)

	if key == "structure_contrib":
		return Color(0.75, 0.70, 0.25 + remapped * 0.40)

	if key == "base_height":
		return Color(0.75, 0.75, 0.75)

	return Color(remapped, remapped, remapped)


func get_coord_hash_color(coord: Vector2i) -> Color:
	var r: float = float(abs(coord.x * 37) % 255) / 255.0
	var g: float = float(abs(coord.y * 57) % 255) / 255.0
	var b: float = float(abs((coord.x + coord.y) * 91) % 255) / 255.0
	return Color(r, g, b)


func get_available_debug_modes(field_data: Dictionary) -> Array[String]:
	var modes: Array[String] = ["height", "inside_board", "nearest_coord"]

	var samples: Array = field_data.get("samples", [])
	if samples.is_empty():
		return modes

	var sample: Variant = samples[0]
	if not (sample is Dictionary):
		return modes

	add_modes_from_section(modes, sample, "terrain_weights", "weight:")
	add_modes_from_section(modes, sample, "noise", "noise:")
	add_modes_from_section(modes, sample, "shape", "shape:")
	add_modes_from_section(modes, sample, "height_components", "component:")

	return modes


func add_modes_from_section(modes: Array[String], sample: Dictionary, section_name: String, prefix: String) -> void:
	var section: Variant = sample.get(section_name, {})
	if not (section is Dictionary):
		return

	for key in section.keys():
		modes.append(prefix + str(key))
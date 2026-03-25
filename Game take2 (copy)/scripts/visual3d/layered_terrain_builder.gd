extends RefCounted
class_name LayeredTerrainBuilder
## Creates flat 3D mesh layers from region contour polygons.
##
## Each layer (water-floor, mud, grass) is placed at a configured Y height.
## Contour polygons are ear-clipped into triangle fans and emitted as an
## ArrayMesh.  This is the "simple flat planes" first pass — no extrusion,
## overhangs, or sculpted geometry yet.


var config: WorldGenVisualConfig


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Build a single flat ArrayMesh from an array of contour polygons placed at
## the given Y height.
## contours: Array[Dictionary] — each has "vertices": PackedVector2Array.
## y_level: float — Y position of the mesh plane.
func build_layer_mesh(contours: Array[Dictionary], y_level: float) -> ArrayMesh:
	var uv_scale: float = _cfg("layer_uv_scale", 0.05)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_geometry: bool = false

	for contour in contours:
		var verts_2d: PackedVector2Array = contour.get("vertices", PackedVector2Array())
		if verts_2d.size() < 3:
			continue

		var triangles: PackedInt32Array = _triangulate_polygon(verts_2d)
		if triangles.size() < 3:
			continue

		has_geometry = true

		for i in range(0, triangles.size(), 3):
			var i0: int = triangles[i]
			var i1: int = triangles[i + 1]
			var i2: int = triangles[i + 2]

			var p0: Vector3 = Vector3(verts_2d[i0].x, y_level, verts_2d[i0].y)
			var p1: Vector3 = Vector3(verts_2d[i1].x, y_level, verts_2d[i1].y)
			var p2: Vector3 = Vector3(verts_2d[i2].x, y_level, verts_2d[i2].y)

			st.set_uv(Vector2(p0.x * uv_scale, p0.z * uv_scale))
			st.add_vertex(p0)

			st.set_uv(Vector2(p1.x * uv_scale, p1.z * uv_scale))
			st.add_vertex(p1)

			st.set_uv(Vector2(p2.x * uv_scale, p2.z * uv_scale))
			st.add_vertex(p2)

	if not has_geometry:
		return ArrayMesh.new()

	st.generate_normals()
	return st.commit()


## Convenience: build all three solid layers and return them in a Dictionary.
## Keys: "water_floor", "mud", "grass" — values are ArrayMesh.
func build_all_layers(mask_contours: Dictionary) -> Dictionary:
	var water_y: float = _cfg("layer_water_floor_y", -0.45)
	var mud_y: float = _cfg("layer_mud_y", -0.12)
	var grass_y: float = _cfg("layer_grass_y", 0.0)

	var water_contours: Array[Dictionary] = mask_contours.get("water", [])
	var mud_contours: Array[Dictionary] = mask_contours.get("mud", [])
	var grass_contours: Array[Dictionary] = mask_contours.get("grass", [])

	return {
		"water_floor": build_layer_mesh(water_contours, water_y),
		"mud": build_layer_mesh(mud_contours, mud_y),
		"grass": build_layer_mesh(grass_contours, grass_y),
	}


# ---------------------------------------------------------------------------
#  Triangulation
# ---------------------------------------------------------------------------

## Use Godot's built-in Geometry2D ear-clip triangulator.
## Returns PackedInt32Array of triangle indices into the polygon.
func _triangulate_polygon(polygon: PackedVector2Array) -> PackedInt32Array:
	return Geometry2D.triangulate_polygon(polygon)


# ---------------------------------------------------------------------------
#  Placeholder materials
# ---------------------------------------------------------------------------

## Create a simple unshaded StandardMaterial3D for a layer.
static func make_placeholder_material(color: Color, double_sided: bool = true) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ---------------------------------------------------------------------------
#  Config helper
# ---------------------------------------------------------------------------

func _cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback

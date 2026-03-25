extends RefCounted
class_name WaterSurfaceBuilder
## Builds a transparent water-surface mesh from the water region contours.
##
## This is separate from the opaque water-floor layer: it sits at its own
## configured Y height and uses a semi-transparent material so the floor
## shows through.  For the first pass this is a flat polygon mesh — later it
## could receive animated vertex displacement, foam edges, etc.


var config: WorldGenVisualConfig


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Build a flat water-surface ArrayMesh from the water region contours.
func build_water_surface(water_contours: Array[Dictionary]) -> ArrayMesh:
	var y_level: float = _cfg("layer_water_surface_y", -0.18)
	var uv_scale: float = _cfg("layer_uv_scale", 0.05)

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var has_geometry: bool = false

	for contour in water_contours:
		var verts_2d: PackedVector2Array = contour.get("vertices", PackedVector2Array())
		if verts_2d.size() < 3:
			continue

		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(verts_2d)
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


## Create the default semi-transparent water surface material.
func make_water_surface_material() -> StandardMaterial3D:
	var color: Color = _cfg("layer_water_surface_color", Color(0.18, 0.38, 0.62, 0.65))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


# ---------------------------------------------------------------------------
#  Config helper
# ---------------------------------------------------------------------------

func _cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback

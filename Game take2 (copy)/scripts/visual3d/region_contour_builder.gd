extends RefCounted
class_name RegionContourBuilder
## Extracts region contour polygons from a scalar mask using marching squares.
##
## Input:  a flat Array[float] mask (grid_width * grid_height) plus field
##         metadata (bounds, sample_spacing).
## Output: an Array of contour polygon Dictionaries, each containing a
##         PackedVector2Array of world-space XZ vertices suitable for
##         triangulation.
##
## Optional Douglas-Peucker simplification is applied to reduce vertex count.
## Tiny islands below a minimum area are discarded.


var config: WorldGenVisualConfig


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Extract all closed contour polygons for a single mask layer.
## Returns Array[Dictionary] where each dict has:
##   "vertices": PackedVector2Array  — world XZ polygon ring (closed)
##   "area": float                   — signed polygon area (positive = CCW)
func build_contours(mask: Array[float], field_data: Dictionary) -> Array[Dictionary]:
	var grid_w: int = int(field_data.get("grid_width", 0))
	var grid_h: int = int(field_data.get("grid_height", 0))
	var bounds: Dictionary = field_data.get("bounds", {})
	var spacing: float = float(field_data.get("sample_spacing", 1.0))
	var min_x: float = float(bounds.get("min_x", 0.0))
	var min_z: float = float(bounds.get("min_z", 0.0))

	var iso: float = _cfg("contour_iso_level", 0.5)
	var simplify_tol: float = _cfg("contour_simplify_tolerance", 0.15)
	var min_area: float = _cfg("contour_min_area", 0.5)

	## 1. Build edge segments via marching squares.
	var segments: Array = _marching_squares(mask, grid_w, grid_h, iso, spacing, min_x, min_z)

	## 2. Chain loose segments into closed polygon rings.
	var rings: Array = _chain_segments(segments)

	## 3. Simplify, measure area, filter.
	var contours: Array[Dictionary] = []
	for ring in rings:
		var pts: PackedVector2Array = ring as PackedVector2Array
		if pts.size() < 3:
			continue

		if simplify_tol > 0.0:
			pts = _douglas_peucker(pts, simplify_tol)

		var area: float = _polygon_area(pts)
		if abs(area) < min_area:
			continue

		contours.append({
			"vertices": pts,
			"area": area,
		})

	return contours


# ---------------------------------------------------------------------------
#  Marching Squares
# ---------------------------------------------------------------------------

## Returns Array of [Vector2, Vector2] edge segments in world XZ space.
func _marching_squares(mask: Array[float], grid_w: int, grid_h: int,
		iso: float, spacing: float, origin_x: float, origin_z: float) -> Array:

	var segments: Array = []

	for gz in range(grid_h - 1):
		for gx in range(grid_w - 1):
			## Four corners of this cell: TL, TR, BR, BL
			var tl: float = mask[gz * grid_w + gx]
			var tr: float = mask[gz * grid_w + (gx + 1)]
			var br: float = mask[(gz + 1) * grid_w + (gx + 1)]
			var bl: float = mask[(gz + 1) * grid_w + gx]

			var case_index: int = 0
			if tl >= iso:
				case_index |= 1
			if tr >= iso:
				case_index |= 2
			if br >= iso:
				case_index |= 4
			if bl >= iso:
				case_index |= 8

			if case_index == 0 or case_index == 15:
				continue

			## Cell corner world positions (XZ).
			var x0: float = origin_x + float(gx) * spacing
			var x1: float = origin_x + float(gx + 1) * spacing
			var z0: float = origin_z + float(gz) * spacing
			var z1: float = origin_z + float(gz + 1) * spacing

			## Edge midpoints (interpolated).
			var top: Vector2 = _lerp_edge(Vector2(x0, z0), Vector2(x1, z0), tl, tr, iso)
			var right: Vector2 = _lerp_edge(Vector2(x1, z0), Vector2(x1, z1), tr, br, iso)
			var bottom: Vector2 = _lerp_edge(Vector2(x0, z1), Vector2(x1, z1), bl, br, iso)
			var left: Vector2 = _lerp_edge(Vector2(x0, z0), Vector2(x0, z1), tl, bl, iso)

			## Emit segments per case.
			match case_index:
				1:
					segments.append([top, left])
				2:
					segments.append([right, top])
				3:
					segments.append([right, left])
				4:
					segments.append([bottom, right])
				5:
					## Saddle — use average to disambiguate.
					var avg: float = (tl + tr + br + bl) * 0.25
					if avg >= iso:
						segments.append([top, right])
						segments.append([bottom, left])
					else:
						segments.append([bottom, right])
						segments.append([top, left])
				6:
					segments.append([bottom, top])
				7:
					segments.append([bottom, left])
				8:
					segments.append([left, bottom])
				9:
					segments.append([top, bottom])
				10:
					## Saddle.
					var avg: float = (tl + tr + br + bl) * 0.25
					if avg >= iso:
						segments.append([left, top])
						segments.append([right, bottom])
					else:
						segments.append([left, bottom])
						segments.append([right, top])
				11:
					segments.append([right, bottom])
				12:
					segments.append([left, right])
				13:
					segments.append([top, right])
				14:
					segments.append([left, top])

	return segments


func _lerp_edge(p0: Vector2, p1: Vector2, v0: float, v1: float, iso: float) -> Vector2:
	if abs(v1 - v0) < 0.0001:
		return (p0 + p1) * 0.5
	var t: float = clamp((iso - v0) / (v1 - v0), 0.0, 1.0)
	return p0.lerp(p1, t)


# ---------------------------------------------------------------------------
#  Segment chaining
# ---------------------------------------------------------------------------

## Chain an unordered list of [Vector2, Vector2] segments into closed rings.
## Uses a simple greedy weld with a small epsilon.
func _chain_segments(segments: Array) -> Array:
	var rings: Array = []
	var remaining: Array = segments.duplicate()
	var weld_eps: float = 0.001

	while not remaining.is_empty():
		var chain: PackedVector2Array = PackedVector2Array()
		var seg: Array = remaining.pop_back()
		chain.append(seg[0])
		chain.append(seg[1])

		var changed: bool = true
		while changed:
			changed = false
			for i in range(remaining.size() - 1, -1, -1):
				var s: Array = remaining[i]
				var head: Vector2 = chain[0]
				var tail: Vector2 = chain[chain.size() - 1]

				if s[0].distance_to(tail) < weld_eps:
					chain.append(s[1])
					remaining.remove_at(i)
					changed = true
				elif s[1].distance_to(tail) < weld_eps:
					chain.append(s[0])
					remaining.remove_at(i)
					changed = true
				elif s[1].distance_to(head) < weld_eps:
					chain.insert(0, s[0])
					remaining.remove_at(i)
					changed = true
				elif s[0].distance_to(head) < weld_eps:
					chain.insert(0, s[1])
					remaining.remove_at(i)
					changed = true

		rings.append(chain)

	return rings


# ---------------------------------------------------------------------------
#  Douglas-Peucker simplification
# ---------------------------------------------------------------------------

func _douglas_peucker(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points

	var max_dist: float = 0.0
	var max_index: int = 0

	for i in range(1, points.size() - 1):
		var d: float = _point_line_distance(points[i], points[0], points[points.size() - 1])
		if d > max_dist:
			max_dist = d
			max_index = i

	if max_dist > tolerance:
		var left: PackedVector2Array = _douglas_peucker(points.slice(0, max_index + 1), tolerance)
		var right: PackedVector2Array = _douglas_peucker(points.slice(max_index), tolerance)

		var result: PackedVector2Array = PackedVector2Array()
		for i in range(left.size() - 1):
			result.append(left[i])
		for i in range(right.size()):
			result.append(right[i])
		return result
	else:
		var result: PackedVector2Array = PackedVector2Array()
		result.append(points[0])
		result.append(points[points.size() - 1])
		return result


func _point_line_distance(point: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var line_vec: Vector2 = line_end - line_start
	var length_sq: float = line_vec.length_squared()
	if length_sq < 0.00001:
		return point.distance_to(line_start)
	var t: float = clamp((point - line_start).dot(line_vec) / length_sq, 0.0, 1.0)
	var projection: Vector2 = line_start + line_vec * t
	return point.distance_to(projection)


# ---------------------------------------------------------------------------
#  Polygon area (shoelace)
# ---------------------------------------------------------------------------

func _polygon_area(pts: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = pts.size()
	for i in range(n):
		var j: int = (i + 1) % n
		area += pts[i].x * pts[j].y
		area -= pts[j].x * pts[i].y
	return area * 0.5


# ---------------------------------------------------------------------------
#  Config helper
# ---------------------------------------------------------------------------

func _cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback

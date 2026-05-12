## BoardwalkBuilder — procedural boardwalk mesh generation.
##
## Reads per-tile "edge_features" data loaded by HexBoard3D._load_map_data() and
## spawns cross-plank boardwalk geometry as a post-terrain pass.
##
## Visual target: marsh/wetland boardwalk. Planks run ACROSS the bridge width,
## not along it. Supports are regular and evenly spaced. Terminal ramps use the
## same cross-plank construction, descending to the destination tile.
##
## Tile classification by boardwalk port count:
##   0 = ignored            (no boardwalk on tile)
##   1 = terminal           (short stub + descending ramp)
##   2 = path               (straight or curved cross-plank run)
##   3 = junction           (small central platform + arm runs)
##   4+ = hub               (wider central platform + arm runs)
class_name BoardwalkBuilder
extends TileFeature

# ---------------------------------------------------------------------------
# Tuning vars — adjust in the inspector or via a .tres resource file.
# ---------------------------------------------------------------------------

@export_group("Deck")
## Extra height above tile top surface.
@export var deck_height_extra: float = HexCoord.ELEVATION_STEP * 0.5
@export var deck_inset_neighbor: float = 0.1

@export_group("Planks")
## Target usable width of the boardwalk (roughly 1 character wide).
@export var walkway_width: float = 1.0
## Width of each plank across the bridge (long axis of the plank).
@export var plank_span_min: float = 0.87
@export var plank_span_max: float = 0.95
## Depth of each plank along the walking direction (short axis of the plank).
## Exaggerated relative to realistic planks so they read in pixel-art renders.
@export var plank_depth_min: float = 0.18
@export var plank_depth_max: float = 0.26
## Plank thickness (vertical).
@export var plank_thickness: float = 0.05
## Overlap (+) or gap (−) between consecutive planks along the walking direction.
## Positive = planks overlap slightly; negative = tiny visible gap.
@export var plank_forward_offset_min: float = -0.01
@export var plank_forward_offset_max: float = 0.05

@export_group("Plank Jitter")
## Random lateral (sideways) shift applied to each plank centre.
@export var plank_lateral_jitter: float = 0.02
## Random vertical shift applied to each plank centre (makes overlap legible).
@export var plank_vertical_jitter: float = 0.005
## Rotation jitter ranges (degrees).
@export var plank_pitch_deg: float = 1.0
@export var plank_roll_deg: float = 2.0
@export var plank_yaw_deg: float = 1.0
## Extra half-extent added to span on both sides for edge roughness.
@export var plank_edge_overhang: float = 0.0

@export_group("Stilts")
## Number of support rows placed per tile-crossing segment.
@export var stilts_per_hex: int = 4
@export var stilt_radius: float = 0.035
## Inset from walkway edge to stilt centre.
@export var stilt_inset_from_edge: float = 0.14
## Number of faces on each cylindrical stilt.
@export var stilt_segments: int = 6

@export_group("Junction / Hub")
## Radius of the flat central landing for 3-port junctions.
@export var junction_platform_radius: float = 0.35
## Scale factor applied to junction_platform_radius for 4+ port hubs.
@export var hub_platform_scale: float = 1.4

## If assigned, this material is used instead of the auto-generated warm brown.
@export var boardwalk_material: Material

# ---------------------------------------------------------------------------
# TileFeature interface
# ---------------------------------------------------------------------------

func get_feature_id() -> String:
	return "boardwalk"


## Filter to tiles that have at least one boardwalk edge_feature port.
func collect_tiles(all_tiles: Dictionary) -> Dictionary:
	var own: Dictionary = {}
	for coord: Vector2i in all_tiles.keys():
		if not _get_boardwalk_ports(all_tiles[coord]).is_empty():
			own[coord] = all_tiles[coord]
	return own


## TileFeature entry point — delegates to spawn_boardwalks with the full
## board tile dict from shared["tiles"] so neighbour lookups work correctly.
func spawn(parent: Node3D, _own_tiles: Dictionary, shared: Dictionary) -> void:
	var tiles_v: Variant = shared.get("tiles", _own_tiles)
	var all_tiles: Dictionary = tiles_v if tiles_v is Dictionary else _own_tiles
	spawn_boardwalks(parent, all_tiles)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

## Spawn all boardwalk geometry as children of a "Boardwalks" node under parent.
## tiles: the full HexBoard3D.tiles Dictionary (read-only).
func spawn_boardwalks(parent: Node3D, tiles: Dictionary) -> void:
	var container: Node3D = Node3D.new()
	container.name = "Boardwalks"
	parent.add_child(container)

	var mat: Material = _make_material()

	for coord: Vector2i in tiles.keys():
		var tile_data: Dictionary = tiles[coord]
		var ports: Array[int] = _get_boardwalk_ports(tile_data)
		if ports.is_empty():
			continue

		var deck_y: float = _compute_deck_y(tile_data)
		var rng: RandomNumberGenerator = _make_rng(coord)
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		match ports.size():
			1:
				_build_terminal(st, tile_data, ports, deck_y, tiles, coord, rng)
			2:
				_build_two_port_segment(st, tile_data, ports, deck_y, tiles, coord, rng)
			3:
				_build_junction(st, tile_data, ports, deck_y, tiles, coord, rng)
			_:
				_build_hub(st, tile_data, ports, deck_y, tiles, coord, rng)

		var mesh: ArrayMesh = st.commit()

		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "Boardwalk_%d_%d" % [coord.x, coord.y]
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = HexCoord.axial_to_world(coord, HexCoord.RADIUS)
		container.add_child(mi)

# ---------------------------------------------------------------------------
# Port detection
# ---------------------------------------------------------------------------

## Return an array of direction indices (0-5) where edge_features == "boardwalk".
func _get_boardwalk_ports(tile_data: Dictionary) -> Array[int]:
	var features: Array = tile_data.get("edge_features", [])
	var ports: Array[int] = []
	for dir: int in range(6):
		if dir < features.size() and features[dir] == "boardwalk":
			ports.append(dir)
	return ports

# ---------------------------------------------------------------------------
# Height helpers
# ---------------------------------------------------------------------------

## Boardwalk deck height for a given tile: tile top + deck_height_extra.
func _compute_deck_y(tile_data: Dictionary) -> float:
	var elev: int = int(tile_data.get("elevation", 0))
	return HexCoord.elevation_to_height(elev) + deck_height_extra

## Height at the top of a neighbouring tile (used for ramp targets).
## Returns the current tile's own top_y as a fallback if the neighbour is absent.
func _compute_neighbour_top_y(tiles: Dictionary, coord: Vector2i, dir: int) -> float:
	var n_coord: Vector2i = HexCoord.get_neighbor(coord, dir)
	if not tiles.has(n_coord):
		return HexCoord.elevation_to_height(int(tiles[coord].get("elevation", 0)))
	return HexCoord.elevation_to_height(int(tiles[n_coord].get("elevation", 0)))

## Stilt base height: water tiles go one step below tile top; others use tile top.
func _compute_stilt_base_y(tile_data: Dictionary) -> float:
	var top_y: float = HexCoord.elevation_to_height(int(tile_data.get("elevation", 0)))
	var ttype: String = tile_data.get("terrain_type", "grass")
	if ttype == "water":
		return top_y - HexCoord.ELEVATION_STEP
	return top_y

## Ramp endpoint on the destination tile, placed HexCoord.TOP_INSET inward from
## the neighbour tile's centre.  In current-tile local space this is at:
##   outward * (sqrt(3)*RADIUS - TOP_INSET)
## which sits just inside the top face of the neighbour hex.
func _get_ramp_end_point(dir: int, land_y: float) -> Vector3:
	var outward: Vector3 = _edge_outward(dir)
	# Neighbour centre in local space is sqrt(3)*RADIUS along the outward direction.
	var neighbour_dist: float = sqrt(3.0) * HexCoord.RADIUS
	# Inset TOP_INSET from that centre = just inside the top face.
	var end_dist: float = neighbour_dist - HexCoord.TOP_INSET
	return Vector3(outward.x * end_dist, land_y, outward.z * end_dist)

# ---------------------------------------------------------------------------
# Geometry helpers — edge midpoints
# ---------------------------------------------------------------------------

## Return the local-space midpoint of a hex edge at the given deck height.
## Uses the same corner convention as HexMeshBuilder/BoardUtils.
func _edge_midpoint_local(dir: int, y: float) -> Vector3:
	var idx: Vector2i = BoardUtils.get_edge_corner_indices(dir)
	var outer: Array[Vector3] = HexCoord.get_corner_positions(HexCoord.RADIUS)
	var mid: Vector3 = (outer[idx.x] + outer[idx.y]) * 0.5
	return Vector3(mid.x, y, mid.z)

## Outward unit vector (XZ plane) for a hex edge direction.
func _edge_outward(dir: int) -> Vector3:
	var mid: Vector3 = _edge_midpoint_local(dir, 0.0)
	return Vector3(mid.x, 0.0, mid.z).normalized()

# ---------------------------------------------------------------------------
# Path generation
# ---------------------------------------------------------------------------

## True when two directions are directly opposite (differ by 3).
func _is_opposite(a: int, b: int) -> bool:
	return (a + 3) % 6 == b

## Build evenly-spaced points along a horizontal path at deck_y.
## Opposite ports → straight lerp.  Adjacent/angled → quadratic Bézier
## through the tile centre for a gentle natural curve.
func _build_path_points(
	from: Vector3,
	to: Vector3,
	deck_y: float,
	straight: bool
) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var steps: int = 12
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		if straight:
			pts.append(from.lerp(to, t))
		else:
			var centre: Vector3 = Vector3(0.0, deck_y, 0.0)
			pts.append(_bezier_quad(from, centre, to, t))
	return pts

func _bezier_quad(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var mt: float = 1.0 - t
	return p0 * (mt * mt) + p1 * (2.0 * mt * t) + p2 * (t * t)

## Build a straight 3D path descending from start to end_pt (used for ramps).
func _build_ramp_path_points(start: Vector3, end_pt: Vector3) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var steps: int = 8
	for i: int in range(steps + 1):
		var t: float = float(i) / float(steps)
		pts.append(start.lerp(end_pt, t))
	return pts

# ---------------------------------------------------------------------------
# Tile-level builders — write into an already-begun SurfaceTool
# ---------------------------------------------------------------------------

## 1-port tile: short flat stub from interior to edge + descending ramp.
func _build_terminal(
	st: SurfaceTool,
	tile_data: Dictionary,
	ports: Array[int],
	deck_y: float,
	tiles: Dictionary,
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var dir: int = ports[0]
	var edge_mid: Vector3 = _edge_midpoint_local(dir, deck_y)
	var inward: Vector3 = -_edge_outward(dir)
	# Stub end: ~40 % of hex radius inward from the edge midpoint.
	var stub_end: Vector3 = edge_mid + inward * (HexCoord.RADIUS * 0.4)

	var path: Array[Vector3] = _build_path_points(stub_end, edge_mid, deck_y, true)
	_build_cross_plank_run(st, path, coord, rng)

	var stilt_base: float = _compute_stilt_base_y(tile_data)
	_build_supports_for_path(st, path, stilt_base)

	# Ramp descending toward the neighbouring tile.
	var land_y: float = _compute_neighbour_top_y(tiles, coord, dir)
	_build_ramp_cross_planks(st, dir, edge_mid, deck_y, land_y, coord, rng)


## 2-port tile: straight or gently curved cross-plank run between two edges.
func _build_two_port_segment(
	st: SurfaceTool,
	tile_data: Dictionary,
	ports: Array[int],
	deck_y: float,
	tiles: Dictionary,
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var dir_a: int = ports[0]
	var dir_b: int = ports[1]
	var from: Vector3 = _edge_midpoint_local(dir_a, deck_y)
	var to: Vector3 = _edge_midpoint_local(dir_b, deck_y)
	var straight: bool = _is_opposite(dir_a, dir_b)

	var path: Array[Vector3] = _build_path_points(from, to, deck_y, straight)
	_build_cross_plank_run(st, path, coord, rng)

	var stilt_base: float = _compute_stilt_base_y(tile_data)
	_build_supports_for_path(st, path, stilt_base)

	# Ramps at exits that face non-boardwalk neighbours.
	_maybe_add_ramp(st, tiles, coord, dir_a, deck_y, rng)
	_maybe_add_ramp(st, tiles, coord, dir_b, deck_y, rng)


## 3-port tile: small central platform + three arm runs.
func _build_junction(
	st: SurfaceTool,
	tile_data: Dictionary,
	ports: Array[int],
	deck_y: float,
	tiles: Dictionary,
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	_build_central_platform(st, deck_y, junction_platform_radius)

	var stilt_base: float = _compute_stilt_base_y(tile_data)
	_add_platform_stilts(st, deck_y, junction_platform_radius, stilt_base)

	for dir: int in ports:
		var edge_mid: Vector3 = _edge_midpoint_local(dir, deck_y)
		var outward: Vector3 = _edge_outward(dir)
		var arm_start: Vector3 = outward * junction_platform_radius
		arm_start.y = deck_y
		var path: Array[Vector3] = _build_path_points(arm_start, edge_mid, deck_y, true)
		_build_cross_plank_run(st, path, coord, rng)
		_build_supports_for_path(st, path, stilt_base)
		_maybe_add_ramp(st, tiles, coord, dir, deck_y, rng)


## 4+ port tile: wider central platform + one arm per port.
func _build_hub(
	st: SurfaceTool,
	tile_data: Dictionary,
	ports: Array[int],
	deck_y: float,
	tiles: Dictionary,
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var hub_radius: float = junction_platform_radius * hub_platform_scale
	_build_central_platform(st, deck_y, hub_radius)

	var stilt_base: float = _compute_stilt_base_y(tile_data)
	_add_platform_stilts(st, deck_y, hub_radius, stilt_base)

	for dir: int in ports:
		var edge_mid: Vector3 = _edge_midpoint_local(dir, deck_y)
		var outward: Vector3 = _edge_outward(dir)
		var arm_start: Vector3 = outward * hub_radius
		arm_start.y = deck_y
		var path: Array[Vector3] = _build_path_points(arm_start, edge_mid, deck_y, true)
		_build_cross_plank_run(st, path, coord, rng)
		_build_supports_for_path(st, path, stilt_base)
		_maybe_add_ramp(st, tiles, coord, dir, deck_y, rng)

# ---------------------------------------------------------------------------
# Ramp helpers
# ---------------------------------------------------------------------------

## Add a ramp only if the neighbour in `dir` has no boardwalk port pointing back.
func _maybe_add_ramp(
	st: SurfaceTool,
	tiles: Dictionary,
	coord: Vector2i,
	dir: int,
	deck_y: float,
	rng: RandomNumberGenerator
) -> void:
	var n_coord: Vector2i = HexCoord.get_neighbor(coord, dir)
	var neighbour_has_bw: bool = false
	if tiles.has(n_coord):
		var n_data: Dictionary = tiles[n_coord]
		var n_ports: Array[int] = _get_boardwalk_ports(n_data)
		var reverse: int = (dir + 3) % 6
		neighbour_has_bw = n_ports.has(reverse)

	if not neighbour_has_bw:
		var edge_mid: Vector3 = _edge_midpoint_local(dir, deck_y)
		var land_y: float = _compute_neighbour_top_y(tiles, coord, dir)
		_build_ramp_cross_planks(st, dir, edge_mid, deck_y, land_y, coord, rng)


## Ramp using the same cross-plank logic as flat segments, along a descending
## 3D path.  Ramp start slightly overlaps the flat deck (no visible gap).
## Ramp end is placed at HexCoord.TOP_INSET inward from the neighbour centre.
func _build_ramp_cross_planks(
	st: SurfaceTool,
	dir: int,
	edge_mid: Vector3,  # local space at deck_y
	deck_y: float,
	land_y: float,
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	var ramp_start: Vector3 = edge_mid


	var ramp_end: Vector3 = _get_ramp_end_point(dir, land_y)

	var path: Array[Vector3] = _build_ramp_path_points(ramp_start, ramp_end)
	_build_cross_plank_run(st, path, coord, rng)
	# Two support rows on the ramp — simple but regular.
	_build_supports_for_path(st, path, land_y, 2)

# ---------------------------------------------------------------------------
# Core cross-plank run
# ---------------------------------------------------------------------------

## March along path_points and place one plank ACROSS the bridge at each step.
##
## Plank orientation (in each plank's local basis):
##   basis.x = right     — long axis, across the bridge (span)
##   basis.y = plank_up  — perpendicular to slope surface (thickness)
##   basis.z = fwd       — short axis, along the bridge (depth)
##
## For ramps, basis.y is tilted with the slope so planks lie flush.
##
## Advance = depth − forward_offset:
##   forward_offset > 0  →  overlap (advance less than depth)
##   forward_offset < 0  →  tiny gap (advance more than depth)
func _build_cross_plank_run(
	st: SurfaceTool,
	path_points: Array[Vector3],
	coord: Vector2i,
	rng: RandomNumberGenerator
) -> void:
	if path_points.size() < 2:
		return
	var total_len: float = _path_length(path_points)
	if total_len < 0.001:
		return

	var cursor: float = 0.0
	var plank_idx: int = 0

	while cursor <= total_len:
		var t: float = cursor / total_len
		var centre: Vector3 = _sample_path(path_points, minf(t, 1.0))

		# Path tangent at this cursor position.
		var t_next: float = minf((cursor + 0.02) / total_len, 1.0)
		var next_pt: Vector3 = _sample_path(path_points, t_next)
		var fwd: Vector3 = next_pt - centre
		if fwd.length_squared() < 0.0001:
			fwd = path_points[path_points.size() - 1] - path_points[0]
		if fwd.length_squared() < 0.0001:
			fwd = Vector3(0.0, 0.0, 1.0)
		fwd = fwd.normalized()

		# right: horizontal, across the bridge.
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.0001:
			right = Vector3(1.0, 0.0, 0.0)

		# plank_up: perpendicular to the slope surface so ramp planks lie flush.
		var plank_up: Vector3 = right.cross(fwd).normalized()

		# Per-plank deterministic variation.
		var span: float = rng.randf_range(plank_span_min, plank_span_max)
		var depth: float = rng.randf_range(plank_depth_min, plank_depth_max)
		var off_lat: float = rng.randf_range(-plank_lateral_jitter, plank_lateral_jitter)
		var off_vert: float = rng.randf_range(-plank_vertical_jitter, plank_vertical_jitter)
		var forward_offset: float = rng.randf_range(plank_forward_offset_min, plank_forward_offset_max)
		var pitch: float = deg_to_rad(rng.randf_range(-plank_pitch_deg, plank_pitch_deg))
		var roll_v: float = deg_to_rad(rng.randf_range(-plank_roll_deg, plank_roll_deg))
		var yaw_v: float = deg_to_rad(rng.randf_range(-plank_yaw_deg, plank_yaw_deg))

		# Apply positional jitter (lateral + subtle vertical nudge for overlap legibility).
		var plank_centre: Vector3 = centre + right * off_lat + plank_up * off_vert

		# Build local basis: X = right (across), Y = plank_up (surface normal), Z = fwd (along).
		var basis: Basis = Basis(right, plank_up, fwd)
		basis = basis.rotated(basis.x, pitch)
		basis = basis.rotated(basis.y, yaw_v)
		basis = basis.rotated(basis.z, roll_v)

		# Half-extents: x = (span + overhang)/2, y = thickness/2, z = depth/2.
		_add_box(st, plank_centre, basis,
			Vector3((span + plank_edge_overhang)*0.75, plank_thickness * 0.5, depth * 0.5))

		# Advance: positive forward_offset = overlap (advance less), negative = gap.
		cursor += depth - forward_offset
		plank_idx += 1

# ---------------------------------------------------------------------------
# Supports / stilts
# ---------------------------------------------------------------------------

## Place stilt pairs at regular intervals along path_points.
## num_rows: explicit row count, or pass -1 to use stilts_per_hex.
func _build_supports_for_path(
	st: SurfaceTool,
	path_points: Array[Vector3],
	base_y: float,
	num_rows: int = -1
) -> void:
	var total_len: float = _path_length(path_points)
	if total_len < 0.001:
		return

	var rows: int = num_rows if num_rows > 0 else stilts_per_hex
	rows = maxi(1, rows)
	var spread: float = walkway_width * 0.5 - stilt_inset_from_edge

	for i: int in range(rows):
		var t: float = (float(i) + 0.5) / float(rows)
		var centre: Vector3 = _sample_path(path_points, t)

		var t_next: float = minf(t + 0.05, 1.0)
		var fwd: Vector3 = (_sample_path(path_points, t_next) - centre).normalized()
		if fwd.length_squared() < 0.0001:
			fwd = Vector3(1.0, 0.0, 0.0)
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		if right.length_squared() < 0.0001:
			right = Vector3(1.0, 0.0, 0.0)

		var left_pos: Vector3 = centre + right * spread
		var right_pos: Vector3 = centre - right * spread
		var top_y: float = centre.y - plank_thickness * 0.5

		if top_y > base_y + 0.01:
			_add_cylinder(st, Vector3(left_pos.x,  base_y, left_pos.z),  top_y, stilt_radius, stilt_segments)
			_add_cylinder(st, Vector3(right_pos.x, base_y, right_pos.z), top_y, stilt_radius, stilt_segments)


## Four corner stilts underneath a central platform polygon.
func _add_platform_stilts(
	st: SurfaceTool,
	deck_y: float,
	platform_radius: float,
	base_y: float
) -> void:
	var top_y: float = deck_y - plank_thickness * 0.5
	if top_y <= base_y + 0.01:
		return
	var inset: float = platform_radius - stilt_inset_from_edge
	for i: int in range(4):
		var angle: float = TAU * float(i) / 4.0
		var pos: Vector3 = Vector3(cos(angle) * inset, base_y, sin(angle) * inset)
		_add_cylinder(st, pos, top_y, stilt_radius, stilt_segments)

# ---------------------------------------------------------------------------
# Central platform (junction / hub)
# ---------------------------------------------------------------------------

## Flat N-gon platform of the given radius at deck_y.
## Uses 12 sides for a smooth-ish circle at these small scales.
func _build_central_platform(
	st: SurfaceTool,
	deck_y: float,
	radius: float
) -> void:
	var sides: int = 12
	var centre: Vector3 = Vector3(0.0, deck_y, 0.0)
	var bot_y: float = deck_y - plank_thickness

	for i: int in range(sides):
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var p0: Vector3 = Vector3(cos(a0) * radius, deck_y, sin(a0) * radius)
		var p1: Vector3 = Vector3(cos(a1) * radius, deck_y, sin(a1) * radius)

		# Top face.
		_add_triangle(st, centre, p0, p1, Vector3.UP)

		# Side wall segment.
		var side_normal: Vector3 = ((p0 + p1) * 0.5 - centre)
		side_normal.y = 0.0
		side_normal = side_normal.normalized()
		_add_quad(st,
			p0, p1,
			Vector3(p1.x, bot_y, p1.z),
			Vector3(p0.x, bot_y, p0.z),
			side_normal)

# ---------------------------------------------------------------------------
# Primitive geometry helpers
# ---------------------------------------------------------------------------

## Axis-aligned box with arbitrary basis and half-extents.
## Writes 6 faces (12 triangles) into st.
## basis: local frame axes (Basis columns = right/up/back in world space).
## half: half-extents along each basis axis.
func _add_box(
	st: SurfaceTool,
	centre: Vector3,
	basis: Basis,
	half: Vector3
) -> void:
	# 8 corners: iterate sign combinations.
	var signs: Array[Vector3] = [
		Vector3( 1,  1,  1),
		Vector3(-1,  1,  1),
		Vector3(-1, -1,  1),
		Vector3( 1, -1,  1),
		Vector3( 1,  1, -1),
		Vector3(-1,  1, -1),
		Vector3(-1, -1, -1),
		Vector3( 1, -1, -1),
	]
	var verts: Array[Vector3] = []
	for s: Vector3 in signs:
		verts.append(centre + basis.x * (half.x * s.x) + basis.y * (half.y * s.y) + basis.z * (half.z * s.z))

	# Six faces, each as a quad. Indices reference the 8 corners above.
	# Face normals are derived from the basis axes (not the cross product of
	# winding verts) so they stay correct despite small rotation jitter.
	_add_quad(st, verts[0], verts[1], verts[2], verts[3],  basis.z)   # +Z face
	_add_quad(st, verts[4], verts[7], verts[6], verts[5], -basis.z)   # -Z face
	_add_quad(st, verts[0], verts[3], verts[7], verts[4],  basis.x)   # +X face
	_add_quad(st, verts[1], verts[5], verts[6], verts[2], -basis.x)   # -X face
	_add_quad(st, verts[0], verts[4], verts[5], verts[1],  basis.y)   # +Y face (top)
	_add_quad(st, verts[3], verts[2], verts[6], verts[7], -basis.y)   # -Y face (bottom)


## N-sided cylinder stilt from base_pos.y=base_y up to top_y.
## base_pos provides the XZ centre; Y is replaced by base_y and top_y.
func _add_cylinder(
	st: SurfaceTool,
	base_pos: Vector3,
	top_y: float,
	radius: float,
	segments: int = 6
) -> void:
	var cx: float = base_pos.x
	var cz: float = base_pos.z
	var by: float = base_pos.y

	for i: int in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)

		var bx0: float = cx + cos(a0) * radius
		var bz0: float = cz + sin(a0) * radius
		var bx1: float = cx + cos(a1) * radius
		var bz1: float = cz + sin(a1) * radius

		var bot0: Vector3 = Vector3(bx0, by, bz0)
		var bot1: Vector3 = Vector3(bx1, by, bz1)
		var top0: Vector3 = Vector3(bx0, top_y, bz0)
		var top1: Vector3 = Vector3(bx1, top_y, bz1)

		var seg_mid: Vector3 = Vector3((bx0 + bx1) * 0.5 - cx, 0.0, (bz0 + bz1) * 0.5 - cz).normalized()
		_add_quad(st, top0, top1, bot1, bot0, seg_mid)


## Add a quad as two triangles with a shared face normal.
func _add_quad(
	st: SurfaceTool,
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	normal: Vector3
) -> void:
	_add_triangle(st, v0, v1, v2, normal)
	_add_triangle(st, v0, v2, v3, normal)


func _add_triangle(
	st: SurfaceTool,
	v0: Vector3, v1: Vector3, v2: Vector3,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	st.add_vertex(v0)
	st.set_normal(normal)
	st.add_vertex(v1)
	st.set_normal(normal)
	st.add_vertex(v2)

# ---------------------------------------------------------------------------
# Path sampling helpers
# ---------------------------------------------------------------------------

func _path_length(pts: Array[Vector3]) -> float:
	var total: float = 0.0
	for i: int in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


## Sample a point at normalised parameter t ∈ [0,1] along path_points.
func _sample_path(pts: Array[Vector3], t: float) -> Vector3:
	if pts.is_empty():
		return Vector3.ZERO
	if t <= 0.0:
		return pts[0]
	if t >= 1.0:
		return pts[pts.size() - 1]

	var total: float = _path_length(pts)
	var target: float = t * total
	var acc: float = 0.0
	for i: int in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if acc + seg >= target:
			var local_t: float = (target - acc) / seg
			return pts[i - 1].lerp(pts[i], local_t)
		acc += seg
	return pts[pts.size() - 1]

# ---------------------------------------------------------------------------
# Deterministic RNG
# ---------------------------------------------------------------------------

## Create a seeded RNG using integer hash of the tile's axial coordinate.
## This guarantees the same plank jitter every time the board is loaded.
func _make_rng(coord: Vector2i) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Large primes give good mixing between q and r so adjacent tiles differ.
	var seed_val: int = (coord.x * 73856093) ^ (coord.y * 19349663)
	rng.seed = seed_val
	return rng

# ---------------------------------------------------------------------------
# Material
# ---------------------------------------------------------------------------

func _make_material() -> Material:
	if boardwalk_material != null:
		return boardwalk_material
	var shader: Shader = load("res://shaders/boardwalk_wood.gdshader") as Shader
	if shader == null:
		# Fallback: plain warm-brown StandardMaterial3D if shader is missing.
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.71, 0.62, 0.50)
		mat.roughness = 0.85
		mat.metallic = 0.0
		return mat
	var smat: ShaderMaterial = ShaderMaterial.new()
	smat.shader = shader
	RenderUtils.attach_edge_detection_pass(smat)
	return smat

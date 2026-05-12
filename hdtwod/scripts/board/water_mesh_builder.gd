class_name WaterMeshBuilder
extends RefCounted

# How far below max_floor_y a water/absent corner can randomly drop.
const MAX_EXTRA_DROP_STEPS: float = 2.5

# Build a two-surface ArrayMesh for a water tile.
#   Surface 0: flat hex water surface  (water_surface.gdshader)
#   Surface 1: irregular seafloor      (tile_surface.gdshader)
#
# Seafloor geometry: 6 outer hex corners + 1 centre = 7 vertices, 6 triangles.
# Corner j is adjacent to two edge directions:
#   dir_left  = (7 - j) % 6   (edge whose right endpoint is corner j)
#   dir_right = (6 - j) % 6   (edge whose left  endpoint is corner j)
# A land neighbour on either adjacent edge locks that corner to the land
# column bottom.  Land always supersedes water/absent on the same corner.
func build_water_mesh(
    tiles: Dictionary,
    coord: Vector2i,
    water_elevation: int,
    height_offset: float = 0.0,
    corner_cache: Dictionary = {}
) -> ArrayMesh:
    var elevation_top_y := HexCoord.elevation_to_height(water_elevation)
    var water_top_y := elevation_top_y + height_offset
    # Seafloor may not rise above the bottom of the water column.
    var max_floor_y := elevation_top_y - HexCoord.ELEVATION_STEP

    var outer := HexCoord.get_corner_positions(HexCoord.RADIUS)

    # --- Surface 0: flat water hex ---
    var st_water := SurfaceTool.new()
    st_water.begin(Mesh.PRIMITIVE_TRIANGLES)
    _build_water_surface(st_water, outer, water_top_y)

    # --- Surface 1: irregular seafloor ---
    var corner_ys := _compute_corner_ys(tiles, coord, max_floor_y, corner_cache)
    var center_y := 0.0
    for y in corner_ys:
        center_y += y
    center_y /= 6.0
    center_y = min(center_y, max_floor_y)

    var st_floor := SurfaceTool.new()
    st_floor.begin(Mesh.PRIMITIVE_TRIANGLES)
    _build_seafloor(st_floor, outer, corner_ys, center_y)

    var mesh := st_water.commit()
    st_floor.commit(mesh)
    return mesh


# ---------------------------------------------------------------------------
# Surface 0 — flat hex water surface
# ---------------------------------------------------------------------------
# Winding: centre → b → a is CCW from above (+Y normal).
# 2D cross product for i=0: b=(√3/2,0.5), a=(√3/2,-0.5)
#   b.z*a.x - b.x*a.z = 0.5*(√3/2) - (√3/2)*(-0.5) = √3/2 > 0  ✓

func _build_water_surface(st: SurfaceTool, outer: Array[Vector3], top_y: float) -> void:
    var center := Vector3(0.0, top_y, 0.0)
    for i in range(6):
        var next_i := (i + 1) % 6
        var a := Vector3(outer[i].x,      top_y, outer[i].z)
        var b := Vector3(outer[next_i].x, top_y, outer[next_i].z)
        st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(center)
        st.set_normal(Vector3.UP); st.set_uv(_top_uv(a));        st.add_vertex(a)
        st.set_normal(Vector3.UP); st.set_uv(_top_uv(b));        st.add_vertex(b)


# ---------------------------------------------------------------------------
# Surface 1 — irregular seafloor
# ---------------------------------------------------------------------------
# Same CCW winding: centre → b → a.
# Normal from (b−centre)×(a−centre): the XZ component is always +√3/2,
# so Y is positive even when vertices are at very different heights.

func _build_seafloor(
    st: SurfaceTool,
    outer: Array[Vector3],
    corner_ys: Array[float],
    center_y: float
) -> void:
    var center_pos := Vector3(0.0, center_y, 0.0)
    for i in range(6):
        var next_i := (i + 1) % 6
        var a := Vector3(outer[i].x,      corner_ys[i],      outer[i].z)
        var b := Vector3(outer[next_i].x, corner_ys[next_i], outer[next_i].z)
        var n := (a - center_pos).cross(b - center_pos).normalized()
        st.set_normal(n); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(center_pos)
        st.set_normal(n); st.set_uv(_top_uv(a));        st.add_vertex(a)
        st.set_normal(n); st.set_uv(_top_uv(b));        st.add_vertex(b)


# ---------------------------------------------------------------------------
# Compute the Y height of each of the 6 outer corner vertices.
# ---------------------------------------------------------------------------

func _compute_corner_ys(
    tiles: Dictionary,
    coord: Vector2i,
    max_floor_y: float,
    corner_cache: Dictionary
) -> Array[float]:
    var q := coord.x
    var r := coord.y
    var depth_weight := _compute_depth_weight(tiles, coord)

    var result: Array[float] = []
    for j in range(6):
        var key := Vector3i(q, r, j)

        # If a neighbouring water tile was already built, it stored the correct
        # Y for this physical corner under our alias key — use it directly.
        if corner_cache.has(key):
            result.append(float(corner_cache[key]))
            continue

        # Compute fresh: land neighbour locks the corner; otherwise random drop.
        var land_y := INF
        for dir: int in [(7 - j) % 6, (6 - j) % 6]:
            var n_coord := HexCoord.get_neighbor(coord, dir)
            if not tiles.has(n_coord):
                continue
            if (tiles[n_coord].get("terrain_type", "grass") as String) == "water":
                continue
            var n_elev := int(tiles[n_coord].get("elevation", 0))
            var bottom := HexCoord.elevation_to_height(n_elev) - HexCoord.ELEVATION_STEP
            land_y = min(land_y, bottom)

        var y: float
        if land_y != INF:
            y = min(land_y, max_floor_y)
        else:
            y = _dropped_y(q, r, j, max_floor_y, depth_weight)

        # Store under all three (tile, corner_index) aliases that refer to the
        # same physical point, so neighbouring water tiles find it already set.
        #
        # Derivation (pointy-top axial, corner at angle 60j-30°):
        #   corner j of (q,r)  =  corner (j+4)%6 of neighbour in dir (6-j)%6
        #   corner j of (q,r)  =  corner (j+2)%6 of neighbour in dir (7-j)%6
        corner_cache[key] = y
        var n_right := HexCoord.get_neighbor(coord, (6 - j) % 6)
        corner_cache[Vector3i(n_right.x, n_right.y, (j + 4) % 6)] = y
        var n_left := HexCoord.get_neighbor(coord, (7 - j) % 6)
        corner_cache[Vector3i(n_left.x, n_left.y, (j + 2) % 6)] = y

        result.append(y)

    return result


func _compute_depth_weight(tiles: Dictionary, coord: Vector2i) -> float:
    var count := 0
    for dir in range(6):
        var n_coord := HexCoord.get_neighbor(coord, dir)
        if not tiles.has(n_coord):
            count += 1
        elif (tiles[n_coord].get("terrain_type", "grass") as String) == "water":
            count += 1
    return clamp(float(count) / 6.0 + 0.25, 0.0, 1.0)


func _dropped_y(q: int, r: int, corner_j: int, max_floor_y: float, depth_weight: float) -> float:
    var h := _hash3(float(q), float(r), float(corner_j))
    return max_floor_y - pow(h, 0.5) * depth_weight * MAX_EXTRA_DROP_STEPS * HexCoord.ELEVATION_STEP


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func _hash3(a: float, b: float, c: float) -> float:
    var v := sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
    return abs(fmod(v, 1.0))


static func _top_uv(v: Vector3) -> Vector2:
    return Vector2(
        v.x / (HexCoord.RADIUS * 2.0) + 0.5,
        v.z / (HexCoord.RADIUS * 2.0) + 0.5
    )


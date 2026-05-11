class_name GrassSpawner
extends RefCounted


# Deterministic hash: maps two floats to a value in [0, 1).
static func _hash2(a: float, b: float) -> float:
    return abs(fmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0))


# World XZ to axial hex coord using pointy-top layout inverse.
static func _world_to_hex(wx: float, wz: float) -> Vector2i:
    var size: float = HexCoord.RADIUS
    var r_frac: float = wz / (size * 1.5)
    var q_frac: float = wx / (size * sqrt(3.0)) - r_frac * 0.5
    var s_frac: float = -q_frac - r_frac

    var q: int = roundi(q_frac)
    var r: int = roundi(r_frac)
    var s: int = roundi(s_frac)

    var qd: float = abs(float(q) - q_frac)
    var rd: float = abs(float(r) - r_frac)
    var sd: float = abs(float(s) - s_frac)

    if qd > rd and qd > sd:
        q = -r - s
    elif rd > sd:
        r = -q - s

    return Vector2i(q, r)


# Scatter blades across the entire board in one MultiMesh.
# spawn_tiles: tiles where grass is allowed to appear.
# terrain_collision_mask: collision mask for raycasts against terrain bodies.
func spawn_for_board(
    parent: Node3D,
    spawn_tiles: Dictionary,
    blade_spacing: float,
    material: Material,
    blade_width: float,
    blade_height: float,
    terrain_collision_mask: int
) -> void:
    if spawn_tiles.is_empty() or blade_spacing <= 0.0:
        return

    # Compute world bounding box of all tile centers.
    var min_x: float = INF
    var max_x: float = -INF
    var min_z: float = INF
    var max_z: float = -INF

    for coord in spawn_tiles.keys():
        var wp: Vector3 = HexCoord.axial_to_world(coord, HexCoord.RADIUS)
        if wp.x < min_x:
            min_x = wp.x
        if wp.x > max_x:
            max_x = wp.x
        if wp.z < min_z:
            min_z = wp.z
        if wp.z > max_z:
            max_z = wp.z

    # Expand by one tile radius so edge cells are fully covered.
    var pad: float = HexCoord.RADIUS * 1.5
    min_x -= pad
    max_x += pad
    min_z -= pad
    max_z += pad

    var positions: Array[Vector3] = []
    var rotations: Array[float] = []

    var gx: float = min_x
    while gx <= max_x:
        var gz: float = min_z
        while gz <= max_z:
            var jx: float = (_hash2(gx * 3.7 + gz * 1.1, 0.0) - 0.5) * blade_spacing
            var jz: float = (_hash2(0.0, gx * 2.3 + gz * 4.7) - 0.5) * blade_spacing
            var wx: float = gx + jx
            var wz: float = gz + jz

            var hex: Vector2i = _world_to_hex(wx, wz)
            if spawn_tiles.has(hex):
                var hit: Dictionary = BoardUtils.sample_surface_position(
                    parent,
                    wx,
                    wz,
                    terrain_collision_mask
                )

                if not hit.is_empty():
                    var hit_pos: Vector3 = hit["position"]
                    positions.append(Vector3(wx, hit_pos.y, wz))
                    rotations.append(_hash2(wx * 0.57, wz * 0.83) * TAU)

            gz += blade_spacing
        gx += blade_spacing

    if positions.is_empty():
        return

    var quad := QuadMesh.new()
    quad.size = Vector2(blade_width * 2.0, blade_height * 2.0)
    quad.center_offset = Vector3(0.0, blade_height * 0.5, 0.0)

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.instance_count = positions.size()
    mm.mesh = quad

    for i in range(positions.size()):
        mm.set_instance_transform(
            i,
            Transform3D(Basis(Vector3.UP, rotations[i]), positions[i])
        )

    var mmi := MultiMeshInstance3D.new()
    mmi.name = "Grass"
    mmi.multimesh = mm
    mmi.material_override = material
    mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mmi)
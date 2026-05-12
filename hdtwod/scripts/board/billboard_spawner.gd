class_name BillboardSpawner
extends RefCounted

## Generic jittered-grid billboard decorator spawner.
## Scatters billboard quads across a tile set, raycasts for surface height,
## and builds a single MultiMeshInstance3D.
##
## Usage:
##   var s := BillboardSpawner.new()
##   s.spacing = 0.3
##   s.width   = 0.12
##   s.height  = 0.3
##   s.spawn(parent, own_tiles, material, shared["terrain_collision_mask"])

## Grid step between candidates (smaller = denser).
var spacing: float = 0.3
## Fraction of spacing to randomly offset each candidate.
var jitter: float = 0.8
## Billboard quad width.
var width: float = 0.15
## Billboard quad height.
var height: float = 0.2
## Whether instances cast shadows.
var cast_shadows: bool = false
## Node name for the spawned MultiMeshInstance3D.
var node_name: String = "Billboards"


func spawn(
    parent: Node3D,
    spawn_tiles: Dictionary,
    material: Material,
    terrain_collision_mask: int
) -> void:
    if spawn_tiles.is_empty() or spacing <= 0.0:
        return

    var min_x := INF;  var max_x := -INF
    var min_z := INF;  var max_z := -INF
    for coord in spawn_tiles.keys():
        var wp := HexCoord.axial_to_world(coord, HexCoord.RADIUS)
        min_x = min(min_x, wp.x);  max_x = max(max_x, wp.x)
        min_z = min(min_z, wp.z);  max_z = max(max_z, wp.z)
    var pad := HexCoord.RADIUS * 1.5
    min_x -= pad;  max_x += pad
    min_z -= pad;  max_z += pad

    var positions: Array[Vector3] = []
    var rotations:  Array[float]  = []
    var jitter_amt := spacing * jitter

    var gx := min_x
    while gx <= max_x:
        var gz := min_z
        while gz <= max_z:
            var jx := (_hash2(gx * 3.7 + gz * 1.1, 0.0) - 0.5) * jitter_amt
            var jz := (_hash2(0.0, gx * 2.3 + gz * 4.7) - 0.5) * jitter_amt
            var wx := gx + jx
            var wz := gz + jz
            if spawn_tiles.has(_world_to_hex(wx, wz)):
                var hit := BoardUtils.sample_surface_position(
                    parent, wx, wz, terrain_collision_mask
                )
                if not hit.is_empty():
                    positions.append(Vector3(wx, hit["position"].y, wz))
                    rotations.append(_hash2(wx * 0.57, wz * 0.83) * TAU)
            gz += spacing
        gx += spacing

    if positions.is_empty():
        return

    var quad := QuadMesh.new()
    quad.size = Vector2(width, height)
    quad.center_offset = Vector3(0.0, height * 0.5, 0.0)

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.instance_count   = positions.size()
    mm.mesh = quad

    for i in range(positions.size()):
        mm.set_instance_transform(
            i, Transform3D(Basis(Vector3.UP, rotations[i]), positions[i])
        )

    var mmi := MultiMeshInstance3D.new()
    mmi.name              = node_name
    mmi.multimesh         = mm
    mmi.material_override = material
    mmi.cast_shadow       = (
        GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows
        else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    )
    parent.add_child(mmi)


static func _hash2(a: float, b: float) -> float:
    return abs(fmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0))


static func _world_to_hex(wx: float, wz: float) -> Vector2i:
    var size   := HexCoord.RADIUS
    var r_frac := wz / (size * 1.5)
    var q_frac := wx / (size * sqrt(3.0)) - r_frac * 0.5
    var s_frac := -q_frac - r_frac
    var q := roundi(q_frac)
    var r := roundi(r_frac)
    var s := roundi(s_frac)
    if abs(float(q) - q_frac) > abs(float(r) - r_frac) and abs(float(q) - q_frac) > abs(float(s) - s_frac):
        q = -r - s
    elif abs(float(r) - r_frac) > abs(float(s) - s_frac):
        r = -q - s
    return Vector2i(q, r)
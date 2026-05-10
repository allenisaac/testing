class_name HexCoord
extends RefCounted


# --- Direction vectors for pointy-top hex grid (axial coordinates) ---
# Order: E, NE, NW, W, SW, SE
# x=q, z=r
const DIRECTION_VECTORS: Array[Vector2i] = [
    Vector2i(1, 0),   # East
    Vector2i(1, -1),  # NE
    Vector2i(0, -1),  # NW
    Vector2i(-1, 0),  # West
    Vector2i(-1, 1),  # SW
    Vector2i(0, 1),   # SE
]

# Distance from center to corner
const RADIUS: float = 1.0
const TOP_INSET: float = 0.65
# Height of one elevation step
const ELEVATION_STEP: float = 0.5


# Pointy-top hex corners in XZ plane
# Y is height in world space
static func get_corner_positions(radius: float = RADIUS) -> Array[Vector3]:
    var corners: Array[Vector3] = []
    for i in range(6):
        var angle_deg := 60.0 * i - 30.0
        var angle_rad := deg_to_rad(angle_deg)
        corners.append(Vector3(cos(angle_rad) * radius, 0.0, sin(angle_rad) * radius))
    return corners



static func get_corner(radius: float, index: int) -> Vector3:
    var corners := get_corner_positions(radius)
    return corners[index % 6]

## Return the neighboring hex in a given direction (0–5, wraps via modulo).
## Direction indices: 0=E, 1=NE, 2=NW, 3=W, 4=SW, 5=SE.
static func get_neighbor(hex: Vector2i, direction: int) -> Vector2i:
    return hex + DIRECTION_VECTORS[direction % 6]


## Return all 6 neighbors of a hex as an Array[Vector2i].
## Order matches DIRECTION_VECTORS: E, NE, NW, W, SW, SE.
static func all_neighbors(hex: Vector2i) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for dir in DIRECTION_VECTORS:
        result.append(hex + dir)
    return result


## Calculate the hex-grid distance (minimum steps) between two axial coords.
## Always returns >= 0.
static func distance(a: Vector2i, b: Vector2i) -> int:
    var dq: int = abs(a.x - b.x)
    var dr: int = abs(a.y - b.y) 
    var ds: int = abs((-a.x - a.y) - (-b.x - b.y)) # s = -q - r
    return int((dq + dr + ds) / 2)
    
## Convert an axial hex coordinate to a world-space position (pointy-top layout).
## Returns Vector3(x, 0, z) where x is horizontal and z is depth.
static func axial_to_world(hex: Vector2i, hex_size: float) -> Vector3:
    var x: float = hex_size * sqrt(3) * (hex.x + (hex.y * 0.5))
    var z: float = hex_size * (1.5 * hex.y)
    return Vector3(x, 0.0, z)


static func elevation_to_height(elevation: int) -> float:
    return elevation * ELEVATION_STEP


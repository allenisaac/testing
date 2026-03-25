## Hex Coordinate System
## Uses axial coordinates (q, r) for pointy-top hexes.
## All methods are static — do not instantiate; call HexCoords.<method> directly.
##
## Available functions:
##   neighbor(hex, direction)    -> Vector2i   — Get the adjacent hex in one of 6 directions (0-5).
##   all_neighbors(hex)          -> Array[Vector2i] — Get all 6 neighbors of a hex.
##   distance(a, b)              -> int        — Hex-grid distance between two axial coords.
##   to_world(hex, hex_size)     -> Vector2    — Convert axial coord to 2D world position (pointy-top).
##   to_world_3d(coord, hex_size)-> Vector3    — Convert axial coord to 3D world position (y=0 plane).
##
## Constants:
##   DIRECTION_VECTORS : Array[Vector2i] — The 6 axial direction offsets (E, NE, NW, W, SW, SE).

extends RefCounted
class_name HexCoords


# --- Direction vectors for pointy-top hex grid (axial coordinates) ---
# Order: E, NE, NW, W, SW, SE
# x=q, y=r
const DIRECTION_VECTORS: Array[Vector2i] = [
	Vector2i(1, 0),   # East
	Vector2i(1, -1),  # NE
	Vector2i(0, -1),  # NW
	Vector2i(-1, 0),  # West
	Vector2i(-1, 1),  # SW
	Vector2i(0, 1),   # SE
]

# Hex size in pixels
# in the future will change based on resolution
### maybe zoom level?
#const HEX_SIZE: float = 48.0

## Return the neighboring hex in a given direction (0–5, wraps via modulo).
## Direction indices: 0=E, 1=NE, 2=NW, 3=W, 4=SW, 5=SE.
static func neighbor(hex: Vector2i, direction: int) -> Vector2i:
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
    
## Convert an axial hex coordinate to a 2D world position (pointy-top layout).
## Returns Vector2(x, y) where x is horizontal and y is vertical.
static func to_world(hex: Vector2i, hex_size: float) -> Vector2:
    var x: float = hex_size * sqrt(3) * (hex.x + (hex.y * 0.5))
    var y: float = hex_size * (1.5 * hex.y)
    return Vector2(x, y)

## Convert an axial hex coordinate to a 3D world position (pointy-top layout).
## Returns Vector3(x, 0.0, z) — height (y) is always 0; caller adjusts as needed.
static func to_world_3d(coord: Vector2i, hex_size: float) -> Vector3:
    var x: float = hex_size * sqrt(3) * (coord.x + (coord.y * 0.5))
    var z: float = hex_size * (1.5 * coord.y)
    return Vector3(x, 0.0, z)
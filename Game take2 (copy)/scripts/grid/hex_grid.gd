## HexGrid — logical board-state container.
## Stores full normalized tile data keyed by Vector2i.
##
## Tile accessors:
##   add_tile(coord, tile_data)       -> void           — Store a deep-copied tile dict; guarantees "units" and "tags" keys.
##   has_tile(coord)                  -> bool           — Check whether a tile exists at coord.
##   get_tile_data(coord)             -> Dictionary     — Full tile data dict (by reference); {} on miss.
##   get_all_coords()                 -> Array[Vector2i]— All coords that have tiles.
##
## Tile queries (prefer direct fields, fall back to tags):
##   get_tags(coord)                  -> Array[String]  — Tag list for the tile; [] on miss.
##   is_blocked(coord)                -> bool           — True if blocks_movement or "blocked" tag; unknown tiles → true.
##   is_hazard(coord)                 -> bool           — True if hazard field or "hazard" tag.
##   has_cover(coord)                 -> bool           — True if cover field or "cover" tag.
##   is_difficult_terrain(coord)      -> bool           — True if move_cost > 1 or "difficult" tag.
##   get_move_cost(coord)             -> int            — Movement cost; defaults to 1, 999 for missing tiles.
##   blocks_los(coord)                -> bool           — True if blocks_los field is true.
##
## Unit management:
##   is_occupied(coord)               -> bool           — True if any units on this tile.
##   get_occupants(coord)             -> Array[String]  — List of unit_id strings on tile; [] on miss.
##   unit_exists(unit_id)             -> bool           — Whether a unit with this id is tracked.
##   get_unit_position(unit_id)       -> Vector2i       — Coord where unit is placed (asserts existence).
##   place_unit(unit_id, coord)       -> void           — Move/place unit to coord (auto-removes from old).
##   remove_unit(unit_id)             -> void           — Remove unit from grid entirely (asserts existence).

extends RefCounted
class_name HexGrid


## key: Vector2i (axial coords), value: Dictionary of normalized tile data
var tiles: Dictionary = {}

## key: unit_id (String), value: Vector2i
var unit_positions: Dictionary = {}


# =========================================================================
#  Tile accessors
# =========================================================================

## Add a tile. tile_data is stored as a deep copy with "units" guaranteed.
func add_tile(coord: Vector2i, tile_data: Dictionary) -> void:
	assert(not tiles.has(coord), "Tile already exists at %s" % str(coord))
	var data: Dictionary = tile_data.duplicate(true)
	if not data.has("units"):
		data["units"] = []
	# Guarantee tags is always Array[String]
	if not data.has("tags"):
		data["tags"] = [] as Array[String]
	tiles[coord] = data


func has_tile(coord: Vector2i) -> bool:
	return tiles.has(coord)


## Returns the full tile data dict (by reference). Returns {} on miss.
## Expected keys (after normalization):
##   "coord"           : Vector2i
##   "terrain_id"      : String
##   "tags"            : Array[String]
##   "terrain_class"   : String        (e.g. "ground", "water", "structure")
##   "move_cost"       : int
##   "blocks_movement" : bool
##   "blocks_los"      : bool
##   "cover"           : bool
##   "hazard"          : bool
##   "region_group"    : String
##   "visual_roles"    : Array
##   "paint_layers"    : Array
##   "detail_rules"    : Dictionary
##   "units"           : Array[String]  (runtime — unit ids occupying this tile)
##   ...plus any extra fields from terrain def or board overrides.
func get_tile_data(coord: Vector2i) -> Dictionary:
	if not tiles.has(coord):
		return {}
	return tiles[coord]


func get_all_coords() -> Array[Vector2i]:
	return tiles.keys()


# =========================================================================
#  Tile queries — prefer direct fields, fall back to tags
# =========================================================================

func get_tags(coord: Vector2i) -> Array[String]:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return [] as Array[String]
	return data.get("tags", [] as Array[String])


func is_blocked(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return true  # unknown tiles are impassable
	if data.has("blocks_movement"):
		return bool(data["blocks_movement"])
	return "blocked" in data.get("tags", [])


func is_hazard(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return false
	if data.has("hazard"):
		return bool(data["hazard"])
	return "hazard" in data.get("tags", [])


func has_cover(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return false
	if data.has("cover"):
		return bool(data["cover"])
	return "cover" in data.get("tags", [])


func is_difficult_terrain(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return false
	if data.has("move_cost"):
		return int(data["move_cost"]) > 1
	return "difficult" in data.get("tags", [])


func get_move_cost(coord: Vector2i) -> int:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return 999
	if data.has("move_cost"):
		return int(data["move_cost"])
	if is_difficult_terrain(coord):
		return 2
	return 1


func blocks_los(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return false
	if data.has("blocks_los"):
		return bool(data["blocks_los"])
	return false


# =========================================================================
#  Unit management
# =========================================================================

func is_occupied(coord: Vector2i) -> bool:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return false
	return data.get("units", []).size() > 0


func get_occupants(coord: Vector2i) -> Array[String]:
	var data: Dictionary = get_tile_data(coord)
	if data.is_empty():
		return [] as Array[String]
	return data.get("units", [])


func unit_exists(unit_id: String) -> bool:
	return unit_positions.has(unit_id)


func get_unit_position(unit_id: String) -> Vector2i:
	assert(unit_positions.has(unit_id), "Unit '%s' does not exist" % unit_id)
	return unit_positions[unit_id]


func place_unit(unit_id: String, coord: Vector2i) -> void:
	assert(tiles.has(coord), "Cannot place unit on non-existent tile %s" % str(coord))
	if unit_positions.has(unit_id):
		remove_unit(unit_id)
	var data: Dictionary = tiles[coord]
	if not data.has("units"):
		data["units"] = []
	data["units"].append(unit_id)
	unit_positions[unit_id] = coord


func remove_unit(unit_id: String) -> void:
	assert(unit_positions.has(unit_id), "Unit '%s' not found" % unit_id)
	var coord: Vector2i = unit_positions[unit_id]
	tiles[coord]["units"].erase(unit_id)
	unit_positions.erase(unit_id)

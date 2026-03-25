## MapLoader — loads board, terrain, and biome JSON files and normalizes them
## into a runtime-ready Dictionary that other systems consume.
##
## Generic JSON helpers:
##   load_json_file(path)                                         -> Variant    — Parse any JSON file; returns null on failure.
##
## Definition loaders:
##   load_terrain_definitions(path)                               -> Dictionary — Terrain defs keyed by terrain_id.
##   load_biome_definitions(path)                                 -> Dictionary — Biome defs keyed by biome_id.
##
## Board loading & normalization:
##   load_board_data(board_path, terrain_defs, biome_defs)        -> Dictionary — Load + normalize a board file from pre-loaded defs.
##   load_board_data_from_files(board_path, terr_path, biome_path)-> Dictionary — Convenience: load all three files then normalize.
##   build_grid_from_board(board_data)                            -> HexGrid    — Build a HexGrid from a normalized board dict.
##
## Normalization internals:
##   normalize_board_data(raw, terrain_defs, biome_defs)          -> Dictionary — Normalize the entire board dict.
##   normalize_tile_entry(raw_tile, terrain_defs)                 -> Dictionary — Merge terrain def + per-tile overrides, convert coord/tags.
##
## Conversion helpers:
##   parse_coord(value)                                           -> Vector2i  — [q, r] array → Vector2i; INVALID_COORD on failure.
##   to_string_array(value)                                       -> Array[String] — Any Variant → Array[String].

extends RefCounted
class_name MapLoader

const DEFAULT_BOARD_ID: String = "unnamed_board"
const INVALID_COORD: Vector2i = Vector2i(-9999, -9999)


# =========================================================================
#  Generic JSON helpers
# =========================================================================

## Load any JSON file and return its parsed data (or null on failure).
func load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("File does not exist: " + path)
		return null

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file: " + path)
		return null

	var json_text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var parse_result: int = json.parse(json_text)

	if parse_result != OK:
		push_error(
			"Failed to parse JSON: %s  (error code %s, line %s)" %
			[path, str(parse_result), str(json.get_error_line())]
		)
		return null

	return json.data


# =========================================================================
#  Definition loaders
# =========================================================================

## Load terrain definitions keyed by terrain_id.
func load_terrain_definitions(path: String) -> Dictionary:
	var data: Variant = load_json_file(path)
	if not (data is Dictionary):
		push_error("Terrain definitions JSON must be a Dictionary: " + path)
		return {}
	return data


## Load biome definitions keyed by biome_id.
func load_biome_definitions(path: String) -> Dictionary:
	var data: Variant = load_json_file(path)
	if not (data is Dictionary):
		push_error("Biome definitions JSON must be a Dictionary: " + path)
		return {}
	return data


# =========================================================================
#  Board loading & normalization
# =========================================================================

## Load + normalize a board file given already-loaded definition dicts.
## Returns a normalized board Dictionary (see normalize_board_data for structure).
func load_board_data(
	board_path: String,
	terrain_defs: Dictionary,
	biome_defs: Dictionary
) -> Dictionary:
	var raw: Variant = load_json_file(board_path)
	if not (raw is Dictionary):
		push_error("Board JSON must be a Dictionary: " + board_path)
		return {}
	return normalize_board_data(raw, terrain_defs, biome_defs)


## Convenience: load all three files from paths, then normalize.
## Returns a normalized board Dictionary (see normalize_board_data for structure).
func load_board_data_from_files(
	board_path: String,
	terrain_defs_path: String,
	biome_defs_path: String
) -> Dictionary:
	var terrain_defs: Dictionary = load_terrain_definitions(terrain_defs_path)
	if terrain_defs.is_empty():
		return {}
	var biome_defs: Dictionary = load_biome_definitions(biome_defs_path)
	if biome_defs.is_empty():
		return {}
	return load_board_data(board_path, terrain_defs, biome_defs)


## Build a HexGrid from an already-normalized board dictionary.
func build_grid_from_board(board_data: Dictionary) -> HexGrid:
	var grid: HexGrid = HexGrid.new()

	for tile_entry in board_data.get("tiles", []):
		if not (tile_entry is Dictionary):
			continue
		var coord: Vector2i = tile_entry.get("coord", INVALID_COORD)
		if coord == INVALID_COORD:
			continue
		grid.add_tile(coord, tile_entry)

	return grid


# =========================================================================
#  Normalization internals
# =========================================================================

## Normalize the entire board dictionary, merging biome + terrain data.
##
## Returns Dictionary with structure:
##   "id"          : String
##   "biome_id"    : String
##   "biome_data"  : Dictionary    (deep copy of the matching biome definition)
##   "seed"        : int           (if present in board JSON)
##   "board_shape" : Dictionary    (if present in board JSON)
##   "visual_style": Dictionary    (if present in board JSON)
##   "tiles"       : Array[Dictionary]  (each tile normalized via normalize_tile_entry)
##   "anchors"     : Array         (guaranteed to exist, may be empty)
##   "entities"    : Array         (guaranteed to exist, may be empty)
##   ...plus any other board-level keys preserved from the raw JSON.
func normalize_board_data(
	raw: Dictionary,
	terrain_defs: Dictionary,
	biome_defs: Dictionary
) -> Dictionary:
	# Start with a shallow copy so we preserve all board-level keys.
	var board: Dictionary = raw.duplicate(false)

	board["id"] = raw.get("id", DEFAULT_BOARD_ID)

	# --- biome attachment ---
	var biome_id: String = str(raw.get("biome_id", ""))
	if biome_id != "" and biome_defs.has(biome_id):
		board["biome_data"] = biome_defs[biome_id].duplicate(true)
	elif biome_id != "":
		push_error("biome_id '%s' not found in biome definitions" % biome_id)

	# --- ensure anchors & entities exist as arrays ---
	if not board.has("anchors") or not (board["anchors"] is Array):
		board["anchors"] = []
	if not board.has("entities") or not (board["entities"] is Array):
		board["entities"] = []

	# --- normalize tiles ---
	var normalized_tiles: Array = []
	for raw_tile in raw.get("tiles", []):
		if not (raw_tile is Dictionary):
			continue
		var norm: Dictionary = normalize_tile_entry(raw_tile, terrain_defs)
		if not norm.is_empty():
			normalized_tiles.append(norm)
	board["tiles"] = normalized_tiles

	return board


## Merge terrain definition defaults with per-tile overrides, convert coord
## to Vector2i, and normalize tags to Array[String].
##
## Returns Dictionary with structure:
##   "coord"           : Vector2i
##   "terrain_id"      : String
##   "tags"            : Array[String]
##   "terrain_class"   : String
##   "move_cost"       : int / float
##   "blocks_movement" : bool
##   "blocks_los"      : bool
##   "cover"           : bool
##   "hazard"          : bool
##   "region_group"    : String
##   "visual_roles"    : Array
##   "paint_layers"    : Array
##   "detail_rules"    : Dictionary
##   ...plus any extra fields from the terrain definition or board tile overrides.
## Returns {} on validation failure.
func normalize_tile_entry(
	raw_tile: Dictionary,
	terrain_defs: Dictionary
) -> Dictionary:
	var terrain_id: String = str(raw_tile.get("terrain_id", ""))
	if terrain_id == "":
		push_error("Tile entry missing terrain_id: " + str(raw_tile))
		return {}
	if not terrain_defs.has(terrain_id):
		push_error("terrain_id '%s' not found in terrain definitions" % terrain_id)
		return {}

	var def_variant: Variant = terrain_defs[terrain_id]
	if not (def_variant is Dictionary):
		push_error("Terrain definition for '%s' must be a Dictionary." % terrain_id)
		return {}

	# 1. Start from terrain definition defaults (deep copy).
	var result: Dictionary = (def_variant as Dictionary).duplicate(true)

	# 2. Overwrite with per-tile board fields.
	for key in raw_tile.keys():
		result[key] = raw_tile[key]

	# 3. Ensure terrain_id is stored.
	result["terrain_id"] = terrain_id

	# 4. Normalize coord -> Vector2i.
	var parsed: Vector2i = parse_coord(raw_tile.get("coord", null))
	if parsed == INVALID_COORD:
		push_error("Invalid coord for tile: " + str(raw_tile))
		return {}
	result["coord"] = parsed

	# 5. Normalize tags -> Array[String].
	result["tags"] = to_string_array(result.get("tags", []))

	return result


# =========================================================================
#  Conversion helpers
# =========================================================================

## Parse a JSON [q, r] array (which may arrive as floats) into Vector2i.
func parse_coord(value: Variant) -> Vector2i:
	if value is Array and value.size() == 2:
		if (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			return Vector2i(int(value[0]), int(value[1]))
	return INVALID_COORD


## Convert any Variant into an Array[String]; non-array values yield [].
func to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result
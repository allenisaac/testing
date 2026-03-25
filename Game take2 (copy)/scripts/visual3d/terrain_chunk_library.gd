## TerrainChunkLibrary — maps terrain_id to chunk scenes for 3D board generation.
## Chunk scenes live under res://scenes/board3d/chunks/.
## Uses load() instead of preload() so missing scenes fail gracefully at runtime.

extends RefCounted
class_name TerrainChunkLibrary


## Base path where chunk scenes are expected.
const CHUNK_BASE_PATH: String = "res://scenes/board3d/chunks/"

## Mapping of terrain_id -> chunk scene filename.
## Add entries here as chunk scenes are authored.
var terrain_scene_names: Dictionary = {
	"village_clearing": "village_clearing_chunk.tscn",
	"boardwalk": "boardwalk_chunk.tscn",
	"hut_platform": "hut_platform_chunk.tscn",
	"marsh_grass": "marsh_ground_chunk.tscn",
	"mud_flat": "mud_flat_chunk.tscn",
	"reed_bank": "reed_bank_chunk.tscn",
	"shallow_water": "shallow_water_chunk.tscn",
	"deep_water": "deep_water_chunk.tscn",
	"stone_plinth": "stone_plinth_chunk.tscn",
}

## Cache of loaded scenes so we only load each once.
var _scene_cache: Dictionary = {}


## Return the chunk PackedScene for a given tile, or null if unavailable.
func get_chunk_scene_for_tile(tile_data: Dictionary) -> PackedScene:
	var terrain_id: String = str(tile_data.get("terrain_id", ""))

	if not terrain_scene_names.has(terrain_id):
		return null

	# Return from cache if already loaded.
	if _scene_cache.has(terrain_id):
		return _scene_cache[terrain_id]

	var scene_path: String = CHUNK_BASE_PATH + terrain_scene_names[terrain_id]
	if not ResourceLoader.exists(scene_path):
		return null

	var scene: PackedScene = load(scene_path) as PackedScene
	if scene != null:
		_scene_cache[terrain_id] = scene
	return scene
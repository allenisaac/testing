## Base class for tile-level feature handlers.
##
## Each subclass handles one type of feature that can be placed on or spanning
## tiles — e.g. boardwalk, tree, rock, ruins — and is responsible for
## spawning its geometry, props, and any structural/gameplay elements.
##
## Registered handlers are invoked by HexBoard3D after all terrain passes,
## receiving the same "shared" params dict that TerrainType handlers receive,
## plus shared["tiles"] which is the full board tiles Dictionary so handlers
## can do neighbour lookups.
##
## Data model in the map JSON:
##   tile_feature: String | null  — whole-tile feature (e.g. "tree", "rock")
##   edge_features: [...]         — per-edge directional features (e.g. "boardwalk")
##
## Feature handlers that need edge connectivity (like boardwalk) should
## override collect_tiles() to filter by edge_features instead.
class_name TileFeature
extends Resource


## The tile_feature string value this handler responds to.
## Used by the default collect_tiles() implementation.
## Override collect_tiles() directly for edge-based or multi-key filtering.
func get_feature_id() -> String:
	return ""


## Return the subset of all_tiles relevant to this feature.
##
## Default: tiles where tile_data["tile_feature"] == get_feature_id().
## Override for edge-based features (e.g. BoardwalkBuilder uses edge_features).
func collect_tiles(all_tiles: Dictionary) -> Dictionary:
	var own: Dictionary = {}
	var fid: String = get_feature_id()
	if fid.is_empty():
		return own
	for coord: Vector2i in all_tiles.keys():
		var td: Dictionary = all_tiles[coord]
		if (td.get("tile_feature", "") as String) == fid:
			own[coord] = td
	return own


## Spawn all geometry and props for own_tiles.
##
## parent   — the board's Tiles Node3D (same parent as terrain meshes).
## own_tiles — filtered tile subset returned by collect_tiles().
## shared   — shared params dict from HexBoard3D (shaders, etc.); also
##            contains shared["tiles"] for full-board neighbour lookups.
func spawn(_parent: Node3D, _own_tiles: Dictionary, _shared: Dictionary) -> void:
	pass

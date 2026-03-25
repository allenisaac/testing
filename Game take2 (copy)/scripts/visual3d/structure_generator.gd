## StructureGenerator — spawns 3D structure nodes (huts, boardwalks, plinths,
## etc.) based on terrain_id or anchor data from the board JSON.

extends RefCounted
class_name StructureGenerator


## Iterate board tiles and anchors, spawn structure scenes under parent.
func generate_structures(
	board_data: Dictionary,
	_parent: Node3D,
	_hex_size: float
) -> void:
	# TODO: match terrain_id / anchor data to structure scenes and instantiate
	var tiles: Array = board_data.get("tiles", [])
	var anchors: Array = board_data.get("anchors", [])

	for tile in tiles:
		if not (tile is Dictionary):
			continue
		# Future: check terrain_class == "structure" and spawn appropriate mesh
		pass

	for anchor in anchors:
		if not (anchor is Dictionary):
			continue
		# Future: spawn anchor-driven feature clusters
		pass

## ScatterGenerator — places billboard props and small detail meshes
## (reeds, flowers, mushrooms, pebbles, etc.) across the board surface
## using detail_rules from terrain definitions and biome scatter settings.

extends RefCounted
class_name ScatterGenerator


## Scatter detail objects across the board surface.
## Uses field_data for height placement and board_data for per-tile rules.
func scatter_details(
	board_data: Dictionary,
	_field_data: Dictionary,
	_parent: Node3D,
	_hex_size: float
) -> void:
	# TODO: iterate tiles, read detail_rules, place scatter instances
	var tiles: Array = board_data.get("tiles", [])

	for tile in tiles:
		if not (tile is Dictionary):
			continue

		var detail_rules: Dictionary = tile.get("detail_rules", {})
		if detail_rules.is_empty():
			continue

		# Future: use clutter_density, allowed props, RNG seed to scatter
		pass

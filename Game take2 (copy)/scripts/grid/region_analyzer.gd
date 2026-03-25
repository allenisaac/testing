extends RefCounted
class_name RegionAnalyzer


func build_tile_lookup(board_data: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var tiles: Array = board_data.get("tiles", [])

	for tile in tiles:
		if not (tile is Dictionary):
			continue

		var coord: Vector2i = tile.get("coord", Vector2i.ZERO)
		lookup[coord] = tile

	return lookup


func find_regions_by_group(board_data: Dictionary, region_group: String) -> Array[Dictionary]:
	var tile_lookup: Dictionary = build_tile_lookup(board_data)
	var visited: Dictionary = {}
	var regions: Array[Dictionary] = []
	var region_id: int = 0

	for coord in tile_lookup.keys():
		if visited.has(coord):
			continue

		var tile_data: Dictionary = tile_lookup[coord]
		if tile_data.get("region_group", "") != region_group:
			continue

		var region_coords: Array[Vector2i] = flood_region(coord, region_group, tile_lookup, visited)
		var edge_coords: Array[Vector2i] = find_edge_coords(region_coords, region_group, tile_lookup)

		regions.append({
			"region_id": region_id,
			"region_group": region_group,
			"coords": region_coords,
			"size": region_coords.size(),
			"edge_coords": edge_coords
		})

		region_id += 1

	return regions


func flood_region(
	start_coord: Vector2i,
	region_group: String,
	tile_lookup: Dictionary,
	visited: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var open_list: Array[Vector2i] = [start_coord]

	while not open_list.is_empty():
		var current: Vector2i = open_list.pop_back()

		if visited.has(current):
			continue

		visited[current] = true

		if not tile_lookup.has(current):
			continue

		var tile_data: Dictionary = tile_lookup[current]
		if tile_data.get("region_group", "") != region_group:
			continue

		result.append(current)

		var neighbors: Array[Vector2i] = HexCoords.all_neighbors(current)
		for neighbor in neighbors:
			if not visited.has(neighbor):
				open_list.append(neighbor)

	return result


func find_edge_coords(
	region_coords: Array[Vector2i],
	region_group: String,
	tile_lookup: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var region_set: Dictionary = {}

	for coord in region_coords:
		region_set[coord] = true

	for coord in region_coords:
		var neighbors: Array[Vector2i] = HexCoords.all_neighbors(coord)
		var is_edge: bool = false

		for neighbor in neighbors:
			if not tile_lookup.has(neighbor):
				is_edge = true
				break

			var neighbor_data: Dictionary = tile_lookup[neighbor]
			if neighbor_data.get("region_group", "") != region_group:
				is_edge = true
				break

		if is_edge:
			result.append(coord)

	return result
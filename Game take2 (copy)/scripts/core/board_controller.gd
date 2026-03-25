## BoardController — scene orchestrator for loading, building, and
## interacting with the hex board.
##
## Lifecycle:
##   _ready()                         — Loads board data then builds visuals.
##   load_board_data()                — Loads board/terrain/biome JSON, normalizes, and builds HexGrid.
##   build_board_visuals()            — Iterates normalized tiles and spawns HexTile nodes.
##   spawn_tile(tile_data)            — Instantiates one HexTile, positions it, connects signals.
##
## Tile node helpers:
##   get_tile_node(coord) -> HexTile  — Look up the HexTile node at a coord (null on miss).
##   refresh_tile_visual(coord)       — Apply selected/hovered/default visual state to a tile.
##
## Interaction callbacks (connected to HexTile signals):
##   _on_tile_hovered(coord)          — Track hover state and refresh visuals.
##   _on_tile_unhovered(coord)        — Clear hover state and refresh visuals.
##   _on_tile_clicked(coord)          — Track selection state and refresh visuals.
##
## Tooltip placeholders:
##   update_tile_tooltip(coord)       — TODO: populate tooltip UI.
##   clear_tile_tooltip()             — TODO: hide tooltip UI.
##
## Key runtime state:
##   board_data          : Dictionary — The full normalized board dictionary.
##   hex_grid            : HexGrid    — Logical tile + unit state.
##   tile_nodes_by_coord : Dictionary — { Vector2i : HexTile } visual node lookup.
##   hovered_coord       : Vector2i   — Currently hovered tile (INVALID_COORD if none).
##   selected_coord      : Vector2i   — Currently selected tile (INVALID_COORD if none).

class_name BoardController
extends Node2D


# =========================================================================
#  Exports / config
# =========================================================================

@export var board_data_path: String = "res://data/boards/frog_village_test_01.json"
@export var terrain_defs_path: String = "res://data/terrain/terrain_definitions.json"
@export var biome_defs_path: String = "res://data/biomes/biome_definitions.json"
@export var hex_size: float = 48.0
@export var tile_scene: PackedScene = preload("res://scenes/board/HexTile.tscn")


# =========================================================================
#  State
# =========================================================================

enum State {
	IDLE,
	HOVERING,
	TILE_SELECTED
}

var state: State = State.IDLE

const INVALID_COORD: Vector2i = Vector2i(-9999, -9999)

@onready var terrain_layer: Node2D = $TerrainLayer

var map_loader: MapLoader = MapLoader.new()
var hex_grid: HexGrid = HexGrid.new()
var board_data: Dictionary = {}
var tile_nodes_by_coord: Dictionary = {}
var hovered_coord: Vector2i = INVALID_COORD
var selected_coord: Vector2i = INVALID_COORD


# =========================================================================
#  Lifecycle
# =========================================================================

func _ready() -> void:
	load_board_data()
	build_board_visuals()


func load_board_data() -> void:
	board_data = map_loader.load_board_data_from_files(
		board_data_path, terrain_defs_path, biome_defs_path
	)
	if board_data.is_empty():
		push_error("Failed to load board data")
		return
	hex_grid = map_loader.build_grid_from_board(board_data)


func build_board_visuals() -> void:
	for tile_entry in board_data.get("tiles", []):
		if not (tile_entry is Dictionary):
			continue
		spawn_tile(tile_entry)


func spawn_tile(tile_data: Dictionary) -> void:
	var hex_tile: HexTile = tile_scene.instantiate() as HexTile
	if hex_tile == null:
		push_error("Failed to instantiate HexTile scene")
		return

	var coord: Vector2i = tile_data.get("coord", INVALID_COORD)
	if coord == INVALID_COORD:
		push_error("Tile data missing valid 'coord': " + str(tile_data))
		return

	hex_tile.position = HexCoords.to_world(coord, hex_size)

	# Add to tree first so @onready references resolve before setup().
	terrain_layer.add_child(hex_tile)
	hex_tile.setup(tile_data, hex_size)

	# Connect signals.
	hex_tile.tile_hovered.connect(_on_tile_hovered)
	hex_tile.tile_unhovered.connect(_on_tile_unhovered)
	hex_tile.tile_clicked.connect(_on_tile_clicked)

	tile_nodes_by_coord[coord] = hex_tile


# =========================================================================
#  Tile node helpers
# =========================================================================

func get_tile_node(coord: Vector2i) -> HexTile:
	if tile_nodes_by_coord.has(coord):
		return tile_nodes_by_coord[coord] as HexTile
	return null


func refresh_tile_visual(coord: Vector2i) -> void:
	var tile: HexTile = get_tile_node(coord)
	if tile == null:
		return

	if coord == selected_coord:
		tile.set_selected_visual_state()
	elif coord == hovered_coord:
		tile.set_hovered_visual_state()
	else:
		tile.set_default_visual_state()


# =========================================================================
#  Interaction callbacks
# =========================================================================

func _on_tile_hovered(coord: Vector2i) -> void:
	var old_hovered: Vector2i = hovered_coord
	hovered_coord = coord
	state = State.HOVERING
	if old_hovered != INVALID_COORD:
		refresh_tile_visual(old_hovered)
	refresh_tile_visual(coord)
	update_tile_tooltip(coord)


func _on_tile_unhovered(coord: Vector2i) -> void:
	if hovered_coord == coord:
		hovered_coord = INVALID_COORD
		if state == State.HOVERING:
			state = State.IDLE
	refresh_tile_visual(coord)
	clear_tile_tooltip()


func _on_tile_clicked(coord: Vector2i) -> void:
	var old_selected: Vector2i = selected_coord
	selected_coord = coord
	state = State.TILE_SELECTED
	if old_selected != INVALID_COORD:
		refresh_tile_visual(old_selected)
	refresh_tile_visual(coord)


# =========================================================================
#  Tooltip placeholders
# =========================================================================

func update_tile_tooltip(_coord: Vector2i) -> void:
	# TODO: populate tooltip UI with tile info from hex_grid.get_tile_data()
	pass


func clear_tile_tooltip() -> void:
	# TODO: hide tooltip UI
	pass
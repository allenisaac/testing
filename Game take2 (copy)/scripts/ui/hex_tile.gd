## HexTile — visual / interactable tile node (Area2D root).

extends Area2D
class_name HexTile

# =========================================================================
#  Signals
# =========================================================================

signal tile_clicked(coord: Vector2i)
signal tile_hovered(coord: Vector2i)
signal tile_unhovered(coord: Vector2i)

# =========================================================================
#  Child references
# =========================================================================

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionPolygon2D = $Collision

# =========================================================================
#  Placeholder texture mapping (will be replaced by biome/terrain rendering)
# =========================================================================

const TEXTURES: Dictionary = {
	"grass_easy_a": preload("res://assets/terrain/grass_easy_a.png"),
	"water_blocked_a": preload("res://assets/terrain/water_blocked_a.png"),
	"sand_difficult_a": preload("res://assets/terrain/sand_difficult_a.png"),
	"cave_covered_a": preload("res://assets/terrain/cave_covered_a.png"),
}

# =========================================================================
#  Runtime tile state
# =========================================================================

var tile_data: Dictionary = {}
var coord: Vector2i = Vector2i(0, 0)
var terrain_id: String = ""
var tags: Array[String] = []


# =========================================================================
#  Lifecycle
# =========================================================================

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


## Call after the node has been added to the tree (so @onready refs exist).
func setup(tile: Dictionary, hex_size: float) -> void:
	tile_data = tile.duplicate(true)
	coord = tile.get("coord", Vector2i(0, 0))
	terrain_id = str(tile.get("terrain_id", ""))
	tags = to_string_array(tile.get("tags", []))

	update_visual()
	apply_hex_sprite_scale(hex_size)
	apply_hex_collision(hex_size)


# =========================================================================
#  Visuals
# =========================================================================

## Temporary: pick a texture from the placeholder map. Falls back to
## terrain_id lookup, then to a blank sprite if nothing matches.
func update_visual() -> void:
	# Try terrain_id first, then fall back to legacy visual_id if present.
	var lookup_key: String = terrain_id
	if lookup_key == "":
		lookup_key = str(tile_data.get("visual_id", ""))

	if TEXTURES.has(lookup_key):
		sprite.texture = TEXTURES[lookup_key]
	else:
		# No placeholder texture for this terrain — leave sprite blank.
		sprite.texture = null


## --- visual-state helpers (modify sprite.modulate, not node modulate) ---

func set_default_visual_state() -> void:
	sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)


func set_hovered_visual_state() -> void:
	sprite.modulate = Color(0.8, 0.8, 1.0, 1.0)


func set_selected_visual_state() -> void:
	sprite.modulate = Color(1.0, 0.8, 0.8, 1.0)


# =========================================================================
#  Geometry helpers
# =========================================================================

## Scale sprite to match pointy-top hex dimensions.
func apply_hex_sprite_scale(hex_size: float) -> void:
	if sprite == null or sprite.texture == null:
		return
	var target_width: float = sqrt(3.0) * hex_size
	var target_height: float = 2.0 * hex_size
	var tex_size: Vector2 = sprite.texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		push_error("Invalid texture size: " + str(tex_size))
		return
	sprite.scale = Vector2(
		target_width / tex_size.x,
		target_height / tex_size.y
	)


## Generate a pointy-top hex collision polygon from hex_size.
func apply_hex_collision(hex_size: float) -> void:
	if collision_shape == null:
		return
	var hw: float = sqrt(3.0) * 0.5 * hex_size
	var hh: float = 0.5 * hex_size

	collision_shape.polygon = PackedVector2Array([
		Vector2(0.0, -hex_size),     # top
		Vector2(hw, -hh),            # upper-right
		Vector2(hw, hh),             # lower-right
		Vector2(0.0, hex_size),      # bottom
		Vector2(-hw, hh),            # lower-left
		Vector2(-hw, -hh)            # upper-left
	])


# =========================================================================
#  Mouse interaction handlers
# =========================================================================

func _on_mouse_entered() -> void:
	tile_hovered.emit(coord)


func _on_mouse_exited() -> void:
	tile_unhovered.emit(coord)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(coord)


# =========================================================================
#  Utility
# =========================================================================

## Convert any Variant to Array[String]; non-array values yield [].
static func to_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			result.append(str(item))
	return result

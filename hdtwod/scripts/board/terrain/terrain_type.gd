## Base class for terrain type handlers.
## Each subclass defines the visual appearance of one terrain type and
## is responsible for building tile materials and spawning any terrain-specific
## props (e.g. grass blades, rocks) for the tiles it owns.
class_name TerrainType
extends Resource

## Base surface color for this terrain. Noise shifts are applied relative to this.
var color_base: Color = Color.WHITE


## Return a ShaderMaterial for a tile mesh belonging to this terrain type.
## shared: Dictionary with global shader parameters (see HexBoard3D._make_shared_params()).
func get_tile_material(_shared: Dictionary) -> ShaderMaterial:
    return ShaderMaterial.new()


## Return a ShaderMaterial for the side-wall surface (surface 1) of tile meshes.
## Return null to leave side walls without a dedicated material (falls back to
## the mesh's default / no override).
## shared: Dictionary with global shader parameters (see HexBoard3D._make_shared_params()).
func get_side_material(_shared: Dictionary) -> ShaderMaterial:
    return null


## Spawn terrain-specific props (e.g. grass, rocks) for the tiles this handler owns.
## own_tiles: subset of the board tiles Dictionary that match this terrain type.
## shared: Dictionary with global shader parameters (see HexBoard3D._make_shared_params()).
func spawn_props(_parent: Node3D, _own_tiles: Dictionary, _shared: Dictionary) -> void:
    pass

## Optional override for height offset of props spawned by this terrain type.
func get_height_offset() -> float:
    return 0.0
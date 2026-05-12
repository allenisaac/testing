# Adding a New Terrain Type

Terrain handlers are `Resource` subclasses (`extends TerrainType`). All visual
parameters are declared as `@export` properties so they can be configured in the
Godot Inspector or saved as `.tres` files.

## 1. Create the handler script

Create `scripts/board/terrain/terrain_<name>.gd`:

```gdscript
class_name TerrainStone
extends TerrainType

@export_group("Tile Surface")
@export var albedo1: Color = Color(0.55, 0.55, 0.55)

@export_subgroup("Albedo 2")
@export var albedo2_hsl: Vector3 = Vector3(0.0, -0.2, 0.1)
@export var albedo2_noise: Texture2D = load("res://art/Albedo2.tres")
@export var albedo2_scale: float = 0.11
@export var albedo2_threshold: float = 0.3

@export_subgroup("Albedo 3")
@export var albedo3_hsl: Vector3 = Vector3(0.0, -0.1, -0.08)
@export var albedo3_noise: Texture2D = load("res://art/Albedo3.tres")
@export var albedo3_scale: float = 0.1
@export var albedo3_threshold: float = 0.5

@export_group("Toon Lighting")
@export var cuts: int = 5
@export var wrap: float = 0.0
@export var steepness: float = 1.0
@export var ambient_min: float = 0.15
@export var threshold_gradient_size: float = 0.2

@export_group("Tile Sides")
@export var side_albedo: Texture2D
@export var side_normal: Texture2D


func get_tile_material(shared: Dictionary) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = shared["tile_shader"]
    RenderUtils.apply_common_surface_params(mat, self)
    RenderUtils.attach_edge_detection_pass(mat)
    return mat


func get_side_material(shared: Dictionary) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = shared["tile_side_shader"]
    RenderUtils.apply_common_surface_params(mat, self)
    if side_albedo != null:
        mat.set_shader_parameter("side_albedo", side_albedo)
    if side_normal != null:
        mat.set_shader_parameter("side_normal", side_normal)
    return mat


func spawn_props(_parent: Node3D, _own_tiles: Dictionary, _shared: Dictionary) -> void:
    pass   # spawn rocks, decals, etc. here
```

`RenderUtils.apply_common_surface_params(mat, self)` reads all the `@export`
properties above (`albedo1`, `albedo2_hsl`, `cuts`, etc.) and sets the
corresponding shader uniforms. You do not need to set them manually.

`albedo2` and `albedo3` colors are derived at runtime by shifting `albedo1`
through HSL space using the delta vectors, so changing `albedo1` alone produces
a coherent palette.

## 2. Register the type in HexBoard3D

Open `scripts/board/hex_board_3d.gd` and:

a) Add an export variable at the top of the class:

```gdscript
@export var stone_terrain: TerrainStone
```

b) Register it in `_ready()` where the other terrain types are registered:

```gdscript
_terrain_types["stone"] = stone_terrain if stone_terrain else TerrainStone.new()
```

## 3. Use the type in map data

In any map JSON file, set `"terrain_type"` on a tile to your new key:

```json
{ "q": 2, "r": 0, "elevation": 0, "terrain_type": "stone", "ramp_edges": [...] }
```

Tiles with an unrecognised `terrain_type` fall back to `"grass"` automatically.

## 4. (Optional) Assign a resource in the scene

If you want to tune the terrain without editing code, create a `.tres` file
(`TerrainStone` resource) in the Godot editor, configure it in the Inspector,
then assign it to the `stone_terrain` export on the `HexBoard3D` node.

---

## How `shared` parameters work

`HexBoard3D._make_shared_params()` builds a Dictionary passed to
`get_tile_material()`, `get_side_material()`, and `spawn_props()`. It contains
only the **shared infrastructure** — shaders and the collision mask. All
per-terrain visual parameters live on the `TerrainType` resource itself.

| Key                      | Type    | Description                                  |
|--------------------------|---------|----------------------------------------------|
| `tile_shader`            | Shader  | `tile_surface.gdshader`                      |
| `tile_side_shader`       | Shader  | `tile_side.gdshader`                         |
| `grass_shader`           | Shader  | `grass_billboard.gdshader`                   |
| `grass_overhang_shader`  | Shader  | `grass_overhang.gdshader`                    |
| `terrain_collision_mask` | int     | Collision mask for terrain `StaticBody3D`s   |
| `terrain_placement_layer`| int     | Collision layer set on tile `StaticBody3D`s  |

---

## TerrainType interface

| Method | Required | Description |
|--------|----------|-------------|
| `get_tile_material(shared)` | Yes | Returns `ShaderMaterial` for the top face (surface 0) |
| `get_side_material(shared)` | No | Returns `ShaderMaterial` for cliff walls (surface 1); return `null` to skip |
| `spawn_props(parent, own_tiles, shared)` | No | Spawn grass, rocks, etc. under `parent` |
| `get_height_offset()` | No | Y offset applied to the tile mesh top (default 0.0) |

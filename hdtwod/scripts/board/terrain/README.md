# Adding a New Terrain Type

## 1. Create the handler script

Create `scripts/board/terrain/terrain_<name>.gd`:

```gdscript
class_name TerrainDirt        # rename to match your terrain
extends TerrainType

func _init() -> void:
    color_base = Color(0.45, 0.30, 0.18)   # set your terrain's base color here


func get_tile_material(shared: Dictionary) -> ShaderMaterial:
    var mat := ShaderMaterial.new()
    mat.shader = shared["tile_shader"]
    mat.set_shader_parameter("color_base",         color_base)
    mat.set_shader_parameter("sun_direction",      shared["sun_direction"])
    mat.set_shader_parameter("ambient_min",        shared["ambient_min"])
    mat.set_shader_parameter("shade_cuts",         shared["shade_cuts"])
    mat.set_shader_parameter("coarse_noise",       shared["coarse_noise"])
    mat.set_shader_parameter("coarse_noise_scale", shared["coarse_noise_scale"])
    mat.set_shader_parameter("fine_noise",         shared["fine_noise"])
    mat.set_shader_parameter("fine_noise_scale",   shared["fine_noise_scale"])
    mat.set_shader_parameter("noise_hue_range",    shared["noise_hue_range"])
    mat.set_shader_parameter("noise_sat_range",    shared["noise_sat_range"])
    mat.set_shader_parameter("noise_bri_range",    shared["noise_bri_range"])
    return mat


func spawn_props(parent: Node3D, own_tiles: Dictionary, shared: Dictionary) -> void:
    pass   # spawn rocks, decals, etc. here; leave empty if the terrain has no props
```

The HSV noise (coarse → brightness, fine → hue/saturation) is driven entirely by
`color_base`, so changing that one color is all that is needed for a new look.

## 2. Register the type in HexBoard3D

Open `scripts/board/hex_board_3d.gd` and add your class to the `_terrain_types` dictionary:

```gdscript
var _terrain_types: Dictionary = {
    "grass": TerrainGrass.new(),
    "dirt":  TerrainDirt.new(),   # <-- add this line
}
```

## 3. Use the type in map data

In any map JSON file, set `"terrain_type"` on a tile to your new key:

```json
{ "q": 2, "r": 0, "elevation": 0, "terrain_type": "dirt", "ramp_edges": [...] }
```

Tiles with an unrecognised `terrain_type` fall back to `"grass"` automatically.

---

## How `shared` parameters work

`HexBoard3D._make_shared_params()` builds a Dictionary that is passed to both
`get_tile_material()` and `spawn_props()`. It contains:

| Key                  | Type       | Description                              |
|----------------------|------------|------------------------------------------|
| `tile_shader`        | Shader     | `tile_surface.gdshader`                  |
| `grass_shader`       | Shader     | `grass_billboard.gdshader`               |
| `sun_direction`      | Vector3    | Direction light comes FROM               |
| `ambient_min`        | float      | Shadow floor brightness (0–1)            |
| `shade_cuts`         | int        | Toon shading steps                       |
| `coarse_noise`       | Texture2D  | Large-feature noise → brightness shifts  |
| `coarse_noise_scale` | float      | Sampling frequency for coarse noise      |
| `fine_noise`         | Texture2D  | Small-feature noise → hue/sat shifts     |
| `fine_noise_scale`   | float      | Sampling frequency for fine noise        |
| `noise_hue_range`    | float      | Max hue delta (HSV 0–1 units)            |
| `noise_sat_range`    | float      | Max saturation multiplier offset         |
| `noise_bri_range`    | float      | Max brightness multiplier offset         |

All noise values are configured globally on the `HexBoard3D` node and affect
every terrain type equally.

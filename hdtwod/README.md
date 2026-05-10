# hdtwod — Hex Tactics 2.5D

Godot 4 isometric tactics game prototype. Hex grid, flat-shaded pixel-art look rendered through a SubViewport, with billboard grass and fullscreen edge detection.

---

## Project Structure

```
data/maps/          JSON map files
scripts/
  board/            HexBoard3D, HexMeshBuilder, GrassSpawner
  grid/             HexCoord (pure hex math — no Godot nodes)
  mesh/             (reserved for future mesh utilities)
  core/             (reserved for game logic)
shaders/
  tile_surface.gdshader    Hex tile surface material
  grass_billboard.gdshader Billboard grass blades
  edge_detection.gdshader  Fullscreen post-process outlines
scenes/
  board/            Reusable board scene (hex_board_3d.tscn)
  test/             Test scenes — start here
art/                Textures (.png, .tres noise resources)
```

---

## Rendering Pipeline

Everything renders inside a **SubViewport** at a fixed pixel resolution (640×360). A `CanvasLayer / TextureRect` blits it to the screen with nearest-neighbour filtering to get the pixel-art look.

```
SubViewport (640×360)
  ├─ Camera3D
  │    └─ MeshInstance3D  ← QuadMesh (2×2, flip_faces=true)
  │                          ShaderMaterial → edge_detection.gdshader
  │                          (fullscreen post-process, child of camera so it
  │                           always covers the screen in clip space)
  ├─ WorldEnvironment
  ├─ DirectionalLight3D   ← present but NOT used by tile/grass shaders
  └─ HexBoard3D
       └─ Tiles/
            ├─ Tile_0_0   MeshInstance3D  → tile_surface.gdshader
            ├─ Tile_1_0   ...
            └─ Grass       MultiMeshInstance3D → grass_billboard.gdshader
```

### Why unshaded?

Tile and grass shaders use `render_mode unshaded`. This bypasses Godot's lighting pass entirely. Shading is computed manually so it is **deterministic and camera-independent** — essential for pixel art where indirect or specular lighting would break the flat look.

The `DirectionalLight3D` in the scene is kept for environment ambient (fog, sky) but does not affect tile or grass colour.

---

## Shaders

### `tile_surface.gdshader`

Renders each hex tile mesh.

**Technique: manual toon shading**

```glsl
NdotL = dot(normalize(world_normal), normalize(sun_direction))
shade = mix(ambient_min, 1.0, floor(NdotL * shade_cuts) / shade_cuts)
ALBEDO = zone_color * shade
```

`world_normal` is computed in `vertex()` from `MODEL_MATRIX * NORMAL` so flat normals (set explicitly by `HexMeshBuilder`) survive correctly. The top face is brightest, side cliffs are darker — all controlled by `sun_direction`.

**Technique: Dylearn-style color zones**

Three layers evaluated at `world_pos.xz` (world-space, not UV-space):

| Layer | When active |
|---|---|
| `color_base` | Always (fallback) |
| `color2` | `noise2.r > color2_threshold` |
| `color3` | `noise3.r > color3_threshold` |

Layers 2 and 3 are hard-threshold overrides (not blends). Setting a high threshold (e.g. 0.85) for zone 3 gives sparse accent patches.

**Edge detection opt-in:** writes `ROUGHNESS = 1.0` so the roughness GBuffer alpha is non-zero → `ceil(roughness)` mask in the edge shader includes this surface.

---

### `grass_billboard.gdshader`

Renders all grass blades as a single `MultiMeshInstance3D`.

**Billboard technique:** overrides `MODELVIEW_MATRIX` each vertex to face the camera, preserving only the world translation of the instance:

```glsl
MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
    INV_VIEW_MATRIX[0].xyz,   // camera right
    INV_VIEW_MATRIX[1].xyz,   // camera up
    INV_VIEW_MATRIX[2].xyz,   // camera forward
    MODEL_MATRIX[3]           // world position
);
```

**Color matching tiles:** zones are sampled at `world_origin.xz` (the blade's anchor point, constant across all vertices of that blade) using the same noise textures, scales, thresholds, and colors as `tile_surface.gdshader`. Shade is computed for a perfectly upward-facing surface:

```glsl
NdotL_top = max(normalize(sun_direction).y, 0.0)
```

This is equivalent to `dot(UP, sun_direction)` — exactly the shade the tile's top face gets. Blades always match the surface beneath them.

**Wind:** samples a `wind_noise` texture animated by `TIME * wind_speed`. Applies a `rotate_axis()` tilt of up to `wind_strength` degrees from vertical, only to the upper half of the quad (lower half stays anchored).

**Edge detection opt-out:** writes `ROUGHNESS = 0.0` so the roughness alpha is 0 → `ceil(0) = 0` → excluded from edge detection mask. No outlines on grass blades.

---

### `edge_detection.gdshader`

Fullscreen post-process applied by a camera-child QuadMesh.

**Setup requirements:**
- QuadMesh: size `(2, 2)`, `flip_faces = true`
- Parent: `Camera3D` (not a sibling in the scene)
- `vertex()` overrides `POSITION = vec4(VERTEX.xy, 1.0, 1.0)` to pin the quad to clip space regardless of camera movement
- `render_mode specular_disabled, ambient_light_disabled` — the `light()` function returns `DIFFUSE_LIGHT = vec3(1.0)` so ALBEDO passes through unmodified

**Edge detection mask (which surfaces get outlines):**

```glsl
float mask = ceil(texture(NORMAL_TEXTURE, uv).a);  // a = roughness
```

- `roughness = 1.0` in tile shader → included (mask = 1)
- `roughness = 0.0` in grass shader → excluded (mask = 0)
- To exclude any future surface from outlines: set `ROUGHNESS = 0.0` in its fragment shader

**Two edge signals:**

1. **Depth edges** — accumulates `clamp(neighbor_depth - center_depth, 0, 1)` over 4 neighbours. Detects silhouettes and depth discontinuities (cliff edges, tile height steps).

2. **Normal edges** — uses `NormalEdgeIndicator` (Kody King / Three.js): detects surface normal discontinuities between adjacent pixels (top face vs. cliff face boundary).

**Tuning uniforms (Inspector on the MeshInstance3D):**

| Uniform | Effect | Default |
|---|---|---|
| `enabled` | Toggle all outlines | `true` |
| `depth_threshold` | How large a depth jump triggers an edge | `0.25` |
| `normal_threshold` | How large a normal difference triggers an edge | `0.2` |
| `line_alpha` | Edge opacity | `0.85` |
| `line_highlight` | Brightness added on bright edges | `0.35` |
| `line_shadow` | Darkness multiplier on dark edges | `0.65` |
| `debug_view` | See below | `0` |

**Debug views** (`debug_view` uniform):

| Value | Shows |
|---|---|
| `0` | Normal output |
| `1` | Linear depth as gray (tiles = varying grays, sky = black) |
| `2` | Geometry mask (white = will get outlines, black = sky or excluded) |
| `3` | Depth edge signal only |
| `4` | Normal edge signal only |

---

## Scripts

### `HexCoord` (`scripts/grid/hex_coord.gd`)

Pure static hex math, no Godot nodes. Pointy-top axial coordinate system.

```
Directions:  0=E  1=NE  2=NW  3=W  4=SW  5=SE
```

Key constants:
- `RADIUS = 1.0` — center-to-corner distance
- `TOP_INSET = 0.65` — inner ring radius for the beveled top face
- `ELEVATION_STEP = 0.2` — world-unit height per elevation integer

Key functions:
- `axial_to_world(hex, size) → Vector3` — axial coord to world XZ position
- `elevation_to_height(elevation) → float`
- `get_neighbor(hex, dir) → Vector2i`
- `distance(a, b) → int` — hex grid steps

---

### `HexMeshBuilder` (`scripts/board/hex_mesh_builder.gd`)

Builds an `ArrayMesh` for a single hex tile using `SurfaceTool`. Explicit normals per triangle — **never call `generate_normals()`** (it averages normals, breaking the flat-shaded look).

Each tile consists of:
- **Inner top** — hexagon inset by `TOP_INSET`, giving a subtle bevel
- **6 edge sectors** — one per hex direction, typed as:
  - `FLAT` — neighbour at same elevation; sector becomes part of the top surface
  - `RAMP` — neighbour one step lower and flagged as ramp in JSON; sloped quad
  - `CLIFF` — neighbour at lower elevation or absent; vertical wall

Corner heights are resolved so dual-ramp corners don't spike upward.

---

### `HexBoard3D` (`scripts/board/hex_board_3d.gd`)

Scene root for the board. Loads a JSON map, spawns tile meshes, then spawns grass.

**Map format** (`data/maps/*.json`):

```json
{
  "tiles": [
    {
      "q": 0,  "r": 0,
      "elevation": 2,
      "ramp_edges": [true, true, false, false, true, false]
    }
  ]
}
```

`ramp_edges` is a 6-element bool array indexed by direction (0=E … 5=SE).

**Inspector groups:**

*Tile Appearance* — `color_base`, `color2_*`, `color3_*`, `sun_direction`, `ambient_min`, `shade_cuts`

*Grass* — `grass_blade_texture`, `grass_wind_noise`, `grass_blade_spacing`

The grass and tile shaders share identical color zone + lighting uniforms. `HexBoard3D._make_grass_material()` copies them all from the board's own exports, so changing one export updates both.

---

### `GrassSpawner` (`scripts/board/grass_spawner.gd`)

Spawns all grass for the board as a **single** `MultiMeshInstance3D` named `"Grass"` under the tiles root.

**Algorithm:**
1. Compute world bounding box of all tile centers, expand by `RADIUS × 1.5`
2. Walk a regular grid at `blade_spacing` intervals across the box
3. For each cell, apply a deterministic hash-jitter (`_hash2`) to the XZ position
4. Convert jittered XZ to axial hex coord (`_world_to_hex`, pointy-top inverse + cube rounding)
5. Accept the blade only if that hex coord is in the `tiles` dictionary
6. Build one `MultiMesh`, set each instance transform with the blade's world position and a random Y-rotation

`blade_spacing = 0.25` ≈ 16 blades per tile. Halving the spacing quadruples blade count.

**Adding coverage to non-grass tile types in future:** `tiles[coord]` currently only stores elevation and ramp_edges. To filter by type (e.g. no grass on stone), add a `"type"` field to the JSON and check it in the acceptance condition.

---

## Adding a New Tile Type

1. Add a `"type"` key to tile entries in the JSON (e.g. `"type": "stone"`)
2. Parse it in `HexBoard3D._load_map_data()` and store in the `tiles` dict
3. Create a new `ShaderMaterial` in `_spawn_board()` that uses a different shader or different color uniforms based on type
4. If the tile should have no grass, check `tile_data["type"] != "grass"` in `GrassSpawner.spawn_for_board()` (pass the type through the dict; it's already available)
5. If the tile should have no outlines, set `ROUGHNESS = 0.0` in its shader

---

## Adding a New Billboard Object (unit, prop, etc.)

1. Use `render_mode unshaded` (or `render_mode depth_prepass_alpha, depth_draw_opaque` for alpha)
2. Override `MODELVIEW_MATRIX` the same way as the grass shader to billboard toward camera
3. Set `ROUGHNESS = 0.0` to **exclude** from edge detection outlines, or `ROUGHNESS = 1.0` to **include**

---

## Known Gotchas

| Problem | Cause | Fix |
|---|---|---|
| Shader compiles but tiles go white | `hint_range` annotation on a `vec3` uniform silently fails to compile | Never add `hint_range` to vec3/vec4 uniforms |
| Edge detection shows nothing | QuadMesh missing `flip_faces = true`, or shader has duplicate `shader_type` declaration | Ensure flip_faces=true; write shader files with Python (heredoc strips tabs) |
| `return` in spatial `fragment()` crashes | Godot 4 does not support early return in spatial fragment | Use `if/else` to branch instead |
| GDScript "Variant inference" error | `roundi()` and `abs()` return Variant — `:=` inference fails | Add explicit type annotation: `var q: int = roundi(...)` |
| Writing .gd files from terminal | Bash heredoc strips tab indentation | Use `python3` with `\t` escapes to write the file |
| Scene baked ShaderMaterial params override shader defaults | Godot serializes `shader_parameter/x` in .tscn; changing shader default has no effect | Edit the `shader_parameter/` values in the .tscn directly |
| Grass not receiving outlines (intentional) | `ROUGHNESS = 0.0` → roughness GBuffer alpha = 0 → mask = 0 | This is correct; see edge detection mask section |

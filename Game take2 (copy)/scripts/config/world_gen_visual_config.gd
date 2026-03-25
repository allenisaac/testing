extends Resource
class_name WorldGenVisualConfig
## Centralised configuration resource for every tunable rendering and
## generation knob in the 3-D terrain pipeline.
##
## Create a .tres from this in the Inspector and assign it to
## Board3DTestController.config.  Every generator and shader push reads
## from this single resource so changes are reflected everywhere.


# ===========================================================================
#  TERRAIN FIELD — Sampling / Bounds
# ===========================================================================
@export_group("Field — Sampling")

@export var board_padding_multiplier: float = 2.0 ## Extra world-space padding around the board before sampling
@export var influence_radius_multiplier: float = 2.0 ## How far a tile's terrain meaning reaches outward
@export var board_membership_radius_multiplier: float = 5.2 ## Max distance from any tile center to count as "inside" the board


# ===========================================================================
#  DEBUG VISUALIZER
# ===========================================================================
@export_group("Debug Visualizer")

@export var debug_marker_size: float = 1.0 ## Size of debug field marker spheres
@export var debug_draw_stride: int = 1 ## Sample skip stride for debug markers (1 = every sample)


# ===========================================================================
#  TERRAIN FIELD — Noise Frequencies
# ===========================================================================
@export_group("Field — Noise")

@export var macro_noise_frequency: float = 0.015 ## Large-scale terrain undulation
@export var micro_noise_frequency: float = 0.06 ## Small-scale surface texture
@export var mud_pocket_noise_frequency: float = 0.45 ## Frequency that drives swampy pocket depressions
@export var mud_crater_noise_frequency: float = 0.1 ## Frequency that drives crater-like mud pits


# ===========================================================================
#  TERRAIN FIELD — Height Strengths
# ===========================================================================
@export_group("Field — Heights")

@export var base_height_strength: float = 0.0 ## Baseline terrain height before noise and shaping
@export var macro_noise_strength: float = 0.30 ## Amplitude of broad terrain shaping
@export var micro_noise_base_strength: float = 0.04 ## Fine-grain surface variation amplitude
@export var micro_noise_mud_bonus_strength: float = 0.10 ## Extra micro-noise in muddy areas
@export var grass_height_strength: float = 0.06 ## Positive lift for grassy areas
@export var clearing_height_strength: float = 0.02 ## Small lift for clearings before flattening


# ===========================================================================
#  TERRAIN FIELD — Terrain-Depth Strengths
# ===========================================================================
@export_group("Field — Depths")

@export var mud_depth_strength: float = 0.75 ## How strongly mud pushes terrain downward
@export var water_depth_strength: float = 1.1 ## How strongly water depresses the terrain (was 4.25, reduced for less exaggeration)


# ===========================================================================
#  TERRAIN FIELD — Mud Pocket & Crater Shaping
# ===========================================================================
@export_group("Field — Mud Shaping")

@export var mud_depth_bias_strength: float = 0.7 ## Multiplier on mud depth bias
@export var mud_pocket_threshold: float = -0.2 ## Noise cutoff for pocket formation
@export var mud_pocket_depth_strength: float = 1.0 ## Depth added by qualifying mud pockets
@export var mud_crater_threshold: float = 0.35 ## Threshold above which craters form
@export var mud_crater_depth_strength: float = 1.35 ## Strength of crater-like pits


# ===========================================================================
#  TERRAIN FIELD — Cliff / Basin Shaping
# ===========================================================================
@export_group("Field — Cliffs")

@export var cliff_start_threshold: float = 0.45 ## Water-weight threshold for sharper dropoff
@export var cliff_depth_strength: float = 0.8 ## Additional basin-edge depth (was 3.4, reduced)
@export var water_depth_power: float = 2.2 ## Exponent for non-linear water basins


# ===========================================================================
#  TERRAIN FIELD — Structure / Clearing Flattening
# ===========================================================================
@export_group("Field — Flattening")

@export var structure_target_height: float = -0.05 ## Height that structures are flattened toward
@export var clearing_target_height: float = 0.02 ## Height that clearings are flattened toward


# ===========================================================================
#  TERRAIN FIELD — Post Smoothing
# ===========================================================================
@export_group("Field — Post Smoothing")

@export var enable_post_smoothing: bool = true ## Run a second-pass height smoother
@export var grass_smoothing_strength: float = 0.45 ## Smoothing for grassy areas
@export var clearing_smoothing_strength: float = 0.75 ## Smoothing for clearings
@export var mud_smoothing_strength: float = 0.00005 ## Smoothing for muddy areas (low to keep pits)
@export var water_smoothing_strength: float = 0.08 ## Smoothing for watery areas


# ===========================================================================
#  TERRAIN MESH
# ===========================================================================
@export_group("Terrain Mesh")

@export var height_visual_scale: float = 0.45 ## Vertical exaggeration on the final mesh (was 1.0, reduced)
@export var terrain_uv_scale: float = 0.05 ## UV tiling scale for terrain
@export var min_inside_corners_to_render: int = 3 ## Board-corner threshold for quad emission
@export var skip_degenerate_triangles: bool = true ## Skip extremely tiny/malformed triangles
@export var degenerate_triangle_epsilon: float = 0.0001 ## Area threshold for degenerate detection


# ===========================================================================
#  WATER MESH — General
# ===========================================================================
@export_group("Water Mesh")

@export var main_water_weight_threshold: float = 0.25 ## Minimum water weight for strong water fill
@export var waterline_height: float = -4.0 ## Base surface height for water
@export var waterline_tolerance: float = 0.6 ## Vertical tolerance above waterline for fill
@export var water_iso_level: float = 0.5 ## Marching-squares iso threshold
@export var water_uv_scale: float = 0.05 ## UV tiling scale for water
@export var require_water_inside_board: bool = true ## Ignore water samples outside playable area


# ===========================================================================
#  WATER MESH — Muddy Pools
# ===========================================================================
@export_group("Water Mesh — Muddy Pools")

@export var mud_pool_weight_threshold: float = 0.15 ## Minimum mud weight for puddles
@export var mud_pool_height_tolerance: float = 1.0 ## Extra vertical allowance for muddy standing water
@export var mud_pool_max_water_weight: float = 0.5 ## Prevents muddy pools from overtaking true water
@export var mud_pool_negative_pocket_threshold: float = -0.08 ## Pocket contribution floor for puddles
@export var mud_pool_bonus_strength: float = 0.35 ## Fill-scalar boost from muddy pools
@export var allow_muddy_pools: bool = true ## Whether muddy depressions may create puddles


# ===========================================================================
#  GRASS SCATTER
# ===========================================================================
@export_group("Grass Scatter")

@export var grass_weight_threshold: float = 0.45 ## Minimum grass weight to place a blade
@export var clearing_weight_max: float = 0.55 ## Maximum clearing weight allowed for grass
@export var water_weight_max: float = 0.35 ## Maximum water weight allowed for grass
@export var mud_weight_max: float = 0.85 ## Maximum mud weight allowed for grass
@export var placement_noise_frequency: float = 0.12 ## Noise frequency for grass placement clumping
@export var placement_noise_threshold: float = -0.05 ## Noise cutoff for grass placement
@export var grass_density_step: int = 2 ## Sample skip stride (1 = every sample, 2 = every other, …)
@export var grass_y_offset: float = 0.02 ## Vertical offset above terrain for grass roots
@export var grass_scale_min: float = 0.75 ## Minimum random blade scale
@export var grass_scale_max: float = 1.35 ## Maximum random blade scale
@export var grass_random_y_rotation: bool = true ## Whether blades are randomly rotated around Y


# ===========================================================================
#  TERRAIN SHADER — Colours
# ===========================================================================
@export_group("Terrain Shader — Colours")

@export var terrain_grass_color_a: Color = Color(0.33, 0.53, 0.22, 1.0) ## Grass colour A (base)
@export var terrain_grass_color_b: Color = Color(0.45, 0.65, 0.30, 1.0) ## Grass colour B (noise mix)
@export var terrain_mud_color_a: Color = Color(0.34, 0.24, 0.14, 1.0) ## Mud colour A
@export var terrain_mud_color_b: Color = Color(0.46, 0.33, 0.20, 1.0) ## Mud colour B
@export var terrain_clearing_color_a: Color = Color(0.52, 0.48, 0.28, 1.0) ## Clearing colour A
@export var terrain_clearing_color_b: Color = Color(0.64, 0.58, 0.34, 1.0) ## Clearing colour B
@export var terrain_wet_tint_color: Color = Color(0.18, 0.28, 0.18, 1.0) ## Water-tint overlay colour
@export var terrain_wet_tint_strength: float = 0.25 ## How strongly water tints the terrain


# ===========================================================================
#  TERRAIN SHADER — Lighting / Cel-shade
# ===========================================================================
@export_group("Terrain Shader — Lighting")

@export var terrain_patch_noise_scale: float = 0.08 ## Colour-patch noise scale
@export var terrain_patch_noise_strength: float = 0.08 ## Colour-patch noise strength
@export var terrain_boundary_softness: float = 0.02 ## Weight-boundary noise softening
@export var terrain_zone_edge_noise_scale: float = 0.11 ## Noise scale for zone-edge wobble in the ground shader
@export var terrain_zone_blend_strength: float = 0.18 ## How strongly zone boundaries blend via noise
@export var terrain_secondary_blend_threshold: float = 0.12 ## Secondary terrain-type blend-in threshold
@export var terrain_light_wrap: float = 0.0 ## Wrapped-lighting factor
@export var terrain_shadow_strength: float = 0.22 ## Shadow darkening intensity
@export var terrain_roughness: float = 0.1 ## Roughness written to the G-buffer
@export var terrain_roughness_value: float = 1.0 ## Roughness value pushed to the ground shader

@export_subgroup("Cel-shade")
@export var terrain_cel_steps: int = 3 ## Number of discrete light bands (0 = smooth, no cel-shade)
@export var terrain_cel_softness: float = 0.01 ## Transition width between cel-shade bands


# ===========================================================================
#  GRASS SHADER
# ===========================================================================
@export_group("Grass Shader")

@export var grass_tint_a: Color = Color(0.32, 0.58, 0.20, 1.0) ## Base grass blade tint A
@export var grass_tint_b: Color = Color(0.52, 0.78, 0.30, 1.0) ## Base grass blade tint B
@export var grass_alpha_cutoff: float = 0.3 ## Alpha-test cutoff
@export var grass_wind_amplitude: float = 0.12 ## Max sway distance
@export var grass_wind_frequency: float = 2.0 ## Sway cycle speed
@export var grass_height_sway_bias: float = 1.5 ## Power curve for top-heavier sway
@export var grass_color_noise_scale: float = 0.25 ## Per-blade colour variation noise scale
@export var grass_color_variation_strength: float = 0.35 ## Per-blade colour variation amount
@export var grass_control_grass_color_a: Color = Color(0.32, 0.58, 0.20, 1.0) ## Grass colour A (ground-map tint)
@export var grass_control_grass_color_b: Color = Color(0.52, 0.78, 0.30, 1.0) ## Grass colour B (ground-map tint)
@export var grass_control_mud_tint: Color = Color(0.45, 0.30, 0.18, 1.0) ## Mud tint on grass blades
@export var grass_control_clearing_tint: Color = Color(0.72, 0.68, 0.40, 1.0) ## Clearing tint on grass blades
@export var grass_roughness: float = 0.85 ## Roughness for grass blades

# ===========================================================================
#  CONTROL MAP
# ===========================================================================

@export var control_map_sharpness: float = 2.75 ## Raises terrain weights before normalization so zones have clearer ownership
@export var control_map_dominant_boost: float = 0.18 ## Slightly boosts the strongest terrain channel so painterly patches read more clearly

# ===========================================================================
#  GRASS SCATTER
# ===========================================================================

@export var grass_clearing_weight_max: float = 0.55 ## Maximum clearing weight allowed for grass placement
@export var grass_water_weight_max: float = 0.35 ## Maximum water weight allowed for grass placement
@export var grass_mud_weight_max: float = 0.85 ## Maximum mud weight allowed for grass placement
@export var grass_placement_noise_frequency: float = 0.12 ## Frequency of scatter acceptance noise for grass placement
@export var grass_placement_noise_threshold: float = -0.05 ## Threshold for noise acceptance when placing grass cards

@export var grass_mud_tint: Color = Color(0.42, 0.30, 0.18, 1.0) ## Mud-influenced tint blended into billboard grass
@export var grass_clearing_tint: Color = Color(0.68, 0.62, 0.36, 1.0) ## Clearing-influenced tint blended into billboard grass


# ===========================================================================
#  LAYERED TERRAIN — Layer Heights
# ===========================================================================
@export_group("Layered Terrain — Heights")

@export var layer_water_floor_y: float = -0.45 ## Y position of the water-floor mesh (lowest layer)
@export var layer_mud_y: float = -0.12 ## Y position of the mud region mesh
@export var layer_grass_y: float = 0.0 ## Y position of the grass region mesh (top solid layer)
@export var layer_water_surface_y: float = -0.18 ## Y position of the transparent water surface plane


# ===========================================================================
#  LAYERED TERRAIN — Region Mask Builder
# ===========================================================================
@export_group("Layered Terrain — Masks")

@export var mask_water_threshold: float = 0.30 ## Water weight above this becomes water region
@export var mask_mud_threshold: float = 0.25 ## Mud weight above this becomes mud region
@export var mask_grass_threshold: float = 0.30 ## Grass weight above this becomes grass region
@export var mask_sharpening_power: float = 3.0 ## Exponent applied to raw mask to sharpen patch edges
@export var mask_binary_cutoff: float = 0.40 ## After sharpening, values above this snap to 1.0
@export var mask_region_noise_frequency: float = 0.035 ## Noise frequency for organic mask edge wobble
@export var mask_region_noise_strength: float = 0.18 ## How much noise shifts the mask threshold
@export var mask_smoothing_passes: int = 2 ## Box-blur passes on the final binary mask for softer contours
@export var mask_precedence_smooth_passes: int = 1 ## Extra smoothing passes after layer precedence subtraction
@export var mask_require_inside_board: bool = true ## Discard mask samples outside the board footprint


# ===========================================================================
#  LAYERED TERRAIN — Contour Extraction
# ===========================================================================
@export_group("Layered Terrain — Contours")

@export var contour_iso_level: float = 0.5 ## Marching-squares iso threshold for region boundary
@export var contour_simplify_tolerance: float = 0.15 ## Douglas-Peucker simplification tolerance (world units)
@export var contour_min_area: float = 0.5 ## Discard tiny contour islands below this area (sq world units)


# ===========================================================================
#  LAYERED TERRAIN — Mesh Generation
# ===========================================================================
@export_group("Layered Terrain — Mesh")

@export var layer_uv_scale: float = 0.05 ## UV tiling for layered region meshes
@export var layer_backface_cull: bool = false ## Whether to cull back faces on region meshes


# ===========================================================================
#  LAYERED TERRAIN — Placeholder Colours
# ===========================================================================
@export_group("Layered Terrain — Colours")

@export var layer_water_floor_color: Color = Color(0.12, 0.18, 0.26, 1.0) ## Water-floor placeholder colour
@export var layer_mud_color: Color = Color(0.38, 0.28, 0.16, 1.0) ## Mud layer placeholder colour
@export var layer_grass_color: Color = Color(0.30, 0.52, 0.22, 1.0) ## Grass layer placeholder colour
@export var layer_water_surface_color: Color = Color(0.18, 0.38, 0.62, 0.65) ## Water surface placeholder colour (semi-transparent)

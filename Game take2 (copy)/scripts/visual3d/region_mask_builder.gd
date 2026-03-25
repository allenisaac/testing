extends RefCounted
class_name RegionMaskBuilder
## Builds scalar region masks from a TerrainFieldBuilder sample field.
##
## Each mask is a flat Array[float] indexed [z * grid_width + x] with values
## in [0.0, 1.0].  The pipeline is:
##   1. Extract the raw weight for the requested terrain type.
##   2. Add organic noise wobble so edges are not tile-aligned.
##   3. Sharpen with a power curve.
##   4. Snap to binary with a hard cutoff.
##   5. Box-blur smooth the result for softer contours.
##
## The builder reads all tunable knobs from a WorldGenVisualConfig resource.


var config: WorldGenVisualConfig

## Noise used to wobble mask edges organically.
var region_noise: FastNoiseLite


func _init(config_resource: WorldGenVisualConfig = null) -> void:
	config = config_resource
	_setup_noise()


func set_config(config_resource: WorldGenVisualConfig) -> void:
	config = config_resource
	_setup_noise()


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## Returns a Dictionary with keys "water", "mud", "grass", plus grid metadata.
## Each value is a flat Array[float] of size grid_width * grid_height.
func build_all_masks(field_data: Dictionary) -> Dictionary:
	var grid_w: int = int(field_data.get("grid_width", 0))
	var grid_h: int = int(field_data.get("grid_height", 0))
	var samples: Array = field_data.get("samples", [])
	var bounds: Dictionary = field_data.get("bounds", {})
	var spacing: float = float(field_data.get("sample_spacing", 1.0))
	var origin_x: float = float(bounds.get("min_x", 0.0))
	var origin_z: float = float(bounds.get("min_z", 0.0))

	## Extract raw weight channels.
	var water_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "water_weight")
	var mud_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "mud_weight")
	var grass_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "grass_weight")

	## Process each mask: threshold + noise wobble -> sharpen -> binary -> smooth.
	var water_mask: Array[float] = _process_mask(water_raw, grid_w, grid_h,
		_cfg("mask_water_threshold", 0.30), origin_x, origin_z, spacing)
	var mud_mask: Array[float] = _process_mask(mud_raw, grid_w, grid_h,
		_cfg("mask_mud_threshold", 0.25), origin_x, origin_z, spacing)
	var grass_mask: Array[float] = _process_mask(grass_raw, grid_w, grid_h,
		_cfg("mask_grass_threshold", 0.30), origin_x, origin_z, spacing)

	## Enforce layer precedence — water > mud > grass.
	_enforce_layer_precedence(water_mask, mud_mask, grass_mask, grid_w, grid_h)

	## Apply board-membership culling if configured.
	if _cfg("mask_require_inside_board", true):
		_apply_board_mask(water_mask, samples, grid_w, grid_h)
		_apply_board_mask(mud_mask, samples, grid_w, grid_h)
		_apply_board_mask(grass_mask, samples, grid_w, grid_h)

	## Log mask statistics.
	print("[masks] water active: ", _count_active(water_mask),
		"  mud active: ", _count_active(mud_mask),
		"  grass active: ", _count_active(grass_mask),
		"  grid: ", grid_w, "x", grid_h, " (", grid_w * grid_h, " total)")

	return {
		"water": water_mask,
		"mud": mud_mask,
		"grass": grass_mask,
		"grid_width": grid_w,
		"grid_height": grid_h,
	}


# ---------------------------------------------------------------------------
#  Internal — noise setup
# ---------------------------------------------------------------------------

func _setup_noise() -> void:
	region_noise = FastNoiseLite.new()
	region_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	region_noise.frequency = _cfg("mask_region_noise_frequency", 0.035)
	## Give a unique seed so the wobble pattern doesn't correlate with the
	## field builder's noises.
	region_noise.seed = 7719


# ---------------------------------------------------------------------------
#  Internal — raw extraction
# ---------------------------------------------------------------------------

## Pull a single weight channel from each sample into a grid-shaped array.
func _extract_raw_mask(samples: Array, grid_w: int, grid_h: int, weight_key: String) -> Array[float]:
	var size: int = grid_w * grid_h
	var mask: Array[float] = []
	mask.resize(size)
	for i in range(size):
		mask[i] = 0.0

	for sample in samples:
		if not (sample is Dictionary):
			continue
		var gx: int = int(sample.get("grid_x", -1))
		var gz: int = int(sample.get("grid_z", -1))
		if gx < 0 or gz < 0 or gx >= grid_w or gz >= grid_h:
			continue

		var weights: Dictionary = sample.get("terrain_weights", {})
		mask[gz * grid_w + gx] = float(weights.get(weight_key, 0.0))

	return mask


# ---------------------------------------------------------------------------
#  Internal — processing pipeline
# ---------------------------------------------------------------------------

func _process_mask(raw: Array[float], grid_w: int, grid_h: int, threshold: float,
		origin_x: float, origin_z: float, spacing: float) -> Array[float]:
	var size: int = grid_w * grid_h
	var noise_strength: float = _cfg("mask_region_noise_strength", 0.18)
	var sharpen_power: float = _cfg("mask_sharpening_power", 3.0)
	var binary_cutoff: float = _cfg("mask_binary_cutoff", 0.40)
	var smooth_passes: int = int(_cfg("mask_smoothing_passes", 2))

	## Step 1 — threshold + noise wobble -> [0, 1]
	var result: Array[float] = []
	result.resize(size)
	for i in range(size):
		result[i] = 0.0

	for idx in range(size):
		var v: float = raw[idx]
		## Noise wobble using world-space positions for spatial consistency.
		var gx: int = idx % grid_w
		var gz: int = idx / grid_w
		var wx: float = origin_x + float(gx) * spacing
		var wz: float = origin_z + float(gz) * spacing
		var noise_val: float = region_noise.get_noise_2d(wx, wz)
		var effective_threshold: float = threshold - noise_val * noise_strength
		var above: float = v - effective_threshold
		if above <= 0.0:
			result[idx] = 0.0
			continue
		## Normalise so that samples well above threshold approach 1.
		var normalised: float = clamp(above / max(0.001, 1.0 - effective_threshold), 0.0, 1.0)
		result[idx] = normalised

	## Step 2 — sharpen with power curve
	for idx in range(size):
		result[idx] = pow(result[idx], sharpen_power)

	## Step 3 — snap to binary
	for idx in range(size):
		result[idx] = 1.0 if result[idx] >= binary_cutoff else 0.0

	## Step 4 — box-blur smooth for softer contour edges
	for _pass in range(smooth_passes):
		result = _box_blur(result, grid_w, grid_h)

	return result


## Simple 3x3 box blur on a flat grid array.
func _box_blur(source: Array[float], grid_w: int, grid_h: int) -> Array[float]:
	var size: int = grid_w * grid_h
	var out: Array[float] = []
	out.resize(size)
	for i in range(size):
		out[i] = 0.0

	for gz in range(grid_h):
		for gx in range(grid_w):
			var total: float = 0.0
			var count: int = 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nx: int = gx + dx
					var nz: int = gz + dz
					if nx < 0 or nx >= grid_w or nz < 0 or nz >= grid_h:
						continue
					total += source[nz * grid_w + nx]
					count += 1
			out[gz * grid_w + gx] = total / float(count)

	return out


## Enforce layer precedence so layers read as nested stacked regions:
## - water is dominant: suppress grass where water is present
## - strong water core suppresses mud (but edges are allowed)
## - strong grass without water suppresses stray mud
func _enforce_layer_precedence(water: Array[float], mud: Array[float],
		grass: Array[float], grid_w: int, grid_h: int) -> void:
	var size: int = grid_w * grid_h

	for i in range(size):
		var w: float = water[i]

		## Water suppresses grass — grass should not visually cover water.
		if w > 0.3:
			grass[i] = max(0.0, grass[i] - w * 1.5)

		## Strong water core suppresses mud (edges still allowed).
		if w > 0.6:
			var suppress: float = (w - 0.6) / 0.4
			mud[i] = max(0.0, mud[i] * (1.0 - suppress * 0.7))

		## Strong grass without water suppresses stray mud patches.
		if grass[i] > 0.5 and w < 0.2:
			mud[i] = max(0.0, mud[i] * 0.4)

	## Post-precedence smooth to heal hard cut edges.
	var precedence_smooth: int = int(_cfg("mask_precedence_smooth_passes", 1))
	for _pass in range(precedence_smooth):
		var smoothed_mud: Array[float] = _box_blur(mud, grid_w, grid_h)
		var smoothed_grass: Array[float] = _box_blur(grass, grid_w, grid_h)
		for i in range(size):
			mud[i] = smoothed_mud[i]
			grass[i] = smoothed_grass[i]


## Zero out mask samples whose field sample is outside the board footprint.
func _apply_board_mask(mask: Array[float], samples: Array, grid_w: int, grid_h: int) -> void:
	for sample in samples:
		if not (sample is Dictionary):
			continue
		if bool(sample.get("is_inside_board", false)):
			continue
		var gx: int = int(sample.get("grid_x", -1))
		var gz: int = int(sample.get("grid_z", -1))
		if gx < 0 or gz < 0 or gx >= grid_w or gz >= grid_h:
			continue
		mask[gz * grid_w + gx] = 0.0


## Count the number of cells above 0.5 in a mask (for logging).
func _count_active(mask: Array[float]) -> int:
	var count: int = 0
	for v in mask:
		if v > 0.5:
			count += 1
	return count


# ---------------------------------------------------------------------------
#  Config helper
# ---------------------------------------------------------------------------

func _cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback

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

## Returns a Dictionary with keys "water", "mud", "grass".
## Each value is a flat Array[float] of size grid_width * grid_height.
func build_all_masks(field_data: Dictionary) -> Dictionary:
	var grid_w: int = int(field_data.get("grid_width", 0))
	var grid_h: int = int(field_data.get("grid_height", 0))
	var samples: Array = field_data.get("samples", [])

	var water_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "water_weight")
	var mud_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "mud_weight")
	var grass_raw: Array[float] = _extract_raw_mask(samples, grid_w, grid_h, "grass_weight")

	var water_mask: Array[float] = _process_mask(water_raw, grid_w, grid_h, _cfg("mask_water_threshold", 0.30))
	var mud_mask: Array[float] = _process_mask(mud_raw, grid_w, grid_h, _cfg("mask_mud_threshold", 0.25))
	var grass_mask: Array[float] = _process_mask(grass_raw, grid_w, grid_h, _cfg("mask_grass_threshold", 0.30))

	## Apply board-membership culling if configured.
	if _cfg("mask_require_inside_board", true):
		_apply_board_mask(water_mask, samples, grid_w, grid_h)
		_apply_board_mask(mud_mask, samples, grid_w, grid_h)
		_apply_board_mask(grass_mask, samples, grid_w, grid_h)

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

func _process_mask(raw: Array[float], grid_w: int, grid_h: int, threshold: float) -> Array[float]:
	var size: int = grid_w * grid_h
	var noise_strength: float = _cfg("mask_region_noise_strength", 0.18)
	var sharpen_power: float = _cfg("mask_sharpening_power", 3.0)
	var binary_cutoff: float = _cfg("mask_binary_cutoff", 0.40)
	var smooth_passes: int = int(_cfg("mask_smoothing_passes", 2))

	## Step 1 — threshold + noise wobble → [0, 1]
	var result: Array[float] = []
	result.resize(size)
	for i in range(size):
		result[i] = 0.0

	for idx in range(size):
		var v: float = raw[idx]
		## Noise wobble shifts the effective threshold per sample.
		var gx: int = idx % grid_w
		var gz: int = idx / grid_w
		var noise_val: float = region_noise.get_noise_2d(float(gx) * 3.7, float(gz) * 3.7)
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


# ---------------------------------------------------------------------------
#  Config helper
# ---------------------------------------------------------------------------

func _cfg(property_name: String, fallback: Variant) -> Variant:
	if config == null:
		return fallback
	var val: Variant = config.get(property_name)
	return val if val != null else fallback

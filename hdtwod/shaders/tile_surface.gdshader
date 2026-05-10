// Tile surface shader — toon shading + HSV noise variation from world XZ position.
// Noise shifts hue, saturation, and brightness relative to color_base, so the same
// shader produces different-looking noise on every terrain color without per-terrain tuning.

shader_type spatial;
//render_mode cull_disabled;


// ---------------------------------------------------------------------------
// Base color (set per terrain type by the terrain handler)
// ---------------------------------------------------------------------------

group_uniforms color;
uniform vec4 albedo1 : source_color = vec4(1.0f);
uniform float threshold_gradient_size = 0.2;


// ---------------------------------------------------------------------------
// Second color (uses albedo2 noise to create a pattern of where this color appears)
// ---------------------------------------------------------------------------

group_uniforms colour.albedo2;
uniform vec3 albedo2_hsl = vec3(0.0, 0.0, 0.0); // ΔHue°, ΔSaturation, ΔLightness relative to albedo1
uniform sampler2D albedo2_noise;
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.2;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.604;

// ---------------------------------------------------------------------------
// Third color (uses albedo3 noise to create a pattern of where this color appears)
// ---------------------------------------------------------------------------

group_uniforms colour.albedo3;
uniform vec3 albedo3_hsl = vec3(0.0, 0.0, 0.0); // ΔHue°, ΔSaturation, ΔLightness relative to albedo1
uniform sampler2D albedo3_noise;
uniform float albedo3_scale : hint_range(0.0, 1.0, 0.001) = 0.1;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.661;


// ---------------------------------------------------------------------------
// Toon lighting (manual — independent of Godot light nodes)
// ---------------------------------------------------------------------------

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0f, 2.0f) = 0.0f;
uniform float steepness : hint_range(1.0f, 8.0f) = 1.0f;
uniform float ambient_min : hint_range(0.0, 1.0) = 0.15;

// ---------------------------------------------------------------------------
// HSL helpers — albedo2/3 are computed from albedo1 + HSL deltas at runtime
// ---------------------------------------------------------------------------

vec3 _rgb_to_hsl(vec3 c) {
	float cmax = max(c.r, max(c.g, c.b));
	float cmin = min(c.r, min(c.g, c.b));
	float d = cmax - cmin;
	float l = (cmax + cmin) * 0.5;
	if (d < 1e-5) return vec3(0.0, 0.0, l);
	float s = d / (1.0 - abs(2.0 * l - 1.0));
	float h;
	if      (c.r >= c.g && c.r >= c.b) h = mod((c.g - c.b) / d, 6.0) / 6.0;
	else if (c.g >= c.b)               h = ((c.b - c.r) / d + 2.0) / 6.0;
	else                               h = ((c.r - c.g) / d + 4.0) / 6.0;
	return vec3(h, s, l);
}
vec3 _hsl_to_rgb(vec3 hsl) {
	float c = (1.0 - abs(2.0 * hsl.z - 1.0)) * hsl.y;
	float h6 = fract(hsl.x) * 6.0;
	float x = c * (1.0 - abs(mod(h6, 2.0) - 1.0));
	float m = hsl.z - c * 0.5;
	vec3 rgb;
	if      (h6 < 1.0) rgb = vec3(c, x, 0.0);
	else if (h6 < 2.0) rgb = vec3(x, c, 0.0);
	else if (h6 < 3.0) rgb = vec3(0.0, c, x);
	else if (h6 < 4.0) rgb = vec3(0.0, x, c);
	else if (h6 < 5.0) rgb = vec3(x, 0.0, c);
	else               rgb = vec3(c, 0.0, x);
	return clamp(rgb + m, 0.0, 1.0);
}
vec3 _linear_to_srgb(vec3 c) {
	vec3 cutoff = step(vec3(0.0031308), c);
	vec3 lower = c * 12.92;
	vec3 higher = 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(lower, higher, cutoff);
}
vec3 _srgb_to_linear(vec3 c) {
	vec3 cutoff = step(vec3(0.04045), c);
	vec3 lower = c / 12.92;
	vec3 higher = pow(max((c + 0.055) / 1.055, vec3(0.0)), vec3(2.4));
	return mix(lower, higher, cutoff);
}
// delta: (ΔHue in degrees, ΔSaturation, ΔLightness)
vec3 hsl_shift(vec3 base_rgb, vec3 delta) {
	vec3 base_srgb = _linear_to_srgb(base_rgb);
	vec3 hsl = _rgb_to_hsl(base_srgb);
	hsl.x = fract(hsl.x + delta.x / 360.0);
	hsl.y = clamp(hsl.y + delta.y, 0.0, 1.0);
	hsl.z = clamp(hsl.z + delta.z, 0.0, 1.0);
	return _srgb_to_linear(_hsl_to_rgb(hsl));
}

// ---------------------------------------------------------------------------
// Varyings
// ---------------------------------------------------------------------------

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// cloud shader? - not yet removed cloud section from light()

// ---------------------------------------------------------------------------
// fragment
// ---------------------------------------------------------------------------


void fragment() {
	// Texture noises for grass patches
	float albedo2_noise_tex = texture(albedo2_noise, vertex_world.xz * (albedo2_scale)).r;
	float albedo3_noise_tex = texture(albedo3_noise, vertex_world.xz * (albedo3_scale)).r;
	// Derive albedo2/3 colors from albedo1 using HSL deltas
	vec3 albedo2_color = hsl_shift(albedo1.rgb, albedo2_hsl);
	vec3 albedo3_color = hsl_shift(albedo1.rgb, albedo3_hsl);
	// Set colours based on noise thresholds
	ALBEDO = albedo1.rgb;
	if (albedo2_noise_tex > albedo2_threshold) {
		ALBEDO = albedo2_color;
	} if (albedo3_noise_tex > albedo3_threshold) {
		ALBEDO = albedo3_color;
	}
}


void light() {
	// Diffuse lighting.
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	// CLOUDS
/* 	if (LIGHT_IS_DIRECTIONAL) {
		vec3 vertex_world_pos = (MODEL_MATRIX * vec4(vertex_pos, 1.0)).xyz;
		float light_value = get_cloud_noise(vertex_world_pos);
		diffuse_amount = min(diffuse_amount, light_value);
	}
 */
	// Toon Shading
	float cuts_inv = 1.0f / float(cuts);
	float cut = cuts_inv; // single cut width
	float original_index = ceil(diffuse_amount * float(cuts));   // ceil(diffuse * cuts)
	float original_stepped = clamp(original_index * cut, 0.0, 1.0);
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv), 0.0f, 1.0f);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;
	vec3 shadow_tint = vec3(0.051, 0.341, 0.439); // darker, slightly green shadow
    float shadow_influence = 1.0 - ATTENUATION; // 1.0 in shadow, 0.0 in light
    diffuse *= mix(vec3(1.0), shadow_tint, shadow_influence * 0.6); // 0.6 controls shadow darkness

	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}


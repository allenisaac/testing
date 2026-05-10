shader_type spatial;

render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color;

uniform vec4 albedo1 : source_color = vec4(1.0);

uniform vec3 albedo2_hsl = vec3(0.0);
uniform sampler2D albedo2_noise : source_color;
uniform float albedo2_scale = 0.1;
uniform float albedo2_threshold = 0.2;

uniform vec3 albedo3_hsl = vec3(0.0);
uniform sampler2D albedo3_noise : source_color;
uniform float albedo3_scale = 0.1;
uniform float albedo3_threshold = 0.5;

uniform int cuts = 5;
uniform float wrap = 0.0;
uniform float steepness = 1.0;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

// ---------------------------------------------------------------------------
// HSL helpers
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
// vertex
// ---------------------------------------------------------------------------


void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
// ---------------------------------------------------------------------------
// fragment
// ---------------------------------------------------------------------------

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	float albedo2_noise_tex = 0.0;
	float albedo3_noise_tex = 0.0;

	albedo2_noise_tex = texture(albedo2_noise, vertex_world.xz * albedo2_scale).r;
	albedo3_noise_tex = texture(albedo3_noise, vertex_world.xz * albedo3_scale).r;


	vec3 albedo2_color = hsl_shift(albedo1.rgb, albedo2_hsl);
	vec3 albedo3_color = hsl_shift(albedo1.rgb, albedo3_hsl);

	vec3 terrain_color = albedo1.rgb;
	if (albedo2_noise_tex > albedo2_threshold) {
		terrain_color = albedo2_color;
	}
	if (albedo3_noise_tex > albedo3_threshold) {
		terrain_color = albedo3_color;
	}

	// White texture should become fully albedo1/albedo2/albedo3 tinted.
	ALBEDO = terrain_color * tex.rgb;

	// Keep it out of your outline logic if that depends on roughness.
	ROUGHNESS = 0.0;
}

// ---------------------------------------------------------------------------
// light
// ---------------------------------------------------------------------------

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	float cuts_inv = 1.0 / float(cuts);
	float diffuse_stepped = clamp(
		diffuse_amount + mod(1.0f - diffuse_amount, cuts_inv),
		0.0f,
		1.0f
	);

	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;

	vec3 shadow_tint = vec3(0.051, 0.341, 0.439);
	float shadow_influence = 1.0 - ATTENUATION;
	diffuse *= mix(vec3(1.0), shadow_tint, shadow_influence * 0.6);

	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
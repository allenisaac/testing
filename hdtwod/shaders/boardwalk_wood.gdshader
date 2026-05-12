// Boardwalk wood shader — simple toon shading.
// Base color: #B48F7F  (sRGB 0.71, 0.62, 0.50)

shader_type spatial;

// ---------------------------------------------------------------------------
// Color
// ---------------------------------------------------------------------------

group_uniforms color;
uniform vec4 albedo : source_color = vec4(0.61, 0.53, 0.42, 1.0);

// ---------------------------------------------------------------------------
// Toon lighting
// ---------------------------------------------------------------------------

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform float ambient_min : hint_range(0.0, 1.0) = 0.15;

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------

void fragment() {
	ALBEDO = albedo.rgb;
}

// ---------------------------------------------------------------------------
// Light — toon diffuse (mirrors tile_surface.gdshader)
// ---------------------------------------------------------------------------

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	float cuts_inv = 1.0 / float(cuts);
	float diffuse_stepped = clamp(
		diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv),
		0.0, 1.0
	);

	vec3 diffuse = albedo.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;

	vec3 shadow_tint = vec3(0.051, 0.341, 0.439);
	float shadow_influence = 1.0 - ATTENUATION;
	diffuse *= mix(vec3(1.0), shadow_tint, shadow_influence * 0.6);

	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, albedo.rgb * ambient_min);
}

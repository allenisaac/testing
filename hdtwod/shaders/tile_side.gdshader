shader_type spatial;

// ---------------------------------------------------------------------------
// Base color
// ---------------------------------------------------------------------------
group_uniforms color;
uniform vec4 albedo1 : source_color = vec4(1.0);
uniform float threshold_gradient_size = 0.2;

// ---------------------------------------------------------------------------
// Second color
// ---------------------------------------------------------------------------
group_uniforms colour.albedo2;
uniform vec3 albedo2_hsl = vec3(0.0, 0.0, 0.0);
uniform sampler2D albedo2_noise;
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.2;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.604;

// ---------------------------------------------------------------------------
// Third color
// ---------------------------------------------------------------------------
group_uniforms colour.albedo3;
uniform vec3 albedo3_hsl = vec3(0.0, 0.0, 0.0);
uniform sampler2D albedo3_noise;
uniform float albedo3_scale : hint_range(0.0, 1.0, 0.001) = 0.1;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.661;

// ---------------------------------------------------------------------------
// Toon lighting
// ---------------------------------------------------------------------------
group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform float ambient_min : hint_range(0.0, 1.0) = 0.15;

group_uniforms side;
uniform sampler2D side_albedo : source_color, hint_default_white;
uniform sampler2D side_normal : hint_normal;
uniform float side_delta_strength : hint_range(0.0, 1.0, 0.01) = 0.6;

#include "res://shaders/includes/hsl_utils.gdshaderinc"
#include "res://shaders/includes/toon_light_utils.gdshaderinc"

varying vec3 vertex_world;

void vertex() {
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float noise2 = texture(albedo2_noise, vertex_world.xz * albedo2_scale).r;
	float noise3 = texture(albedo3_noise, vertex_world.xz * albedo3_scale).r;

	vec3 side_tex = texture(side_albedo, UV).rgb;

	vec3 albedo2_color = mix(side_tex, hsl_shift(side_tex, albedo2_hsl), side_delta_strength);
	vec3 albedo3_color = mix(side_tex, hsl_shift(side_tex, albedo3_hsl), side_delta_strength);

	vec3 base_color = side_tex;

	if (noise2 > albedo2_threshold) {
		base_color = albedo2_color;
	}

	if (noise3 > albedo3_threshold) {
		base_color = albedo3_color;
	}

	ALBEDO = base_color;
	NORMAL_MAP = texture(side_normal, UV).rgb;
}

void light() {
	vec3 diffuse = apply_basic_toon_light(
		ALBEDO.rgb,
		NORMAL,
		LIGHT,
		LIGHT_COLOR,
		ATTENUATION,
		wrap,
		steepness,
		cuts
	);

	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
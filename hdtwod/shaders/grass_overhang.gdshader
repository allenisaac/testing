shader_type spatial;

render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color;

group_uniforms color;
uniform vec4 albedo1 : source_color = vec4(1.0);
uniform float threshold_gradient_size = 0.2;

group_uniforms colour.albedo2;
uniform vec3 albedo2_hsl = vec3(0.0, 0.0, 0.0);
uniform sampler2D albedo2_noise;
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.2;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.604;

group_uniforms colour.albedo3;
uniform vec3 albedo3_hsl = vec3(0.0, 0.0, 0.0);
uniform sampler2D albedo3_noise;
uniform float albedo3_scale : hint_range(0.0, 1.0, 0.001) = 0.1;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.661;

group_uniforms lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform float ambient_min : hint_range(0.0, 1.0) = 0.15;

uniform float alpha_scissor_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;

#include "res://shaders/includes/hsl_utils.gdshaderinc"
#include "res://shaders/includes/terrain_color_utils.gdshaderinc"
#include "res://shaders/includes/toon_light_utils.gdshaderinc"

varying vec3 vertex_pos;
varying vec3 normal;
varying vec3 vertex_world;

void vertex() {
	vertex_pos = VERTEX;
	normal = NORMAL;
	vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}



void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

	vec3 terrain_color = get_world_noise_shifted_albedo(
		vertex_world.xz,
		albedo1.rgb,
		albedo2_hsl,
		albedo2_noise,
		albedo2_scale,
		albedo2_threshold,
		albedo3_hsl,
		albedo3_noise,
		albedo3_scale,
		albedo3_threshold
	);

	ALBEDO = terrain_color * tex.rgb;
	ROUGHNESS = 0.0;
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
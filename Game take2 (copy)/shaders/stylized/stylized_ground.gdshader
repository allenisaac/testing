shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D control_map;

uniform vec2 field_min_xz = vec2(-100.0, -100.0);
uniform vec2 field_max_xz = vec2(100.0, 100.0);

uniform vec4 grass_color_a : source_color = vec4(0.36, 0.55, 0.24, 1.0);
uniform vec4 grass_color_b : source_color = vec4(0.48, 0.67, 0.31, 1.0);

uniform vec4 mud_color_a : source_color = vec4(0.39, 0.28, 0.17, 1.0);
uniform vec4 mud_color_b : source_color = vec4(0.52, 0.37, 0.22, 1.0);

uniform vec4 clearing_color_a : source_color = vec4(0.58, 0.52, 0.31, 1.0);
uniform vec4 clearing_color_b : source_color = vec4(0.70, 0.63, 0.38, 1.0);

uniform vec4 wet_tint_color : source_color = vec4(0.16, 0.24, 0.18, 1.0);
uniform float wet_tint_strength : hint_range(0.0, 1.0) = 0.12;

uniform float patch_noise_scale = 0.07;
uniform float patch_noise_strength : hint_range(0.0, 1.0) = 0.08;
uniform float zone_edge_noise_scale = 0.11;
uniform float zone_blend_strength : hint_range(0.0, 1.0) = 0.18;
uniform float secondary_blend_threshold : hint_range(0.0, 1.0) = 0.12;

uniform float light_wrap : hint_range(0.0, 1.0) = 0.0;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.22;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

uniform int cel_steps = 3;
uniform float cel_softness : hint_range(0.0, 0.2) = 0.01;

global uniform vec3 main_light_direction;

varying vec3 world_pos;
varying vec3 world_normal;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(a, b, u.x)
		+ (c - a) * u.y * (1.0 - u.x)
		+ (d - b) * u.x * u.y;
}


vec2 get_control_uv(vec3 wp) {
	vec2 size = field_max_xz - field_min_xz;
	size = max(size, vec2(0.001, 0.001));

	vec2 uv = (wp.xz - field_min_xz) / size;
	return clamp(uv, vec2(0.0), vec2(1.0));
}


vec3 get_zone_color(int zone_index, float patch_mix) {
	if (zone_index == 0) {
		return mix(grass_color_a.rgb, grass_color_b.rgb, patch_mix);
	}
	if (zone_index == 1) {
		return mix(mud_color_a.rgb, mud_color_b.rgb, patch_mix);
	}
	return mix(clearing_color_a.rgb, clearing_color_b.rgb, patch_mix);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec2 control_uv = get_control_uv(world_pos);
	vec4 control = texture(control_map, control_uv);

	float grass_w = control.r;
	float mud_w = control.g;
	float clearing_w = control.b;
	float water_w = control.a;

	float zone_noise = (noise2d(world_pos.xz * zone_edge_noise_scale) - 0.5) * 2.0 * zone_blend_strength;

	float weights[3];
	weights[0] = grass_w + zone_noise * 0.35;
	weights[1] = mud_w - zone_noise * 0.20;
	weights[2] = clearing_w + zone_noise * 0.15;

	int primary_index = 0;
	int secondary_index = 1;

	if (weights[1] > weights[primary_index]) {
		primary_index = 1;
	}
	if (weights[2] > weights[primary_index]) {
		primary_index = 2;
	}

	secondary_index = 0;
	if (secondary_index == primary_index) {
		secondary_index = 1;
	}

	if (weights[1] > weights[secondary_index] && 1 != primary_index) {
		secondary_index = 1;
	}
	if (weights[2] > weights[secondary_index] && 2 != primary_index) {
		secondary_index = 2;
	}

	float patch_noise = noise2d(world_pos.xz * patch_noise_scale);
	float patch_mix = clamp(0.5 + ((patch_noise - 0.5) * 2.0) * patch_noise_strength, 0.0, 1.0);

	vec3 primary_color = get_zone_color(primary_index, patch_mix);
	vec3 secondary_color = get_zone_color(secondary_index, 1.0 - patch_mix);

	float primary_weight = weights[primary_index];
	float secondary_weight = weights[secondary_index];

	float weight_gap = primary_weight - secondary_weight;
	float secondary_blend = 0.0;

	if (weight_gap < secondary_blend_threshold) {
		secondary_blend = 1.0 - clamp(weight_gap / max(secondary_blend_threshold, 0.001), 0.0, 1.0);
	}

	secondary_blend *= 0.35;

	vec3 base_col = mix(primary_color, secondary_color, secondary_blend);
	base_col = mix(base_col, base_col * wet_tint_color.rgb, water_w * wet_tint_strength);

	vec3 n = normalize(world_normal);
	vec3 l = normalize(-main_light_direction);

	float ndotl = dot(n, l);
	float wrapped_light = clamp((ndotl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);

	float steps_f = float(max(cel_steps, 1));
	float banded = floor(wrapped_light * steps_f + 0.5) / steps_f;
	float edge = abs(wrapped_light - banded);
	float soften = smoothstep(0.0, cel_softness, edge);
	wrapped_light = mix(banded, wrapped_light, soften * 0.35);

	float light_term = mix(1.0 - shadow_strength, 1.0, wrapped_light);

	ALBEDO = base_col * light_term;
	ROUGHNESS = roughness_value;
}
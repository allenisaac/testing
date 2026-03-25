shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_disabled;

uniform sampler2D albedo_texture : source_color;
uniform sampler2D control_map;

uniform vec2 field_min_xz = vec2(-100.0, -100.0);
uniform vec2 field_max_xz = vec2(100.0, 100.0);

uniform vec4 grass_tint_a : source_color = vec4(0.36, 0.55, 0.24, 1.0);
uniform vec4 grass_tint_b : source_color = vec4(0.48, 0.67, 0.31, 1.0);
uniform vec4 mud_tint : source_color = vec4(0.42, 0.30, 0.18, 1.0);
uniform vec4 clearing_tint : source_color = vec4(0.68, 0.62, 0.36, 1.0);

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.3;
uniform float wind_amplitude : hint_range(0.0, 2.0) = 0.12;
uniform float wind_frequency : hint_range(0.0, 10.0) = 2.0;
uniform float height_sway_bias : hint_range(0.0, 4.0) = 1.5;

uniform float color_noise_scale = 0.25;
uniform float color_variation_strength : hint_range(0.0, 1.0) = 0.35;

global uniform float wind_time;
global uniform vec2 wind_direction;
global uniform float wind_strength;

varying vec2 uv_interp;
varying vec3 world_pos_interp;


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


void vertex() {
	uv_interp = UV;

	vec3 object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 camera_pos = CAMERA_POSITION_WORLD;

	vec3 to_camera = normalize(camera_pos - object_origin);
	vec3 up = vec3(0.0, 1.0, 0.0);

	vec3 forward = normalize(vec3(to_camera.x, 0.0, to_camera.z));
	vec3 right = normalize(cross(up, forward));

	mat3 billboard_basis = mat3(
		right,
		up,
		forward
	);

	VERTEX = billboard_basis * VERTEX;

	float height_factor = pow(clamp(UV.y, 0.0, 1.0), height_sway_bias);
	float phase = wind_time * wind_frequency + dot(object_origin.xz, wind_direction * 0.15);
	float sway = sin(phase) * wind_amplitude * wind_strength * height_factor;

	VERTEX.x += wind_direction.x * sway;
	VERTEX.z += wind_direction.y * sway;

	world_pos_interp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec4 tex = texture(albedo_texture, uv_interp);

	if (tex.a < alpha_cutoff) {
		discard;
	}

	vec2 control_uv = get_control_uv(world_pos_interp);
	vec4 control = texture(control_map, control_uv);

	float grass_w = control.r;
	float mud_w = control.g;
	float clearing_w = control.b;
	float water_w = control.a;

	float n = noise2d(world_pos_interp.xz * color_noise_scale);
	float patch_mix = clamp(0.5 + ((n - 0.5) * 2.0) * color_variation_strength, 0.0, 1.0);

	vec3 base_grass = mix(grass_tint_a.rgb, grass_tint_b.rgb, patch_mix);

	// Pull tinting from the same terrain-family logic as the ground
	base_grass = mix(base_grass, mud_tint.rgb, mud_w * 0.28);
	base_grass = mix(base_grass, clearing_tint.rgb, clearing_w * 0.18);

	// Slight darkening near wet areas
	base_grass *= mix(1.0, 0.82, water_w * 0.35);

	ALBEDO = tex.rgb * base_grass;
	ALPHA = tex.a;
	ROUGHNESS = 1.0;
}
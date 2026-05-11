vec3 get_world_noise_shifted_albedo(
	vec2 p_world_xz,
	vec3 p_base_color,
	vec3 p_albedo2_hsl,
	sampler2D p_albedo2_noise,
	float p_albedo2_scale,
	float p_albedo2_threshold,
	vec3 p_albedo3_hsl,
	sampler2D p_albedo3_noise,
	float p_albedo3_scale,
	float p_albedo3_threshold
) {
	float albedo2_noise_tex = texture(p_albedo2_noise, p_world_xz * p_albedo2_scale).r;
	float albedo3_noise_tex = texture(p_albedo3_noise, p_world_xz * p_albedo3_scale).r;

	vec3 albedo2_color = hsl_shift(p_base_color, p_albedo2_hsl);
	vec3 albedo3_color = hsl_shift(p_base_color, p_albedo3_hsl);

	vec3 result = p_base_color;

	if (albedo2_noise_tex > p_albedo2_threshold) {
		result = albedo2_color;
	}
	if (albedo3_noise_tex > p_albedo3_threshold) {
		result = albedo3_color;
	}

	return result;
}
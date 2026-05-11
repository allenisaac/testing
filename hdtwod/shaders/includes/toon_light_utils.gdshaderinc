vec3 apply_basic_toon_light(
	vec3 p_albedo_rgb,
	vec3 p_normal,
	vec3 p_light_dir,
	vec3 p_light_color,
	float p_attenuation,
	float p_wrap,
	float p_steepness,
	int p_cuts
) {
	float NdotL = dot(p_normal, p_light_dir);
	float diffuse_amount = NdotL + (p_attenuation - 1.0) + p_wrap;
	diffuse_amount *= p_steepness;

	float cuts_inv = 1.0 / float(p_cuts);
	float diffuse_stepped = clamp(
		diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv),
		0.0,
		1.0
	);

	vec3 diffuse = p_albedo_rgb * p_light_color / PI;
	diffuse *= diffuse_stepped;

	vec3 shadow_tint = vec3(0.051, 0.341, 0.439);
	float shadow_influence = 1.0 - p_attenuation;
	diffuse *= mix(vec3(1.0), shadow_tint, shadow_influence * 0.6);

	return diffuse;
}
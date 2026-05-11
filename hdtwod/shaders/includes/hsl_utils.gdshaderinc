vec3 _rgb_to_hsl(vec3 p_c) {
	float cmax = max(p_c.r, max(p_c.g, p_c.b));
	float cmin = min(p_c.r, min(p_c.g, p_c.b));
	float d = cmax - cmin;
	float l = (cmax + cmin) * 0.5;

	if (d < 1e-5) {
		return vec3(0.0, 0.0, l);
	}

	float s = d / (1.0 - abs(2.0 * l - 1.0));
	float h;

	if (p_c.r >= p_c.g && p_c.r >= p_c.b) {
		h = mod((p_c.g - p_c.b) / d, 6.0) / 6.0;
	} else if (p_c.g >= p_c.b) {
		h = ((p_c.b - p_c.r) / d + 2.0) / 6.0;
	} else {
		h = ((p_c.r - p_c.g) / d + 4.0) / 6.0;
	}

	return vec3(h, s, l);
}

vec3 _hsl_to_rgb(vec3 p_hsl) {
	float c = (1.0 - abs(2.0 * p_hsl.z - 1.0)) * p_hsl.y;
	float h6 = fract(p_hsl.x) * 6.0;
	float x = c * (1.0 - abs(mod(h6, 2.0) - 1.0));
	float m = p_hsl.z - c * 0.5;

	vec3 rgb;
	if (h6 < 1.0) rgb = vec3(c, x, 0.0);
	else if (h6 < 2.0) rgb = vec3(x, c, 0.0);
	else if (h6 < 3.0) rgb = vec3(0.0, c, x);
	else if (h6 < 4.0) rgb = vec3(0.0, x, c);
	else if (h6 < 5.0) rgb = vec3(x, 0.0, c);
	else rgb = vec3(c, 0.0, x);

	return clamp(rgb + m, 0.0, 1.0);
}

vec3 _linear_to_srgb(vec3 p_c) {
	vec3 cutoff = step(vec3(0.0031308), p_c);
	vec3 lower = p_c * 12.92;
	vec3 higher = 1.055 * pow(max(p_c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(lower, higher, cutoff);
}

vec3 _srgb_to_linear(vec3 p_c) {
	vec3 cutoff = step(vec3(0.04045), p_c);
	vec3 lower = p_c / 12.92;
	vec3 higher = pow(max((p_c + 0.055) / 1.055, vec3(0.0)), vec3(2.4));
	return mix(lower, higher, cutoff);
}

vec3 hsl_shift(vec3 p_base_rgb, vec3 p_delta) {
	vec3 base_srgb = _linear_to_srgb(p_base_rgb);
	vec3 hsl = _rgb_to_hsl(base_srgb);
	hsl.x = fract(hsl.x + p_delta.x / 360.0);
	hsl.y = clamp(hsl.y + p_delta.y, 0.0, 1.0);
	hsl.z = clamp(hsl.z + p_delta.z, 0.0, 1.0);
	return _srgb_to_linear(_hsl_to_rgb(hsl));
}
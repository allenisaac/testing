// Water surface shader — transparent toon water with depth-based color,
// animated Perlin wave crests, shoreline foam, and UV distortion.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

group_uniforms depth;
uniform vec4  color_shallow : source_color = vec4(0.22, 0.65, 0.78, 0.6);
uniform vec4  color_deep    : source_color = vec4(0.04, 0.20, 0.42, 0.88);
uniform float depth_max     : hint_range(0.01, 5.0, 0.01) = 1.2;

group_uniforms foam;
uniform vec4  foam_color        : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform vec4  shoreline_foam_color : source_color = vec4(0.95, 0.97, 1.0, 0.6);
uniform float foam_max_distance : hint_range(0.01, 2.0, 0.01) = 0.4;
uniform float foam_min_distance : hint_range(0.0,  1.0, 0.01) = 0.04;
// 0.5 = sqrt, 0.333 = cbrt. Smaller = crisper/narrower band; larger = wider foam for taller objects.
uniform float foam_edge_power   : hint_range(0.1, 3.0, 0.01) = 0.5;

group_uniforms waves;
uniform sampler2D surface_noise    : hint_default_white;
uniform float     noise_scale      : hint_range(0.01, 4.0, 0.01) = 0.4;
uniform float     noise_cutoff     : hint_range(0.0,  1.0, 0.01) = 0.77;
uniform float edge_noise_cutoff_min     : hint_range(0.0,  1.0, 0.01) = 0.77;
uniform float edge_noise_cutoff_max     : hint_range(0.0,  1.0, 0.01) = 0.45;
uniform vec2      noise_scroll                                    = vec2(0.03, 0.03);
uniform vec2      shoreline_noise_scroll                           = vec2(0.03, 0.03);

group_uniforms waves.distortion;
uniform sampler2D noise_distortion     : hint_default_white;
uniform float     noise_distortion_amt : hint_range(0.0, 0.5, 0.005) = 0.12;

group_uniforms lighting;
uniform int   cuts        : hint_range(1, 8)      = 4;
uniform float wrap        : hint_range(-2.0, 2.0) = 0.2;
uniform float steepness   : hint_range(1.0, 8.0)  = 1.0;
uniform float ambient_min : hint_range(0.0, 1.0)  = 0.3;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

varying vec3  vertex_world;
varying float view_depth;

void vertex() {
    vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // FIX: VERTEX in vertex() is LOCAL space. MODELVIEW_MATRIX gives view space.
    // The old "-VERTEX.z" used local Z (hex corner XZ coords) — totally wrong.
    view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

vec4 alpha_blend(vec4 top, vec4 bottom) {
    vec3 col = (top.rgb * top.a) + (bottom.rgb * (1.0 - top.a));
    float a  = top.a + bottom.a * (1.0 - top.a);
    return vec4(col, a);
}

void fragment() {
    // INV_PROJECTION_MATRIX works in fragment() body (not helper functions).
    float raw_depth   = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec4  view_pos    = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
    view_pos.xyz     /= view_pos.w;
    float scene_depth = -view_pos.z;
    float depth_diff  = max(scene_depth - view_depth, 0.0);

    // --- Color gradient ---
    float depth_t    = clamp(depth_diff / depth_max, 0.0, 1.0);
    vec4 water_color = mix(color_shallow, color_deep, depth_t);

    // --- Foam ---
    // Power curve: shapes how noise foam band width relates to depth.
    float foam_depth_scaled    = pow(depth_diff, foam_edge_power);
    float foam_t               = clamp(foam_depth_scaled / foam_max_distance, 0.0, 1.0);
    // Noise-based foam: cutoff rises from 0 at shore to noise_cutoff in open water.
    float surface_noise_cutoff = mix(0.0, noise_cutoff, foam_t);

    // --- UV distortion ---
    vec2  dist_uv    = vertex_world.xz * noise_scale + TIME * noise_scroll * 0.3;
    vec2  dist_raw   = texture(noise_distortion, dist_uv).rg;
    vec2  distortion = (dist_raw * 2.0 - 1.0) * noise_distortion_amt;

    // --- Wave noise ---
    vec2  noise_uv  = vertex_world.xz * noise_scale + TIME * noise_scroll + distortion;
    float noise_val = texture(surface_noise, noise_uv).r;

    const float AA = 0.01;
    float noise_foam = smoothstep(surface_noise_cutoff - AA, surface_noise_cutoff + AA, noise_val);

    // --- Shoreline foam ---
    // shore_t: 0 at the object edge, 1 at the outer limit of the foam band.
    float shore_t      = clamp(depth_diff / foam_min_distance, 0.0, 1.0);
    // Cutoff varies from edge_noise_cutoff_min (at object) to edge_noise_cutoff_max (outer edge).
    float shore_cutoff = mix(edge_noise_cutoff_min, edge_noise_cutoff_max, shore_t);
    // Independent noise sample with its own scroll speed.
    vec2  shore_uv    = vertex_world.xz * noise_scale + TIME * shoreline_noise_scroll;
    float shore_noise = texture(surface_noise, shore_uv).r;
    // Foam where noise exceeds the cutoff; naturally fades to 0 at shore_t=1 if max cutoff is high enough.
    float hard_edge   = smoothstep(shore_cutoff - AA, shore_cutoff + AA, shore_noise) * (1.0 - shore_t);

    float foam_mask   = max(hard_edge, noise_foam);
    // Blend shoreline and noise foam separately before compositing over water.
    // hard_edge drives shoreline_foam_color; noise_foam drives foam_color.
    // Where both overlap, shoreline wins (it's layered on top).
    vec4  noise_foam_layer     = vec4(foam_color.rgb,           foam_color.a * noise_foam);
    vec4  shoreline_foam_layer = vec4(shoreline_foam_color.rgb, shoreline_foam_color.a * hard_edge);
    vec4  combined_foam = alpha_blend(shoreline_foam_layer, noise_foam_layer);
    vec4  final_color = alpha_blend(combined_foam, water_color);

    ALBEDO    = final_color.rgb;
    ALPHA     = final_color.a;
    ROUGHNESS = 0.05;
    SPECULAR  = 0.3;
}

void light() {
    float NdotL          = dot(NORMAL, LIGHT);
    float diffuse_amount = (NdotL + (ATTENUATION - 1.0) + wrap) * steepness;
    float cuts_inv        = 1.0 / float(cuts);
    float diffuse_stepped = clamp(diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv), 0.0, 1.0);
    diffuse_stepped       = max(diffuse_stepped, ambient_min);
    vec3  diffuse          = ALBEDO.rgb * LIGHT_COLOR / PI * diffuse_stepped;
    float shadow_influence = 1.0 - ATTENUATION;
    diffuse               *= mix(vec3(1.0), vec3(0.051, 0.341, 0.439), shadow_influence * 0.6);
    DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
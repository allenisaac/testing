// Water billboard shader — pixel-art decorators for water tiles (reeds, seaweed, etc.)
// Animation: gentle wind-driven sway, top-heavy (bottom is pinned).
// Lighting: toon shading matching tile_surface.gdshader.
shader_type spatial;
render_mode depth_prepass_alpha, depth_draw_opaque;

group_uniforms texture;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4      albedo_tint    : source_color = vec4(1.0);

group_uniforms animation;
uniform sampler2D wind_noise       : hint_default_white;
uniform float     wind_noise_scale : hint_range(0.0, 0.1, 0.001) = 0.05;
uniform float     wind_noise_speed : hint_range(0.0, 0.2, 0.001) = 0.015;
uniform vec2      wind_direction                                  = vec2(0.0, 1.0);
uniform float     sway_angle : hint_range(0.0, 45.0, 0.1)        = 10.0;
uniform float     idle_speed : hint_range(0.0, 5.0, 0.01)        = 0.5;

group_uniforms lighting;
uniform int   cuts        : hint_range(1, 8)      = 3;
uniform float wrap        : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness   : hint_range(1.0, 8.0)  = 1.0;
uniform float ambient_min : hint_range(0.0, 1.0)  = 0.15;

varying vec3 vertex_world;

void vertex() {
    vertex_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // UV.y = 0 at top, 1 at bottom → height_factor = 1 at top, 0 at bottom.
    float height_factor = 1.0 - UV.y;

    vec2  wind_uv  = vertex_world.xz * wind_noise_scale
                   + TIME * wind_noise_speed * normalize(wind_direction);
    float wind_val = texture(wind_noise, wind_uv).r * 2.0 - 1.0;

    // Per-instance idle sway (golden-ratio phase to desync neighbours).
    float idle     = sin(TIME * idle_speed + float(INSTANCE_ID) * 2.39996) * 0.4;
    float combined = (wind_val + idle) * radians(sway_angle) * height_factor;

    VERTEX.x += sin(combined);
}

void fragment() {
    vec4 col = texture(albedo_texture, UV) * albedo_tint;
    ALBEDO = col.rgb;
    ALPHA  = col.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}

void light() {
    float NdotL          = dot(NORMAL, LIGHT);
    float diffuse_amount = (NdotL + (ATTENUATION - 1.0) + wrap) * steepness;
    float cuts_inv       = 1.0 / float(cuts);
    float stepped        = clamp(diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv), 0.0, 1.0);
    stepped = max(stepped, ambient_min);
    DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, ALBEDO * LIGHT_COLOR / PI * stepped);
}
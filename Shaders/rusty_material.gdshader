shader_type canvas_item;

// Base background color — match your terracotta
uniform vec4 base_color : source_color = vec4(0.78, 0.33, 0.24, 1.0);

// Grain intensity — 0.06–0.12 gives that subtle vintage look
uniform float grain_strength : hint_range(0.0, 0.5) = 0.09;

// Pixel size of each grain particle (1.0 = 1px, higher = chunkier)
uniform float grain_scale : hint_range(0.5, 6.0) = 1.2;

// true = animated film grain, false = static baked-in grain
uniform bool animated = false;

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

void fragment() {
    // Use screen pixel coords so grain stays pixel-stable regardless of node size
    vec2 grain_uv = FRAGCOORD.xy / grain_scale;

    // Animate at ~24fps for a film feel, or freeze it for the static look in your image
    float seed = animated ? floor(TIME * 24.0) : 0.0;

    float grain = hash(grain_uv + seed);

    vec3 color = base_color.rgb;
    // Grain shifts color both lighter AND darker, centered around 0
    color += (grain - 0.5) * (grain_strength * 2.0);
    color = clamp(color, 0.0, 1.0);

    COLOR = vec4(color, 1.0);
}
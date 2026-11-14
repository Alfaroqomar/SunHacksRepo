shader_type canvas_item;

// ── Outline ───────────────────────────────────────────────────────────────────
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float width : hint_range(0, 10) = 1.0;
uniform int pattern : hint_range(0, 2) = 0; // 0 = diamond, 1 = circle, 2 = square
uniform bool inside = false;

// ── Grain ─────────────────────────────────────────────────────────────────────
uniform float grain_strength : hint_range(0.0, 0.5) = 0.09;
uniform float grain_scale : hint_range(0.5, 6.0) = 1.2;
uniform bool animated = false;

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

bool hasContraryNeighbour(vec2 uv, vec2 pixel_size, sampler2D tex) {
    for (float i = -ceil(width); i <= ceil(width); i++) {
        float x = abs(i) > width ? width * sign(i) : i;
        float offset;
        if (pattern == 0)       offset = width - abs(x);
        else if (pattern == 1)  offset = floor(sqrt(pow(width + 0.5, 2.0) - x * x));
        else                    offset = width;
        for (float j = -ceil(offset); j <= ceil(offset); j++) {
            float y = abs(j) > offset ? offset * sign(j) : j;
            vec2 xy = uv + pixel_size * vec2(x, y);
            if ((xy != clamp(xy, vec2(0.0), vec2(1.0)) || texture(tex, xy).a == 0.0) == inside) {
                return true;
            }
        }
    }
    return false;
}

void fragment() {
    vec4 base_color = texture(TEXTURE, UV);

    if (base_color.a > 0.001) {
        vec2 grain_uv = UV * (vec2(textureSize(TEXTURE, 0)) / grain_scale);
        float seed = animated ? floor(TIME * 24.0) : 0.0;
        float grain = hash(grain_uv + seed);
        base_color.rgb += (grain - 0.5) * (grain_strength * 2.0);
        base_color.rgb = clamp(base_color.rgb, 0.0, 1.0);
    }

    if ((base_color.a > 0.0) == inside && hasContraryNeighbour(UV, TEXTURE_PIXEL_SIZE, TEXTURE)) {
        base_color.rgb = inside ? mix(base_color.rgb, outline_color.rgb, outline_color.a) : outline_color.rgb;
        base_color.a += (1.0 - base_color.a) * outline_color.a;
    }

    COLOR = base_color;
}
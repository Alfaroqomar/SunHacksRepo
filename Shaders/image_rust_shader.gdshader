shader_type canvas_item;

uniform float grain_strength : hint_range(0.0, 0.5) = 0.09;
uniform float grain_scale : hint_range(0.5, 6.0) = 1.2;
uniform bool animated = false;

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 17.5);
    return fract(p.x * p.y);
}

void fragment() {
    // Sample the TextureRect's own image
    vec4 tex = texture(TEXTURE, UV);

	vec2 grain_uv = UV * (vec2(textureSize(TEXTURE, 0)) / grain_scale);
    float seed = animated ? floor(TIME * 24.0) : 0.0;
    float grain = hash(grain_uv + seed);

    vec3 color = tex.rgb;
    color += (grain - 0.5) * (grain_strength * 2.0);
    color = clamp(color, 0.0, 1.0);

    // Preserve the texture's original alpha
    COLOR = vec4(color, tex.a);
}
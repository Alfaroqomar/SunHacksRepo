shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.5);
uniform float warp_strength : hint_range(-10.0, 10.0) = 2.0;
uniform float radius : hint_range(0.0, 1.0) = 0.4;

void fragment() {
    vec2 uv = UV;
    vec2 delta = uv - center;
    float dist = length(delta);
    
    // Only warp within the specified radius
    if (dist < radius) {
        float percent = (radius - dist) / radius;
        // Apply a smooth bulge/pinch warp formula
        uv += delta * percent * warp_strength;
    }
    
    COLOR = texture(TEXTURE, uv);
}

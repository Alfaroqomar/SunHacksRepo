shader_type spatial;
render_mode unshaded;

uniform vec4 wall_color : source_color = vec4(0.25, 0.65, 1.0, 1.0);

uniform float slice_y : hint_range(-10.0, 20.0) = 1.5;

uniform float slice_half_thickness : hint_range(0.05, 10.0) = 2.0;

varying float world_y;

void vertex() {
    world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
    if (abs(world_y - slice_y) > slice_half_thickness) {
        discard;  // clips floor, ceiling, anything outside the band
    }
    ALBEDO = wall_color.rgb;
    ALPHA  = 1.0;
}
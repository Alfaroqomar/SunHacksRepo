shader_type canvas_item;

uniform vec2 tilt = vec2(0.0, 0.0);   // -1..1 per axis
uniform float max_tilt_deg = 15.0;
uniform vec2 card_size = vec2(200.0, 300.0);

void vertex() {
    vec2 half = card_size * 0.5;
    vec2 c = VERTEX - half; // center around origin

    float ax = radians(tilt.y * max_tilt_deg); // X-axis rotation (top/bottom)
    float ay = radians(tilt.x * max_tilt_deg); // Y-axis rotation (left/right)

    float x = c.x, y = c.y, z = 0.0;

    // Rotate around Y axis
    float nx = x * cos(ay) + z * sin(ay);
    float nz = -x * sin(ay) + z * cos(ay);
    x = nx; z = nz;

    // Rotate around X axis
    float ny = y * cos(ax) - z * sin(ax);
    nz = y * sin(ax) + z * cos(ax);
    y = ny; z = nz;

    // Perspective divide
    float focal = 800.0;
    float w = focal / (focal + z);
    VERTEX = vec2(x, y) * w + half;
}
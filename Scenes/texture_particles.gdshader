shader_type particles;

// ─── Sprite sheet ─────────────────────────────────────────────────────────
uniform int sprite_columns = 4;
uniform int sprite_rows    = 3;
uniform int valid_rows     = 2;

// ─── Emission shape ───────────────────────────────────────────────────────
// 0 = point  |  1 = rectangle  |  2 = disc (filled circle)  |  3 = ring
uniform bool  emission_rect        = false;
uniform bool  emission_disc        = false; // filled circle
uniform bool  emission_ring        = false;
uniform vec2  emission_box_extents = vec2(50.0, 10.0); // half-extents (rect)
uniform float emission_radius      = 50.0;           // radius       (shapes 2 & 3)

// ─── Initial velocity ─────────────────────────────────────────────────────
uniform vec3  initial_direction = vec3(0.0, 1.0, 0.0); // XY used; normalised internally
uniform float spread_degrees    = 30.0;                 // ± half-angle cone
uniform float initial_speed_min = 50.0;
uniform float initial_speed_max = 150.0;

// ─── Physics ──────────────────────────────────────────────────────────────
uniform vec3  gravity = vec3(0.0, -98.0, 0.0);
uniform float damping = 0.0; // velocity drag coefficient per second (0 = none)

// ─── Rotation ─────────────────────────────────────────────────────────────
uniform float initial_angle_min     = 0.0;   // degrees
uniform float initial_angle_max     = 0.0;   // degrees
uniform float angular_velocity_min  = 0.0;   // degrees per second (negative = counter-clockwise)
uniform float angular_velocity_max  = 0.0;   // degrees per second

// ─── Appearance ───────────────────────────────────────────────────────────
uniform float scale_min                 = 1.0;
uniform float scale_max                 = 1.0;
uniform vec4  base_color : source_color = vec4(1.0);
uniform float fade_in_fraction          = 0.1; // fraction of effective lifetime to fade in
uniform float fade_out_fraction         = 0.2; // fraction of effective lifetime to fade out

// ─── Lifetime randomisation ───────────────────────────────────────────────
// 1.0 = every particle lives its full LIFETIME
// 0.5 = particles live somewhere between 50 % and 100 % of LIFETIME
uniform float lifetime_min_fraction = 1.0;

// ─────────────────────────────────────────────────────────────────────────

float rand_from_seed(inout uint seed) {
    int k;
    int s = int(seed);
    if (s == 0) s = 305420679;
    k = s / 127773;
    s = 16807 * (s - k * 127773) - 2836 * k;
    if (s < 0) s += 2147483647;
    seed = uint(s);
    return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
    x = ((x >> uint(16)) ^ x) * uint(73244475);
    x = ((x >> uint(16)) ^ x) * uint(73244475);
    x = (x >> uint(16)) ^ x;
    return x;
}

// Builds the 2D rotation + uniform scale basis
void apply_rot_scale(inout mat4 xform, float angle, float s) {
    float c = cos(angle);
    float n = sin(angle);
    xform[0].xyz = vec3( c * s, -n * s, 0.0);
    xform[1].xyz = vec3( n * s,  c * s, 0.0);
    xform[2].xyz = vec3(0.0, 0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────

void start() {
    uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);

    // ── Scale + rotation ────────────────────────────────────────────────
    // USERDATA1: x = current angle (rad), y = angular velocity (rad/s), z = scale
    if (RESTART_ROT_SCALE) {
        float s     = mix(scale_min, scale_max, rand_from_seed(seed));
        float angle = radians(mix(initial_angle_min, initial_angle_max, rand_from_seed(seed)));
        float spin  = radians(mix(angular_velocity_min, angular_velocity_max, rand_from_seed(seed)));

        USERDATA1.xyz = vec3(angle, spin, s);
        apply_rot_scale(TRANSFORM, angle, s);
    }

    // ── Spawn position ──────────────────────────────────────────────────
    if (RESTART_POSITION) {
        TRANSFORM[3].xyz = EMISSION_TRANSFORM[3].xyz;
        TRANSFORM[3].z   = 0.0;

        if (emission_rect) {
            float ox = (rand_from_seed(seed) * 2.0 - 1.0) * emission_box_extents.x;
            float oy = (rand_from_seed(seed) * 2.0 - 1.0) * emission_box_extents.y;
            TRANSFORM[3].xy += vec2(ox, oy);

        } else if (emission_disc) {
            float angle  = rand_from_seed(seed) * TAU;
            float radius = sqrt(rand_from_seed(seed)) * emission_radius;
            TRANSFORM[3].xy += vec2(cos(angle), sin(angle)) * radius;

        } else if (emission_ring) {
            float angle = rand_from_seed(seed) * TAU;
            TRANSFORM[3].xy += vec2(cos(angle), sin(angle)) * emission_radius;
        }
        // all false → point emission, no offset
    }

    // ── Initial velocity ────────────────────────────────────────────────
    if (RESTART_VELOCITY) {
        vec2 dir2d = initial_direction.xy;
        // Fall back to "up" when the XY component is degenerate
        dir2d = length(dir2d) > 1e-4 ? normalize(dir2d) : vec2(0.0, 1.0);

        float a  = (rand_from_seed(seed) * 2.0 - 1.0) * radians(spread_degrees);
        float ca = cos(a);
        float sa = sin(a);
        vec2 dir = vec2(dir2d.x * ca - dir2d.y * sa,
                        dir2d.x * sa + dir2d.y * ca);

        float speed = mix(initial_speed_min, initial_speed_max, rand_from_seed(seed));
        VELOCITY = vec3(dir * speed, 0.0);
    }

    // ── Custom data ─────────────────────────────────────────────────────
    if (RESTART_CUSTOM) {
        CUSTOM = vec4(0.0);

        // .w = normalised death threshold; < 1.0 shortens effective lifetime
        CUSTOM.w = mix(lifetime_min_fraction, 1.0, rand_from_seed(seed));

        // .x = sprite frame index   .z = atlas UV offset (kept in sync in process)
        int valid_frames = sprite_columns * valid_rows;
        int frame        = int(rand_from_seed(seed) * float(valid_frames));
        CUSTOM.x = float(frame);
        CUSTOM.z = CUSTOM.x / float(sprite_columns * sprite_rows);
    }

    COLOR = base_color;
}
// ─────────────────────────────────────────────────────────────────────────

void process() {
    // ── Lifetime ────────────────────────────────────────────────────────
    CUSTOM.y += DELTA / LIFETIME;
    if (CUSTOM.y >= CUSTOM.w) {
        ACTIVE = false;
    } else {
        // ── Sprite atlas frame ──────────────────────────────────────────
        CUSTOM.z = CUSTOM.x / float(sprite_columns * sprite_rows);

        // ── Rotation ────────────────────────────────────────────────────
        USERDATA1.x += USERDATA1.y * DELTA;
        apply_rot_scale(TRANSFORM, USERDATA1.x, USERDATA1.z);

        // ── Physics ─────────────────────────────────────────────────────
        VELOCITY   += gravity * DELTA;
        VELOCITY   *= max(0.0, 1.0 - damping * DELTA);
        VELOCITY.z  = 0.0;
        TRANSFORM[3].xyz += VELOCITY * DELTA;
        TRANSFORM[3].z    = 0.0;

        // ── Fade in / out ────────────────────────────────────────────────
        float t     = CUSTOM.y / CUSTOM.w;
        float alpha = 1.0;
        if (fade_in_fraction > 0.0 && t < fade_in_fraction) {
            alpha = t / fade_in_fraction;
        } else if (fade_out_fraction > 0.0 && t > 1.0 - fade_out_fraction) {
            alpha = (1.0 - t) / fade_out_fraction;
        }
        COLOR = base_color * vec4(1.0, 1.0, 1.0, alpha);
    }
}
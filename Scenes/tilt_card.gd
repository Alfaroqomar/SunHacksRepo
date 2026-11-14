extends MarginContainer

@export var max_tilt_deg := 15.0
@export var smoothing := 10.0

var _tilt := Vector2.ZERO
var _target_tilt := Vector2.ZERO
var _hovering := false

func _ready() -> void:
    mouse_entered.connect(func(): _hovering = true; set_process(true))
    mouse_exited.connect(func(): _hovering = false; _target_tilt = Vector2.ZERO)
    set_process(false)

func _process(delta: float) -> void:
    if _hovering:
        var mouse := get_local_mouse_position()
        _target_tilt = ((mouse / size) - Vector2(0.5, 0.5)) * 2.0
        _target_tilt = _target_tilt.clamp(Vector2(-1, -1), Vector2(1, 1))

    _tilt = _tilt.lerp(_target_tilt, delta * smoothing)
    _apply_tilt()

    if not _hovering and _tilt.length() < 0.001:
        _tilt = Vector2.ZERO
        _apply_tilt()
        set_process(false)

func _apply_tilt() -> void:
    pivot_offset = size / 2.0
    scale = Vector2(
        cos(deg_to_rad(_tilt.x * max_tilt_deg)),  # left/right tilt compresses X
        cos(deg_to_rad(_tilt.y * max_tilt_deg))   # up/down tilt compresses Y
    )
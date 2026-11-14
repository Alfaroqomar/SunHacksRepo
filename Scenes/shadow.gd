extends MarginContainer  # or CenterContainer

@export var shadow_color := Color(0, 0, 0, 0.45)
@export var shadow_distance := 18.0
@export var shadow_layers := 6
@export var shadow_spread := 10.0

func _process(_delta: float) -> void:
    queue_redraw()  # redraw every frame to track mouse

func _draw() -> void:
    var card_center = size / 2.0
    var mouse = get_local_mouse_position()
    var offset = (card_center - mouse).normalized() * shadow_distance

    for i in range(shadow_layers, 0, -1):
        var t = float(i) / shadow_layers       # 1.0 = tight, 0.0 = outer
        var expand = (1.0 - t) * shadow_spread
        var alpha = shadow_color.a * t / shadow_layers

        draw_rect(
            Rect2(
                offset.x * t - expand,
                offset.y * t - expand,
                size.x + expand * 2.0,
                size.y + expand * 2.0
            ),
            Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha)
        )
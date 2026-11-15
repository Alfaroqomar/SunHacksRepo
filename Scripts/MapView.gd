class_name MapView
extends Control

## Overhead map shown to the MAP_PLAYER only.
## SubViewportContainer renders the maze automatically — no manual bake needed.
##
## ── Expected scene tree ──────────────────────────────────────────────────────
##
##   MapViewNode (Control, full-screen)   ← this script
##   ├── MapArea (Control, left ~65%)
##   │   ├── SubViewportContainer  (anchors_preset=15, fills MapArea)
##   │   │   └── SubViewport  (own_world_3d = OFF)
##   │   │       └── Camera3D  (Orthographic, top-down, cull_mask excludes player)
##   │   ├── PlayerIcon   (Control 32×32, free layout, hidden at start)
##   │   │   └── TextureRect  (anchors_preset=15)
##   │   ├── ExitIcon     (Control 32×32, free layout, hidden at start)
##   │   │   └── TextureRect  (anchors_preset=15)
##   │   └── EnemyIcons   (Control, anchors_preset=15, mouse_filter=IGNORE)
##   └── ChatPanel (Control, right ~35%)
##       ├── ChatScroll  (ScrollContainer, fills top of ChatPanel)
##       │   └── VBoxContainer  (chat lines added here)
##       └── HBoxContainer  (40 px, pinned to bottom)
##           ├── ChatInput  (LineEdit, expand-fill)
##           └── Button "Send"

# ─── Exports ─────────────────────────────────────────────────────────────────

@export var chat_font: FontFile
@export var chat_font_size: int = 16

@export var map_camera: Camera3D
@export var maze_manager: MazeGameManager

## The MapArea Control — provides the pixel size for coordinate conversion.
@export var map_area: Control

## The SubViewport that holds the overhead Camera3D (for future use / size queries).
@export var map_viewport: SubViewport

## 2-D overlay dot that follows the maze runner.  Made visible on first position update.
@export var player_icon: Control

## 2-D overlay dot for the exit.  Positioned automatically from exit_area.global_position.
@export var exit_icon: Control

## Parent Control for dynamically spawned enemy dots.
@export var enemy_icons_container: Control

## Small Control scene for each enemy dot (e.g. a 12×12 red ColorRect).
@export var enemy_icon_scene: PackedScene

@export var chat_container: VBoxContainer
#@export var chat_scroll: ScrollContainer
@export var chat_input: LineEdit
@export var send_button: Button

const MESSAGE_ALPHAS: Array[float] = [0.0, 0.25, 0.65, 1.0]

## World-space XZ extents of your maze floor — must match the overhead camera coverage.
@export var maze_world_min: Vector2 = Vector2(-50.0, -50.0)
@export var maze_world_max: Vector2 = Vector2( 50.0,  50.0)

# ─── Private ─────────────────────────────────────────────────────────────────

var _enemy_icons: Dictionary = {}   # enemy_id: int → Control

# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	if maze_manager == null:
		push_error("MapView: maze_manager not assigned")
		return

	maze_manager.maze_player_moved.connect(_on_maze_player_moved)
	maze_manager.enemy_positions_updated.connect(_on_enemy_positions_updated)
	maze_manager.chat_received.connect(_on_chat_received)
	maze_manager.game_ended.connect(_on_game_ended)

	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if chat_input:
		chat_input.text_submitted.connect(func(_t: String) -> void: _on_send_pressed())

	# Wait one frame so global_position on exit_area is valid.
	await get_tree().process_frame
	_place_exit_icon()
	_start_player_pulse()



func _start_player_pulse() -> void:
	if player_icon == null:
		return
	var tween := create_tween().set_loops()
	tween.tween_property(player_icon, "scale", Vector2(1.4, 1.4), 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(player_icon, "scale", Vector2(1.0, 1.0), 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_interval(2.0)  # pause between pulses
## Places the exit icon using the 3-D world position of exit_area.
## Called once at startup; the exit never moves.


# ─── Coordinate Conversion ───────────────────────────────────────────────────

## Maps a 3-D world position (XZ plane) to a pixel position inside MapArea.
## Y is ignored — the map is a top-down projection of the floor.
func world_to_map_px(world_pos: Vector3) -> Vector2:
	if map_camera == null or map_viewport == null or map_area == null:
		return Vector2.ZERO
	# Let the camera's own projection do the conversion
	var screen_pos := map_camera.unproject_position(world_pos)
	# Normalize to SubViewport size, then scale to MapArea pixel size
	var normalized := screen_pos / Vector2(map_viewport.size)
	return normalized * map_area.size

# ─── Signal Handlers ─────────────────────────────────────────────────────────

func _on_maze_player_moved(world_pos: Vector3, facing_angle: float) -> void:
	if player_icon == null:
		return
	if not player_icon.visible:
		player_icon.visible = true
	player_icon.pivot_offset = Vector2(16, 16)  # rotate around center
	player_icon.position = world_to_map_px(world_pos) - Vector2(16, 16)
	player_icon.rotation = -facing_angle  # negate: 3D Y is CCW, 2D is CW


func _place_exit_icon() -> void:
	if exit_icon == null or maze_manager == null or maze_manager.exit_area == null:
		return
	exit_icon.position = world_to_map_px(maze_manager.exit_area.global_position) - Vector2(16, 16)
	exit_icon.visible = true


func _on_enemy_positions_updated(positions: Dictionary) -> void:
	for id in positions:
		if not _enemy_icons.has(id):
			if enemy_icon_scene == null or enemy_icons_container == null:
				continue
			var icon: Control = enemy_icon_scene.instantiate()
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			enemy_icons_container.add_child(icon)
			_enemy_icons[id] = icon
		var icon: Control = _enemy_icons[id]
		icon.position = world_to_map_px(positions[id]) - icon.size * 0.5


func _on_chat_received(_sender_id: int, username: String, color: Color, message: String) -> void:
	if chat_container == null:
		return
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.modulate.a = 0.0
	label.visible_ratio = 0.0  # start with no characters visible
	if chat_font:
		label.add_theme_font_override("normal_font", chat_font)
		label.add_theme_font_size_override("normal_font_size", chat_font_size)
	var safe_name := username.replace("[", "[lb]")
	label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), safe_name, message]
	chat_container.add_child(label)

	while chat_container.get_child_count() > 4:
		chat_container.get_child(0).free()

	_update_message_fades()

	# Typewriter effect — tune the duration to control typing speed
	var chars := float(label.get_total_character_count())
	var duration := chars * 0.04  # 40ms per character
	var tween := create_tween()
	tween.tween_property(label, "visible_ratio", 1.0, duration)

func _update_message_fades() -> void:
	var children := chat_container.get_children()
	var count := children.size()
	for i in count:
		# Always map so the newest (last) child = alpha 1.0
		var alpha_index := MESSAGE_ALPHAS.size() - count + i
		var target: float = MESSAGE_ALPHAS[alpha_index] if alpha_index >= 0 else 0.0
		var tween := create_tween()
		tween.tween_property(children[i], "modulate:a", target, 0.6)

func setup_for_role(role: MazeGameManager.Role) -> void:
	var is_map_player := (role == MazeGameManager.Role.MAP_PLAYER)
	if map_area:
		map_area.visible = is_map_player
	if chat_input:
		chat_input.visible = is_map_player
	if send_button:
		send_button.visible = is_map_player
	if not is_map_player:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if map_area:
			map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_game_ended(_won: bool) -> void:
	if chat_input:
		chat_input.editable = false
	if send_button:
		send_button.disabled = true


func _on_send_pressed() -> void:
	if maze_manager == null or chat_input == null:
		return
	maze_manager.send_chat(chat_input.text)
	chat_input.clear()
	chat_input.grab_focus()

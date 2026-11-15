class_name MapView
extends Control

## Overhead map shown to the MAP_PLAYER only.
## This node has no network code — it only listens to MazeGameManager's signals.
##
## Scene setup (all assigned in the Inspector):
##   maze_manager      → your MazeGameManager node
##   map_bg            → TextureRect with an overhead image/render of the maze
##   player_icon       → small Control (dot/arrow) that follows the maze runner
##   exit_icon         → static Control; position it over the exit in-editor
##   enemy_icon_scene  → PackedScene for a small enemy dot (spawned per enemy)
##   chat_container    → VBoxContainer where message lines are added
##   chat_scroll       → ScrollContainer wrapping chat_container
##   chat_input        → LineEdit for typing messages
##   send_button       → Button that calls send_chat
##
## Coordinate mapping:
##   Set maze_world_min / maze_world_max to the XZ extents of your 3-D maze floor.
##   world_to_map_px() converts a Vector3 world position to pixels on map_bg.

# ─── Exports ─────────────────────────────────────────────────────────────────

@export var maze_manager: MazeGameManager

@export var map_bg: TextureRect
@export var player_icon: Control
@export var exit_icon: Control          ## Place this over the exit in-editor; it won't move.

@export var chat_container: VBoxContainer
@export var chat_scroll: ScrollContainer
@export var chat_input: LineEdit
@export var send_button: Button

## Spawned dynamically for each enemy; use a small red dot Control scene.
@export var enemy_icon_scene: PackedScene

## World-space XZ extents of the maze floor.  Must match your 3-D maze bounds.
@export var maze_world_min: Vector2 = Vector2(-50.0, -50.0)
@export var maze_world_max: Vector2 = Vector2( 50.0,  50.0)

# ─── Private ─────────────────────────────────────────────────────────────────

## enemy_id (int) → Control node on the map
var _enemy_icons: Dictionary = {}

# ─── Ready ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	if maze_manager == null:
		push_error("MapView: maze_manager not assigned in the Inspector")
		return

	maze_manager.maze_player_moved.connect(_on_maze_player_moved)
	maze_manager.enemy_positions_updated.connect(_on_enemy_positions_updated)
	maze_manager.chat_received.connect(_on_chat_received)
	maze_manager.game_ended.connect(_on_game_ended)

	if send_button:
		send_button.pressed.connect(_on_send_pressed)
	if chat_input:
		chat_input.text_submitted.connect(func(_t: String) -> void: _on_send_pressed())

# ─── Coordinate Conversion ───────────────────────────────────────────────────

## Maps a 3-D world position (XZ plane) to a pixel position on map_bg.
## Y is ignored — the map is a top-down projection of the floor.
func world_to_map_px(world_pos: Vector3) -> Vector2:
	if map_bg == null:
		return Vector2.ZERO
	var t := Vector2(
		inverse_lerp(maze_world_min.x, maze_world_max.x, world_pos.x),
		inverse_lerp(maze_world_min.y, maze_world_max.y, world_pos.z)
	)
	return t * map_bg.size

# ─── Signal Handlers ─────────────────────────────────────────────────────────

func _on_maze_player_moved(world_pos: Vector3) -> void:
	if player_icon == null:
		return
	# Centre the icon on the converted position.
	player_icon.position = world_to_map_px(world_pos) - player_icon.size * 0.5


func _on_enemy_positions_updated(positions: Dictionary) -> void:
	for id in positions:
		# Spawn an icon the first time we see this enemy.
		if not _enemy_icons.has(id):
			if enemy_icon_scene == null:
				continue
			var icon: Control = enemy_icon_scene.instantiate()
			map_bg.add_child(icon)
			_enemy_icons[id] = icon

		var icon: Control = _enemy_icons[id]
		icon.position = world_to_map_px(positions[id]) - icon.size * 0.5


func _on_chat_received(_sender_id: int, username: String, color: Color, message: String) -> void:
	if chat_container == null:
		return

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	var safe_name := username.replace("[", "[lb]")   # prevent BBCode injection
	label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), safe_name, message]
	chat_container.add_child(label)

	# Auto-scroll to the newest message.
	if chat_scroll:
		await get_tree().process_frame
		chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value


func _on_game_ended(won: bool) -> void:
	# Optionally show a "You won!" / "Runner caught!" overlay here.
	if chat_input:
		chat_input.editable = false
	if send_button:
		send_button.disabled = true

# ─── Send ─────────────────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	if maze_manager == null or chat_input == null:
		return
	maze_manager.send_chat(chat_input.text)
	chat_input.clear()
	chat_input.grab_focus()
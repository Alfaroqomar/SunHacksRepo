class_name MapView
extends Control

## Overhead map shown to the MAP_PLAYER only.
## Generates a top-down snapshot of the maze at game start using a SubViewport,
## then overlays 2D icons for the runner, enemies, and exit.
##
## ── Scene tree expected ──────────────────────────────────────────────────────
##
##   MapView (Control)  ← this script
##   ├── MapArea (Control)
##   │   ├── SubViewportContainer          ← resizes the viewport to fit
##   │   │   └── SubViewport               ← own_world_3d = OFF
##   │   │       └── Camera3D              ← Orthographic, pointing straight down
##   │   │                                    cull_mask: exclude player layer
##   │   ├── player_icon  (ColorRect / TextureRect dot)
##   │   ├── exit_icon    (ColorRect / TextureRect dot, positioned in-editor)
##   │   └── EnemyIcons   (Control, parent for spawned dots)
##   └── ChatPanel (Control)
##       ├── ChatScroll → ChatContainer (VBoxContainer)
##       └── HBox → ChatInput + SendButton
##
## ── Render-layer setup (do this in the Inspector) ────────────────────────────
##   • All maze MeshInstance3D nodes → VisualInstance3D → Layers: layer 1 ON
##   • Player MeshInstance3D         → VisualInstance3D → Layers: layer 1 OFF, layer 2 ON
##   • Overhead Camera3D Cull Mask   → layer 1 ON, layer 2 OFF
##   This way the overview camera never sees the player; the 2D dot handles that.

# ─── Exports ─────────────────────────────────────────────────────────────────

@export var maze_manager: MazeGameManager

## The SubViewport that holds the overhead Camera3D.
## Set own_world_3d = OFF so it shares your main 3-D scene.
## Set update_mode = UPDATE_ONCE; we trigger the snapshot manually in _ready().
@export var map_viewport: SubViewport

## TextureRect that displays the SubViewport's render.
## Assign this to a TextureRect whose parent is MapArea.
@export var map_bg: TextureRect

## 2-D overlay dot that follows the maze runner.
@export var player_icon: Control

## 2-D overlay dot for the exit — position it over the exit in the editor;
## it never moves at runtime.
@export var exit_icon: Control

## Parent Control for dynamically spawned enemy dots.
@export var enemy_icons_container: Control

## Small Control scene used for each enemy dot (e.g. a red ColorRect, 8×8 px).
@export var enemy_icon_scene: PackedScene

@export var chat_container: VBoxContainer
@export var chat_scroll: ScrollContainer
@export var chat_input: LineEdit
@export var send_button: Button

## World-space XZ extents of your maze floor.
## Must match the orthographic camera's coverage so dots land correctly.
@export var maze_world_min: Vector2 = Vector2(-50.0, -50.0)
@export var maze_world_max: Vector2 = Vector2( 50.0,  50.0)

# ─── Private ─────────────────────────────────────────────────────────────────

## enemy_id (int) → Control node
var _enemy_icons: Dictionary = {}

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

	# Wait one frame so the 3-D scene is fully loaded before we snapshot it.
	await get_tree().process_frame
	_bake_map_render()


## Takes a one-shot render of the maze from the overhead camera and
## assigns it to map_bg.  Called once at game start.
func _bake_map_render() -> void:
	if map_viewport == null or map_bg == null:
		push_warning("MapView: map_viewport or map_bg not assigned — no render generated")
		return

	# Trigger exactly one render frame, then stop.
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Wait for that frame to actually render before reading the texture.
	await RenderingServer.frame_post_draw

	map_bg.texture = map_viewport.get_texture()

# ─── Coordinate Conversion ───────────────────────────────────────────────────

## Converts a 3-D world position (XZ plane) to a 2-D pixel position on map_bg.
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
	player_icon.position = world_to_map_px(world_pos) - player_icon.size * 0.5


func _on_enemy_positions_updated(positions: Dictionary) -> void:
	for id in positions:
		if not _enemy_icons.has(id):
			if enemy_icon_scene == null or enemy_icons_container == null:
				continue
			var icon: Control = enemy_icon_scene.instantiate()
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
	var safe_name := username.replace("[", "[lb]")
	label.text = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), safe_name, message]
	chat_container.add_child(label)
	if chat_scroll:
		await get_tree().process_frame
		chat_scroll.scroll_vertical = chat_scroll.get_v_scroll_bar().max_value


func _on_game_ended(_won: bool) -> void:
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

class_name MazeGameManager
extends Node

## Manages a 2-player asymmetric maze game over GDSync.
##
## Role MAP_PLAYER  → sees an overhead map, chats hints to the runner.
## Role MAZE_PLAYER → navigates the 3-D maze, relies on the map player.
##
## Position sync : maze player broadcasts every `position_sync_interval` seconds.
## Enemy sync    : host broadcasts all enemy positions on its own timer.
## Chat          : either player can send a message; both see every message.

# ─── Enums ───────────────────────────────────────────────────────────────────

enum Role { UNASSIGNED, MAP_PLAYER, MAZE_PLAYER }
enum GameState { LOBBY, PLAYING, WON, LOST }

# ─── Exports ─────────────────────────────────────────────────────────────────



const GEMINI_PROMPTS: Array[String] = [
	"You are to rephrase the text in an slightly impractical way, keeping the same meaning original meaning but being slightly harder to understand. Be concise.",
	"You are to rephrase the text in an slightly impractical way alongside reformatting in shakespearian style, keeping the same meaning original meaning but being slightly harder to understand. Be concise.",
	"You are to rephrase the text in an slightly impractical way by reformatting the message into emojis, keeping the same meaning original meaning but being slightly harder to understand. Be concise.",
	"You are to rephrase the text in a slightly impractical way by reformatting the message into a poem, keeping the same meaning original meaning but being slightly harder to understand. Be concise.",
	"You are to rephrase the text in a slightly impractical way by reformatting the message into a haiku, keeping the same meaning original meaning but being slightly harder to understand. Be concise.",
]

## Seconds between maze-player position broadcasts.  Drop to ~0.5 for a
## smoother dot on the map; raise to 3–4 for more tension.
@export var position_sync_interval: float = 1.0
@export var exit_trigger_distance: float = 4.0

## The 3-D character scene.  Instantiated only on the MAZE_PLAYER's machine.
@export var maze_player_scene: PackedScene

## Your MapView node (MapView.gd).  Shown for MAP_PLAYER, hidden for MAZE_PLAYER.
@export var map_view_node: Node

## Area3D at the maze exit.  Its body_entered is wired up in _ready().
@export var exit_area: Area3D

# ─── Runtime state ───────────────────────────────────────────────────────────

var my_role: Role = Role.UNASSIGNED
var game_state: GameState = GameState.LOBBY

@export var gemini_api_key: String = ""
@export var gemini_model: String = "gemini-2.0-flash"

## player_id (int) → Role
var role_map: Dictionary = {}

var _http: HTTPRequest = null
var _pending_message: String = ""

## Instantiated only on the MAZE_PLAYER's client.
var maze_player_node: CharacterBody3D = null

var _sync_timer: float = 0.0

# ─── Signals (MapView and UI connect to these) ────────────────────────────────

signal maze_player_moved(world_pos: Vector3)
## { enemy_id: int → world_pos: Vector3 }
signal enemy_positions_updated(positions: Dictionary)
signal chat_received(sender_id: int, username: String, color: Color, message: String)
signal game_ended(won: bool)

# ═══════════════════════════════════════════════════════════════════════════════
# Ready
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_gemini_response)
	# Expose all RPCs before any packet can arrive.
	GDSync.expose_func(_rpc_assign_roles)
	GDSync.expose_func(_rpc_begin_game)
	GDSync.expose_func(_rpc_maze_player_position)
	GDSync.expose_func(_rpc_enemy_positions)
	GDSync.expose_func(_rpc_chat)
	GDSync.expose_func(_rpc_end_game)

	if exit_area:
		exit_area.body_entered.connect(_on_exit_body_entered)

	await get_tree().process_frame

	if MinigameManager.is_host:
		await get_tree().create_timer(0.5).timeout
		_host_assign_roles()

# ═══════════════════════════════════════════════════════════════════════════════
# Role Assignment
# ═══════════════════════════════════════════════════════════════════════════════

func _host_assign_roles() -> void:
	var players: Array = MinigameManager.player_list.duplicate()
	if players.size() < 2:
		push_error("MazeGameManager: need at least 2 players")
		return

	players.shuffle()
	# Extend here if you want 3+ players (spectators, second maze runner, etc.)
	var assignments := {
		players[0].player_id: Role.MAP_PLAYER,
		players[1].player_id: Role.MAZE_PLAYER,
	}
	GDSync.call_func_all(_rpc_assign_roles, assignments)


func _rpc_assign_roles(assignments: Dictionary) -> void:
	role_map = assignments
	my_role = assignments.get(GDSync.get_client_id(), Role.UNASSIGNED)
	_setup_local_view()

	if MinigameManager.is_host:
		await get_tree().create_timer(0.3).timeout
		GDSync.call_func_all(_rpc_begin_game)


func _rpc_begin_game() -> void:
	game_state = GameState.PLAYING


## Show the right view and optionally spawn the 3-D character.
func _setup_local_view() -> void:
	if map_view_node:
		map_view_node.visible = true  # both roles need to see the chat
		if map_view_node.has_method("setup_for_role"):
			map_view_node.setup_for_role(my_role)

	if my_role == Role.MAZE_PLAYER:
		_spawn_maze_player()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _spawn_maze_player() -> void:
	if maze_player_scene == null:
		push_error("MazeGameManager: maze_player_scene is not set")
		return
	maze_player_node = maze_player_scene.instantiate() as CharacterBody3D
	add_child(maze_player_node)              # ← _ready() fires here, disabling processing
	maze_player_node.global_position = Vector3(-2, .5, 2) # ← adjust to your maze's spawn point
	if maze_player_node.has_method("enable_local_input"):
		maze_player_node.enable_local_input() # ← now runs AFTER _ready(), so it sticks

# ═══════════════════════════════════════════════════════════════════════════════
# Position Sync  (maze player → everyone, via RPC)
# ═══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if my_role != Role.MAZE_PLAYER or game_state != GameState.PLAYING:
		return
	if maze_player_node == null:
		return

	# Position sync
	_sync_timer += delta
	if _sync_timer >= position_sync_interval:
		_sync_timer = 0.0
		GDSync.call_func_all(_rpc_maze_player_position, maze_player_node.global_position)

	# Exit proximity check
	if exit_area == null:
		return
	var dist := maze_player_node.global_position.distance_to(exit_area.global_position)
	if dist <= exit_trigger_distance:
		GDSync.call_func_all(_rpc_end_game, true)

## Received by every client.  MapView connects to maze_player_moved to update the dot.
func _rpc_maze_player_position(world_pos: Vector3) -> void:
	maze_player_moved.emit(world_pos)

# ═══════════════════════════════════════════════════════════════════════════════
# Enemy Sync  (host → everyone)
# ═══════════════════════════════════════════════════════════════════════════════

## Call this from your EnemyManager on the host (e.g. on a 0.5-s Timer).
## `positions` → { enemy_id: int : world_pos: Vector3 }
func broadcast_enemy_positions(positions: Dictionary) -> void:
	if not MinigameManager.is_host:
		return
	GDSync.call_func_all(_rpc_enemy_positions, positions)


func _rpc_enemy_positions(positions: Dictionary) -> void:
	enemy_positions_updated.emit(positions)

# ═══════════════════════════════════════════════════════════════════════════════
# Chat
# ═══════════════════════════════════════════════════════════════════════════════

## Call from MapView (or a maze-player HUD if you add one) on text_submitted / Send.
func send_chat(message: String) -> void:
	var trimmed := message.strip_edges()
	if trimmed.is_empty():
		return

	if gemini_api_key.is_empty():
		# No API key — send as-is
		GDSync.call_func_all(_rpc_chat, GDSync.get_client_id(), trimmed)
		return

	_pending_message = trimmed
	_call_gemini(trimmed)

func _call_gemini(message: String) -> void:
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" \
		% [gemini_model, gemini_api_key]

	var body := JSON.stringify({
		"system_instruction": {
			"parts": [{ "text": GEMINI_PROMPTS.pick_random() }]
		},
		"contents": [{
			"parts": [{ "text": message }]
		}]
	})

	_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _on_gemini_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Gemini request failed: result=%d code=%d" % [result, code])
		# Fall back to the original message
		GDSync.call_func_all(_rpc_chat, GDSync.get_client_id(), _pending_message)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		GDSync.call_func_all(_rpc_chat, GDSync.get_client_id(), _pending_message)
		return

	var data: Variant = json.get_data()
	var out: String = _pending_message  # fallback if parsing fails

	if data is Dictionary and data.has("candidates"):
		var candidates: Array = data["candidates"]
		if candidates.size() > 0:
			var parts = candidates[0].get("content", {}).get("parts", [])
			if parts.size() > 0:
				out = parts[0].get("text", _pending_message).strip_edges()

	GDSync.call_func_all(_rpc_chat, GDSync.get_client_id(), out)

func _rpc_chat(sender_id: int, message: String) -> void:
	var data = MinigameManager.get_player_data_by_id(sender_id)
	var username: String = data.username if data else "Player %d" % sender_id
	var color: Color = data.color if data else Color.WHITE
	chat_received.emit(sender_id, username, color, message)

# ═══════════════════════════════════════════════════════════════════════════════
# Win / Lose
# ═══════════════════════════════════════════════════════════════════════════════

## Connected to exit_area.body_entered in _ready().
## maze_player_node is null on the MAP_PLAYER's machine, so the guard handles it.
func _on_exit_body_entered(body: Node3D) -> void:
	if body != maze_player_node:
		return
	GDSync.call_func_all(_rpc_end_game, true)


## Call from EnemyAI when it overlaps the maze player.
## Host-only to prevent duplicate end-game RPCs from several enemies at once.
func notify_player_caught() -> void:
	if not MinigameManager.is_host:
		return
	GDSync.call_func_all(_rpc_end_game, false)


func _rpc_end_game(won: bool) -> void:
	if game_state != GameState.PLAYING:
		return   # already ended; drop the duplicate
	game_state = GameState.WON if won else GameState.LOST
	game_ended.emit(won)
	# Release the cursor for everyone so the end screen is usable.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if MinigameManager.is_host:
		await get_tree().create_timer(3.0).timeout
		GDSync.change_scene("res://Scenes/MainMenu.tscn") # ← adjust to your lobby path

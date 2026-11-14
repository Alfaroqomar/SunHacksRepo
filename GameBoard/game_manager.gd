class_name BoardManger
extends Node

const PATH_ARROW = preload("uid://ynyeb8uqxkmv")

@export var StartPathNode: PathNode
@export var default_player: BoradPlayer     # template node, duplicated once per player
@export var current_player_label: RichTextLabel
@export var reaper_chud: TextureRect
@export var MaxTurns: int = 20
@export var coins_and_shards_label: RichTextLabel

@onready var turn_counter: Label = $"../UI/Turn counter/Label"
@onready var roll_label: Label = $"../UI/Control/Label"
@onready var phantom_camera_2d: PhantomCamera2D = $"../PhantomCamera2D"
@onready var player_buttons: Panel = $"../UI/Player buttons"

var reaper_spritesheet: Texture2D = preload("res://Sprites/MinigameSprites/CardMinigame/Reaper.png")

@export var minigame_pool: Array[PackedScene] = []   # drag minigame scenes in here
var _pending_minigame: String = ""

var CurrentPlayer: BoradPlayer              # token whose turn it is
var TurnsCount: int = 0                     # resets when the scene reloads

var tokens: Dictionary[int, BoradPlayer] = {}   # player_id -> token
var tiles: Array[PathNode] = []                 # index = value saved in player_data.board_position

var _moving: bool = false
var _turn_started: bool = false
var _chosen_path: Dictionary[int, int] = {}     # player_id -> index into PathsAhead
signal _path_chosen


func _ready() -> void:
	if StartPathNode == null:
		push_error("BoardManager: StartPathNode is not set")
		return

	# Exposed immediately so an RPC can never arrive before it's registered.
	GDSync.expose_func(_rpc_start_move)
	GDSync.expose_func(_rpc_choose_path)
	GDSync.expose_func(_rpc_turn_finished)
	GDSync.expose_func(_rpc_move_back)
	GDSync.expose_func(_rpc_start_minigame)
	#GDSync.expose_func(set_sprite_frame)

	set_sprite_frame(1, 3) # 0 is happy, 1 is normal, 2 is good

	# The parent is still running its own _ready pass, so add_child() on it fails right now.
	await get_tree().process_frame

	default_player.hide()   # template only; the copies are what you see
	_build_tile_list()
	_sync_tokens()
	MinigameManager.board_turn_changed.connect(_on_board_turn_changed)
	MinigameManager.stats_changed.connect(_update_stats_label)
	_update_stats_label()
	print("[Board %d] host=%s players=%s" % [GDSync.get_client_id(), MinigameManager.is_host,
			MinigameManager.player_list.map(func(p): return p.player_id)])   # debug, delete later

	if MinigameManager.current_board_player_id != -1:
		# Returning from a minigame, or the order arrived while we were loading.
		_on_board_turn_changed(MinigameManager.current_board_player_id)
	elif MinigameManager.is_host:
		await get_tree().create_timer(0.5).timeout
		MinigameManager.randomize_board_order()


# Creates a token for every player that doesn't have one yet. Safe to call repeatedly,
# which matters on non-host clients whose player list can still be filling in at load.
func _sync_tokens() -> void:
	for data in MinigameManager.player_list:
		if not tokens.has(data.player_id):
			_spawn_token(data)


func _spawn_token(data) -> void:
	var token: BoradPlayer = default_player.duplicate()
	token.name = "Player_%d" % data.player_id
	token.PlayerId = data.player_id
	token.modulate = data.color
	default_player.get_parent().add_child(token)    # into the tree first, then position it

	var idx: int = data.board_position
	var node: PathNode = tiles[idx] if idx >= 0 and idx < tiles.size() else StartPathNode
	token.CurrnetNodeOn = node
	token.global_position = node.global_position
	token.show()
	tokens[data.player_id] = token

# ─── Setup ───────────────────────────────────────────────────────────────────

# Walks the board from the start so every client gets the same tile order.
func _build_tile_list() -> void:
	var queue: Array[PathNode] = [StartPathNode]
	while not queue.is_empty():
		var node: PathNode = queue.pop_front()
		if node in tiles:
			continue
		tiles.append(node)
		for ahead in node.PathsAhead:
			queue.append(ahead)


# ─── Turns ───────────────────────────────────────────────────────────────────

func _on_board_turn_changed(player_id: int) -> void:
	_sync_tokens()   # <- add
	_update_stats_label()
	print("[Board %d] turn -> %d" % [GDSync.get_client_id(), player_id])
	var token: BoradPlayer = tokens.get(player_id)
	if token == null:
		return
	var data = MinigameManager.get_player_data_by_id(player_id)
	var mine: bool = player_id == GDSync.get_client_id()

	# Count a round each time the first player in the order is up again.
	var order = MinigameManager.player_board_order
	if _turn_started and not order.is_empty() and order[0].player_id == player_id:
		TurnsCount += 1
	_turn_started = true
	turn_counter.text = "TURNS\n%d/%d" % [TurnsCount, MaxTurns]

	CurrentPlayer = token
	current_player_label.text = "Your Turn." if mine else "%s's Turn" % data.username
	phantom_camera_2d.follow_target = token
	player_buttons.visible = mine


func roll_button_pressed() -> void:
	if _moving or not MinigameManager.is_my_board_turn():
		return
	player_buttons.hide()
	GDSync.call_func_all(_rpc_start_move, GDSync.get_client_id(), randi_range(1, 6))


# Runs on every client with the same inputs, so every screen shows the same move.
func _rpc_start_move(player_id: int, roll: int) -> void:
	_sync_tokens()
	var token: BoradPlayer = tokens.get(player_id)
	if token == null or _moving:
		return
	_moving = true
	var mine: bool = player_id == GDSync.get_client_id()
	var data = MinigameManager.get_player_data_by_id(player_id)
	current_player_label.text = "You rolled a %d" % roll if mine \
			else "%s rolled a %d" % [data.username, roll]

	for step in range(roll):
		var ahead: Array = token.CurrnetNodeOn.PathsAhead
		if ahead.is_empty():
			break

		if ahead.size() >= 2:
			# Fork: only the mover picks; everyone else waits for the broadcast.
			if mine:
				var picked: int = await _pick_path(token)
				GDSync.call_func_all(_rpc_choose_path, player_id, picked)
			var idx: int = await _wait_for_choice(player_id)
			token.CurrnetNodeOn = ahead[idx]
		else:
			token.CurrnetNodeOn = ahead[0]

		await _move_to_node(token, token.CurrnetNodeOn)
		if mine and step != roll - 1:
			await token.CurrnetNodeOn.touchPath(token)

	if mine:
		var roll_again: bool = await token.CurrnetNodeOn.land_on(token)
		MinigameManager.set_current_board_plr_pos(tiles.find(token.CurrnetNodeOn))
		if roll_again:
			player_buttons.show()
		elif _pending_minigame != "":
			var scene_path := _pending_minigame
			_pending_minigame = ""
			GDSync.call_func_all(_rpc_start_minigame, scene_path)
		else:
			GDSync.call_func_all(_rpc_turn_finished)
	_moving = false


func _rpc_turn_finished() -> void:
	if not MinigameManager.is_host:
		return
	await get_tree().create_timer(1.0).timeout   # pause between turns
	MinigameManager.progress_board_turn()

func _update_stats_label() -> void:
	if coins_and_shards_label == null:
		return
	coins_and_shards_label.bbcode_enabled = true
	var players: Array = MinigameManager.player_board_order
	if players.is_empty():
		players = MinigameManager.player_list   # board order isn't set yet
	var lines: PackedStringArray = []
	for p in players:
		var safe_name: String = p.username.replace("[", "[lb]")   # stops usernames breaking the bbcode
		lines.append("[color=#%s]%s[/color]  Coins: %d  Shards: %d" % [
				p.color.to_html(false), safe_name, p.coins, p.shards])
	coins_and_shards_label.text = "\n".join(lines)

# ─── Movement / path choice ──────────────────────────────────────────────────

func _move_to_node(token: BoradPlayer, node: PathNode) -> void:
	while not token.global_position.is_equal_approx(node.global_position):
		token.global_position = token.global_position.move_toward(
				node.global_position, token.MoveSpeed * get_process_delta_time())
		await get_tree().process_frame

func move_back(token: BoradPlayer, steps: int) -> void:
	var route: Array = []   # tile indices, same on every client
	var node: PathNode = token.CurrnetNodeOn
	for i in steps:
		var prev: PathNode = _node_behind(node)
		if prev == null:
			break
		route.append(tiles.find(prev))
		node = prev
	if route.is_empty():
		return
	GDSync.call_func(_rpc_move_back, token.PlayerId, route)   # skips the caller
	await _walk_route(token, route)


func _rpc_move_back(player_id: int, route: Array) -> void:
	var token: BoradPlayer = tokens.get(player_id)
	if token == null:
		return
	while _moving:   # let this client finish animating the roll first
		await get_tree().process_frame
	await _walk_route(token, route)

func set_sprite_frame(frame_index: int, total_frames: int) -> void:
	var frame_width = reaper_spritesheet.get_width() / total_frames
	var frame_height = reaper_spritesheet.get_height()

	var atlas = AtlasTexture.new()
	atlas.atlas = reaper_spritesheet
	atlas.region = Rect2(frame_index * frame_width, 0, frame_width, frame_height)

	reaper_chud.texture = atlas

func _walk_route(token: BoradPlayer, route: Array) -> void:
	for idx in route:
		token.CurrnetNodeOn = tiles[idx]
		await _move_to_node(token, tiles[idx])


func _node_behind(node: PathNode) -> PathNode:
	for prev in node.PathsBehind:
		if prev != null:
			return prev
	return null

# Shows arrows around the token and returns the index of the chosen branch.
func _pick_path(token: BoradPlayer) -> int:
	var branches: Array = token.CurrnetNodeOn.PathsAhead
	var arrows: Array[Node2D] = []
	for target in branches:
		var arrow: Node2D = PATH_ARROW.instantiate()
		token.add_child(arrow)
		arrow.global_position = token.global_position
		arrow.look_at(target.global_position)
		arrow.rotate(PI / 2)
		arrow.move_local_y(-60)
		arrow.Path = target
		arrows.append(arrow)

	await token.arrowSelected
	for arrow in arrows:
		arrow.queue_free()
	return branches.find(token.nextPath)


func _rpc_choose_path(player_id: int, index: int) -> void:
	_chosen_path[player_id] = index
	_path_chosen.emit()


# The choice can arrive before this client reaches the fork, so check the stored value first.
func _wait_for_choice(player_id: int) -> int:
	while not _chosen_path.has(player_id):
		await _path_chosen
	var idx: int = _chosen_path[player_id]
	_chosen_path.erase(player_id)
	return idx


func queue_random_minigame() -> void:
	var pool := minigame_pool.filter(func(s): return s != null)
	if pool.is_empty():
		push_warning("BoardManager: minigame_pool is empty, skipping minigame tile")
		return
	var scene: PackedScene = pool.pick_random()
	_pending_minigame = scene.resource_path


# Runs on every client with the same path, so everyone agrees on which minigame it is.
func _rpc_start_minigame(scene_path: String) -> void:
	current_player_label.text = "Minigame time!"
	player_buttons.hide()
	if not MinigameManager.is_host:
		return
	await get_tree().create_timer(1.5).timeout
	MinigameManager.progress_board_turn()   # so the next player is up when the board reloads
	await get_tree().create_timer(0.2).timeout   # let the turn update reach everyone first
	GDSync.change_scene(scene_path)

func to_minigame():
	GlobalGameData.Switch_to_minigame("uid://drqo248bup68v")
	return
extends Node

signal board_turn_changed(player_id: int)

var turn_based_game : bool = true
signal turn_changed(player_id: int)
signal stats_changed

var current_player_id : int = -1
var local_player_id   : int = -1

const COLOR_POOL: Array[Color] = [
	Color(0.90, 0.25, 0.30),   # red
	Color(0.25, 0.55, 0.95),   # blue
	Color(0.30, 0.85, 0.40),   # green
	Color(0.98, 0.85, 0.25),   # yellow
	Color(0.70, 0.40, 0.95),   # purple
	Color(1.00, 0.55, 0.20),   # orange
	Color(0.25, 0.85, 0.85),   # cyan
	Color(1.00, 0.50, 0.75),   # pink
]

var current_board_player_id : int = -1

# score list being kept here for later balancing
# xmemory match game correct pair = 15 points

class player_data:
	var player_id      : int
	var score          : int    = 0
	var username       : String = ""
	var board_position : int    = -1   # index in player_board_order
	var items          : Array  = []   # TODO: type once item type is decided
	var color : Color = Color(1, 1, 1, 1)
	var coins          : int    = 0
	var shards          : int    = 0

var player_list       : Array[player_data] = []
var current_list      : Array[player_data] = []
var player_board_order : Array[player_data] = []
var board_order_set : bool = false # if board order has been set for the game


var is_host : bool = false

# ─── Setup ────────────────────────────────────────────────────────────────────

func _ready() -> void:
	local_player_id = GDSync.get_client_id()
	is_host         = GDSync.is_host()
	GDSync.host_changed.connect(_on_host_changed)
	GDSync.expose_func(_rpc_set_player_order)
	GDSync.expose_func(_rpc_set_current_player)
	GDSync.expose_func(_rpc_update_score)
	GDSync.expose_func(_rpc_set_board_order)
	GDSync.expose_func(_rpc_set_current_board_player)
	GDSync.expose_func(_rpc_update_board_position)
	GDSync.expose_func(_rpc_set_players)
	GDSync.expose_func(_rpc_set_coins)
	GDSync.expose_func(_rpc_set_shards)

func _on_host_changed(i_am_host: bool, _new_host_id: int) -> void:
	is_host = i_am_host

# ─── Player management ────────────────────────────────────────────────────────

func add_player(player_id: int, color: Color = Color.WHITE) -> void:
	var p       = player_data.new()
	p.player_id = player_id
	p.username  = GDSync.player_get_username(player_id, "Player %d" % player_id)
	p.color     = color
	player_list.append(p)

func get_player_data_by_id(player_id: int) -> player_data:
	for p in player_list:
		if p.player_id == player_id:
			return p
	return null

func get_player_by_board_position(pos: int) -> player_data:
	if pos >= 0 and pos < player_board_order.size():
		return player_board_order[pos]
	return null

# ─── Turn order ───────────────────────────────────────────────────────────────

func randomize_player_order() -> void:
	if not is_host: return
	current_list = player_list.duplicate()
	current_list.shuffle()
	var order_ids   : Array = current_list.map(func(p): return p.player_id)
	var order_names : Array = current_list.map(func(p): return p.username)
	GDSync.call_func_all(_rpc_set_player_order, order_ids, order_names)

func _rpc_set_player_order(order_ids: Array, order_names: Array) -> void:
	current_list.clear()
	for i in range(order_ids.size()):
		var p = get_player_data_by_id(order_ids[i])
		if p == null:
			p = player_data.new()
			p.player_id = order_ids[i]
			p.username = order_names[i]
			player_list.append(p)
		current_list.append(p)
	local_player_id = GDSync.get_client_id()
	is_host = GDSync.is_host()
	if current_list.size() > 0:
		_rpc_set_current_player(current_list[0].player_id)

# ── _rpc_set_board_order: DELETE the line  p.board_position = i ──

# ── REPLACE _rpc_set_current_board_player ──
func _rpc_set_current_board_player(player_id: int) -> void:
	current_board_player_id = player_id
	board_turn_changed.emit(player_id)

# ── ADD these ──
func is_my_board_turn() -> bool:
	return current_board_player_id == GDSync.get_client_id()

# Host calls this right before GDSync.change_scene(). The autoload is always loaded,
# so the call reaches every client even while they're still loading the board.
func set_players(ids: Array) -> void:
	var picks: Array = range(COLOR_POOL.size())
	picks.shuffle()
	var color_ids: Array = []
	for i in ids.size():
		color_ids.append(picks[i % picks.size()])
	GDSync.call_func_all(_rpc_set_players, ids, color_ids)

func _rpc_set_players(ids: Array, color_ids: Array) -> void:
	player_list.clear()
	player_board_order.clear()
	board_order_set = false
	current_board_player_id = -1
	for i in ids.size():
		add_player(ids[i], COLOR_POOL[color_ids[i]])
	local_player_id = GDSync.get_client_id()
	is_host = GDSync.is_host()

# Applies locally right away (so back-to-back "+=" don't read a stale value),
# then sends the absolute value to everyone else. call_func skips the caller.
func set_coins(player_id: int, value: int) -> void:
	_rpc_set_coins(player_id, value)
	GDSync.call_func(_rpc_set_coins, player_id, value)

func _rpc_set_coins(player_id: int, value: int) -> void:
	var p = get_player_data_by_id(player_id)
	if p != null:
		p.coins = value
		stats_changed.emit()

func _rpc_set_shards(player_id: int, value: int) -> void:
	var p = get_player_data_by_id(player_id)
	if p != null:
		p.shards = value
		stats_changed.emit()

func increase_current_player_shards(amount: int) -> void:
	if not is_host: return
	var p = get_current_player_data()
	if p != null:
		set_shards(p.player_id, p.shards + amount)

func set_shards(player_id: int, value: int) -> void:
	_rpc_set_shards(player_id, value)
	GDSync.call_func(_rpc_set_shards, player_id, value)

func _rpc_set_current_player(player_id: int) -> void:
	current_player_id = player_id
	turn_changed.emit(player_id)

func progress_turn() -> void:
	if not is_host: return
	if current_list.is_empty(): return
	var idx     = current_list.find(get_current_player_data())
	var next_id = current_list[(idx + 1) % current_list.size()].player_id
	GDSync.call_func_all(_rpc_set_current_player, next_id)

# ─── Board order ──────────────────────────────────────────────────────────────

# Called externally by the board script on first load (host only).
func randomize_board_order() -> void:
	if not is_host: return
	var shuffled    : Array = player_list.duplicate()
	shuffled.shuffle()
	var order_ids   : Array = shuffled.map(func(p): return p.player_id)
	var order_names : Array = shuffled.map(func(p): return p.username)
	GDSync.call_func_all(_rpc_set_board_order, order_ids, order_names)

func _rpc_set_board_order(order_ids: Array, order_names: Array) -> void:
	player_board_order.clear()
	for i in range(order_ids.size()):
		# Reuse the existing player_data object so score/items are preserved.
		var p = get_player_data_by_id(order_ids[i])
		if p == null:
			# Edge case: board order arrived before player_list was populated.
			p = player_data.new()
			p.player_id = order_ids[i]
			p.username = order_names[i]
			player_list.append(p)
		p.board_position = i
		player_board_order.append(p)
	board_order_set = true
	if player_board_order.size() > 0:
		_rpc_set_current_board_player(player_board_order[0].player_id)

func progress_board_turn() -> void:
	if not is_host: return
	if player_board_order.is_empty(): return
	var idx     = player_board_order.find(get_current_board_player_data())
	var next_id = player_board_order[(idx + 1) % player_board_order.size()].player_id
	GDSync.call_func_all(_rpc_set_current_board_player, next_id)


func get_current_board_player_data() -> player_data:
	return get_player_data_by_id(current_board_player_id)

func set_current_board_plr_pos(pos: int) -> void:
	var p = get_current_board_player_data()
	if p != null:
		p.board_position = pos
		GDSync.call_func_all(_rpc_update_board_position, current_board_player_id, pos)

func _rpc_update_board_position(player_id: int, pos: int) -> void:
	var p = get_player_data_by_id(player_id)
	if p != null:
		p.board_position = pos

# ─── Score ────────────────────────────────────────────────────────────────────

func increase_current_player_score(amount: int) -> void:
	if not is_host: return
	var p = get_current_player_data()
	if p != null:
		p.score += amount
		GDSync.call_func_all(_rpc_update_score, current_player_id, p.score)

func increase_current_player_coins(amount: int) -> void:
	if not is_host: return
	var p = get_current_player_data()
	if p != null:
		set_coins(p.player_id, p.coins + amount)

func _rpc_update_score(player_id: int, new_score: int) -> void:
	var p = get_player_data_by_id(player_id)
	if p != null:
		p.score = new_score

# ─── Helpers ──────────────────────────────────────────────────────────────────

func get_current_player_data() -> player_data:
	return get_player_data_by_id(current_player_id)

func get_current_player_name() -> String:
	var p = get_current_player_data()
	return p.username if p != null else "Unknown Player"

func get_local_player_name() -> String:
	var p = get_player_data_by_id(local_player_id)
	return p.username if p != null else "Unknown Player"

func get_local_player_board_position() -> int:
	var p = get_player_data_by_id(local_player_id)
	return p.board_position if p != null else -1

func is_my_turn() -> bool:
	return current_player_id == GDSync.get_client_id()

func get_player_count() -> int:
	return player_list.size()

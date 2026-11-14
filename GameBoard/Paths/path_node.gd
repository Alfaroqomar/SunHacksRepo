class_name PathNode
extends Sprite2D

@export var TileType: TileTypeEnum = TileTypeEnum.Blank
enum TileTypeEnum {
	Blank, Good, Bad, Reroll, Crystal, Back, Friend, Shop,
	Toll, Bank, Item, Warp, Shuffle, Steal,
	Minigame
}

const GOOD_COINS := 5
const BAD_COINS := 5
const BACK_STEPS := 2
const STEAL_COINS := 5
const CRYSTAL_SHARDS := 1

@export var PathsAhead: Array[PathNode]
@export var AutoBehind: bool = true
@export var PathsBehind: Array[PathNode]

@export var tileTexture: Texture2D

var BoardGameManager: BoardManger

func _ready() -> void:
	BoardGameManager = get_tree().get_first_node_in_group("BoardManager")

	if tileTexture:
		texture = tileTexture

	_apply_tile_color()

	for node in PathsAhead:
		if node == null: continue
		var newLine: Line2D = Line2D.new()
		newLine.add_point(Vector2.ZERO)
		newLine.add_point(node.global_position - position)
		newLine.z_index -= 1
		add_child(newLine)
		node.add_behind_node(self)

func add_behind_node(node):
	if AutoBehind:
		PathsBehind.append(node)

func _apply_tile_color() -> void:
	match TileType:
		TileTypeEnum.Blank:    modulate = Color.WHITE
		TileTypeEnum.Good:     modulate = Color(0.3, 0.9, 0.3)
		TileTypeEnum.Bad:      modulate = Color(0.9, 0.3, 0.3)
		TileTypeEnum.Reroll:   modulate = Color(0.9, 0.9, 0.3)
		TileTypeEnum.Crystal:  modulate = Color(0.5, 0.8, 1.0)
		TileTypeEnum.Back:     modulate = Color(0.8, 0.5, 0.2)
		TileTypeEnum.Friend:   modulate = Color(1.0, 0.6, 0.8)
		TileTypeEnum.Shop:     modulate = Color(0.7, 0.5, 1.0)
		TileTypeEnum.Toll:     modulate = Color(0.9, 0.7, 0.2)
		TileTypeEnum.Bank:     modulate = Color(0.2, 0.7, 0.5)
		TileTypeEnum.Item:     modulate = Color(0.6, 0.9, 0.6)
		TileTypeEnum.Warp:     modulate = Color(0.8, 0.3, 0.9)
		TileTypeEnum.Shuffle:  modulate = Color(1.0, 0.5, 0.2)
		TileTypeEnum.Steal:    modulate = Color(0.4, 0.4, 0.4)
		TileTypeEnum.Minigame: modulate = Color(0.3, 0.5, 1.0)   # blue


# Runs only on the client whose turn it is. Returns true if the player should roll again.
func land_on(Player: BoradPlayer) -> bool:
	var roll_again := false
	match TileType:
		TileTypeEnum.Good:
			_add_coins(Player.PlayerId, GOOD_COINS)
		TileTypeEnum.Bad:
			_add_coins(Player.PlayerId, -BAD_COINS)
		TileTypeEnum.Reroll:
			roll_again = true
		TileTypeEnum.Back:
			await BoardGameManager.move_back(Player, BACK_STEPS)
		TileTypeEnum.Steal:
			_steal_coins(Player.PlayerId, STEAL_COINS)
		TileTypeEnum.Crystal:
			_add_shards(Player.PlayerId, CRYSTAL_SHARDS)
		TileTypeEnum.Friend:
			pass
		TileTypeEnum.Shop:
			pass
		TileTypeEnum.Toll:
			pass
		TileTypeEnum.Bank:
			pass
		TileTypeEnum.Item:
			pass
		TileTypeEnum.Warp:
			pass
		TileTypeEnum.Shuffle:
			BoardGameManager.GoingForwardOrder *= -1
		TileTypeEnum.Minigame:
			BoardGameManager.queue_random_minigame()
	return roll_again


func touchPath(Player):
	match TileType:
		TileTypeEnum.Crystal:
			pass
		TileTypeEnum.Toll:
			pass
		TileTypeEnum.Bank:
			pass


# ─── Coin helpers ─────────────────────────────────────────────────────────────

# Clamps at 0 so nobody goes negative.
func _add_coins(player_id: int, amount: int) -> void:
	var data = MinigameManager.get_player_data_by_id(player_id)
	if data == null:
		return
	MinigameManager.set_coins(player_id, maxi(data.coins + amount, 0))

func _add_shards(player_id: int, amount: int) -> void:
	var data = MinigameManager.get_player_data_by_id(player_id)
	if data == null:
		return
	MinigameManager.set_shards(player_id, maxi(data.shards + amount, 0))

func _steal_coins(thief_id: int, amount: int) -> void:
	var victims: Array = MinigameManager.player_list.filter(
			func(p): return p.player_id != thief_id and p.coins > 0)
	if victims.is_empty():
		return   # nobody has anything to steal
	var victim = victims.pick_random()
	var taken: int = mini(amount, victim.coins)
	_add_coins(victim.player_id, -taken)
	_add_coins(thief_id, taken)
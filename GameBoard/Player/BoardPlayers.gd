class_name BoradPlayer
extends Node2D

var MoveSpeed: int = 250
var PlayerId: int = -1            # GD-Sync client id; set by BoardManager on spawn
var CurrnetNodeOn: PathNode

@export var CharterSprites: Array[Array]

# The path-arrow scene talks to its parent through these two.
signal arrowSelected
var nextPath: PathNode

# Stats live in MinigameManager.player_data so they sync and survive scene changes.
var CoinCount: int:
	get:
		var d = MinigameManager.get_player_data_by_id(PlayerId)
		return d.coins if d != null else 0
	set(value):
		MinigameManager.set_coins(PlayerId, value)

var ShardCount: int:
	get:
		var d = MinigameManager.get_player_data_by_id(PlayerId)
		return d.shards if d != null else 0
	set(value):
		MinigameManager.set_shards(PlayerId, value)
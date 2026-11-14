extends Node

var gridSize = 4 # rows and columns so 4 would be 4x4 grid aka 16 cards
@export var defaultCard: CenterContainer
@export var current_player_label: RichTextLabel
var cardSymbols: Array[String] = ["Bat", "Cat", "Witch", "Ghost", "Pumpkin", "Spider", "Candy", "Moon"]
var cardList: Array[Card] = []

@export var shards_per_pair: int = 1

var card_back_texture: Texture2D = preload("res://Sprites/MinigameSprites/CardMinigame/cardback.png")
var card_front_texture: Texture2D = preload("res://Sprites/MinigameSprites/CardMinigame/CardbackOne.png") # side without symbol

@export var coins_per_pair: int = 5

@export_file("*.tscn") var board_scene_path: String = ""   # set to your board scene in the inspector
var pairs_found: int = 0
var _finishing: bool = false

var selectingSecond: bool = false
var firstSelectedCard: Card = null

var card_reveal_time: float = 0.5
var card_flip_back_time: float = 0.5

var _local_picks: Array[int] = []   # cards this client has clicked that haven't resolved yet

var do_spawn_animation: bool = true
var can_select : bool = true

@export var reaperSprite: TextureRect

var reaper_spritesheet: Texture2D = preload("res://Sprites/MinigameSprites/CardMinigame/Reaper.png")
var symbol_spritesheet: Texture2D = preload("res://Sprites/MinigameSprites/CardMinigame/Gamejam_card_symbols.png")

#players is a dictionary of player ids with their scores, for example: {1: 0, 2: 0} for a 2 player game

var players: Dictionary[int, int] = {}

func _on_card_gui_input(event: InputEvent, actualNode: Node) -> void:
	if not MinigameManager.is_my_turn():
		print("Not your turn ", MinigameManager.get_local_player_name())
		return
	if event is InputEventMouseButton and event.pressed and can_select:
		var card = get_card_from_node(actualNode)
		if card != null and not card.isFlipped:
			var idx = cardList.find(card)
			if idx in _local_picks or _local_picks.size() >= 2:
				return   # already sent two flips, or this card, and the RPC hasn't landed yet
			_local_picks.append(idx)
			GDSync.call_func_all(_rpc_flip_card, idx)

func _rpc_flip_card(card_index: int) -> void:
	handle_card_flip(cardList[card_index])

var delayTimer: Timer = null

class Card:
	var node: CenterContainer
	var symbol_node: TextureRect
	var symbol: String
	var pairedCard: Card
	var isFlipped: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:

	GDSync.expose_func(_rpc_flip_card)
	GDSync.expose_func(_rpc_set_card_layout)
	GDSync.expose_func(set_sprite_frame)
	set_sprite_frame(1, 3) # 0 is happy, 1 is normal, 2 is good
	MinigameManager.turn_changed.connect(func(_id):
		_local_picks.clear()
		current_player_label.text = MinigameManager.get_current_player_name() + "'s Turn"
		if MinigameManager.is_my_turn():
			current_player_label.text = "Your Turn."
		can_select = true
	)
	current_player_label.text = "Waiting..."
	populateGrid()
	if MinigameManager.is_host:
		MinigameManager.randomize_player_order()

func progress_turn() -> void:
	MinigameManager.progress_turn()
	
func get_card_from_node(node: Node) -> Card:
	for card in cardList:
		if card.node == node:
			return card
	return null

func handle_card_flip(card: Card) -> void:
	if card.isFlipped:
		return # Ignore if the card is already flipped

	if firstSelectedCard == null:
		firstSelectedCard = card
		selectingSecond = true
	else:
		can_select = false # Disable further selection until the cards are processed

	card.isFlipped = true
	card_flip_animation(card)

func card_flip_animation(card: Card) -> void:
	# Implement the flip animation logic here
	# tweening the scale x of transform offset to 0, then change the symbol, then tween back to 1
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(card.node, "scale:x", 0, card_reveal_time)
	tween.tween_callback(_on_flip_halfway.bind(card))
	tween.tween_property(card.node, "scale:x", 1, card_reveal_time)
	tween.tween_callback(_on_flip_complete.bind(card))
	tween.play()
	pass

func _on_flip_halfway(card: Card) -> void:
	# Change the symbol of the card here
	#card.node.get_node("Card/RichTextLabel").text = card.symbol
	set_symbol_of_card(card, card.symbol, 4, 3)
	card.symbol_node.visible = true
	card.node.get_node("Card/CardBackground").texture = card_back_texture

func _on_flip_complete(card: Card) -> void:
	if selectingSecond and firstSelectedCard != null and firstSelectedCard != card:
		if firstSelectedCard.symbol == card.symbol:
			firstSelectedCard.node.modulate = Color(0, 1, 0)
			card.node.modulate = Color(0, 1, 0)
			can_select = true # Re-enable selection for the next pair
			_local_picks.clear()
			GDSync.call_func_all(set_sprite_frame, 0, 3)
			tween_cards_to_reaper(firstSelectedCard, card)
			MinigameManager.increase_current_player_score(15)
			MinigameManager.increase_current_player_coins(coins_per_pair)
			MinigameManager.increase_current_player_shards(shards_per_pair)

			pairs_found += 1
			if pairs_found >= cardList.size() / 2: # cardList.size() / 2:
				can_select = false   # nothing left to flip
				_return_to_board()
		else:
			can_select = false
			GDSync.call_func_all(set_sprite_frame, 2, 3)
			await get_tree().create_timer(.5).timeout
			flip_back_cards(firstSelectedCard, card)

		selectingSecond = false
		firstSelectedCard = null

func tween_cards_to_reaper(card1: Card, card2: Card) -> void:
	_fly_card_to_reaper(card1, Vector2(0.2, 0.2))
	_fly_card_to_reaper(card2, Vector2.ZERO)

func _return_to_board() -> void:
	if _finishing:
		return
	_finishing = true
	current_player_label.text = "All pairs found!"

	# Gives the last pair time to fly into the reaper and the final score RPC time to land.
	await get_tree().create_timer(2.0).timeout

	if not MinigameManager.is_host:
		return   # only the host can change the scene for everyone
	if board_scene_path == "":
		push_error("Memory minigame: board_scene_path is not set")
		return
	GDSync.change_scene(board_scene_path)

func _fly_card_to_reaper(card: Card, end_scale: Vector2) -> void:
	var bg: TextureRect = card.node.get_node("Card/CardBackground")
	var sym: TextureRect = card.symbol_node

	# Snap to global space visually before detaching from parent transform
	for node in [bg, sym]:
		var gpos = node.global_position
		node.top_level = true
		node.global_position = gpos
		node.pivot_offset = node.size / 2.0

	var reaper_center = reaperSprite.global_position + (reaperSprite.size * reaperSprite.scale) / 2.0 - bg.size / 2.0
	reaper_center = reaper_center - Vector2(50, 0)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(bg, "global_position", reaper_center, 1.0-0.2)
	tween.tween_property(bg, "scale", end_scale, 1.0)
	tween.tween_property(sym, "global_position", reaper_center, 1.0)
	tween.tween_property(sym, "scale", end_scale, 1.0)
	tween.chain().tween_callback(_on_card_reached_reaper.bind(card))

func _on_card_reached_reaper(card: Card) -> void:
	card.node.get_node("Card/CardBackground").visible = false
	card.symbol_node.visible = false

func turn_completed() -> void:
	# Update the current player label to reflect the next player's turn
	progress_turn()

func flip_back_cards(card1: Card, card2: Card) -> void:
	print("Flipping back cards")
	card1.isFlipped = false
	card2.isFlipped = false
	# Implement the flip back animation logic here
	var tween1 = create_tween()
	tween1.set_ease(Tween.EASE_IN_OUT)
	tween1.set_trans(Tween.TRANS_SINE)
	tween1.tween_property(card1.node, "scale:x", 0, card_flip_back_time)
	tween1.tween_callback(_on_flip_back_halfway.bind(card1))
	tween1.tween_property(card1.node, "scale:x", 1, card_flip_back_time)
	tween1.play()

	var tween2 = create_tween()
	tween2.set_ease(Tween.EASE_IN_OUT)
	tween2.set_trans(Tween.TRANS_SINE)
	tween2.tween_property(card2.node, "scale:x", 0, card_flip_back_time)
	tween2.tween_callback(_on_flip_back_halfway.bind(card2))
	tween2.tween_property(card2.node, "scale:x", 1, card_flip_back_time)
	tween2.tween_callback(_on_flip_back_complete.bind(card1, card2))
	tween2.play()



func _on_flip_back_halfway(card: Card) -> void:
	# Change the symbol of the card back to default here
	card.symbol_node.visible = false
	#card.node.get_node("Card/RichTextLabel").text = ""
	card.node.get_node("Card/CardBackground").texture = card_front_texture

func _on_flip_back_complete(card1: Card, card2: Card) -> void:
	# Reset the modulate color of the cards back to normal
	turn_completed()

func populateGrid() -> void:
	var cardCount = gridSize * gridSize
	var possibleSymbols = cardSymbols.slice(0, cardCount / 2)
	for symbol in possibleSymbols:
		var c1 = Card.new(); c1.symbol = symbol; cardList.append(c1)
		var c2 = Card.new(); c2.symbol = symbol; cardList.append(c2)
		c1.pairedCard = c2; c2.pairedCard = c1

	if MinigameManager.is_host:
		cardList.shuffle()
		var layout: Array = cardList.map(func(c): return c.symbol)
		GDSync.call_func_all(_rpc_set_card_layout, layout)

func _rpc_set_card_layout(layout: Array) -> void:
	cardList.clear()
	var by_symbol: Dictionary = {}
	for symbol in layout:
		var card = Card.new()
		card.symbol = symbol
		cardList.append(card)
		if not by_symbol.has(symbol): by_symbol[symbol] = []
		by_symbol[symbol].append(card)
	for symbol in by_symbol:
		var pair = by_symbol[symbol]
		if pair.size() == 2:
			pair[0].pairedCard = pair[1]
			pair[1].pairedCard = pair[0]
	spawn_cards()

func spawn_cards() -> void:
	for i in range(cardList.size()):
		var newCard : CenterContainer = defaultCard.duplicate()
		cardList[i].node = newCard
		cardList[i].symbol_node = newCard.get_node("Card/Symbol")
		# bind the gui_input signal of the new card to the _on_card_gui_input function
		newCard.gui_input.connect(_on_card_gui_input.bind(newCard))
		#newCard.get_node("Label").text = cardList[i].symbol
		defaultCard.get_parent().add_child(newCard)
		newCard.visible = true
	# This function can be used to spawn cards if needed
	pass

func set_sprite_frame(frame_index: int, total_frames: int) -> void:
	var frame_width = reaper_spritesheet.get_width() / total_frames
	var frame_height = reaper_spritesheet.get_height()

	var atlas = AtlasTexture.new()
	atlas.atlas = reaper_spritesheet
	atlas.region = Rect2(frame_index * frame_width, 0, frame_width, frame_height)

	reaperSprite.texture = atlas

func set_symbol_of_card(card: Card, symbol_text: String, columns: int, rows: int) -> void:
	# get frame index from the symbol based on position in symbol array
	var frame_index = cardSymbols.find(symbol_text)
	var spritesheet = symbol_spritesheet
	var frame_width = spritesheet.get_width() / columns
	var frame_height = spritesheet.get_height() / rows

	var col = frame_index % columns
	var row = frame_index / columns

	var atlas = AtlasTexture.new()
	atlas.atlas = spritesheet
	atlas.region = Rect2(col * frame_width, row * frame_height, frame_width, frame_height)

	card.symbol_node.texture = atlas

class_name menu_manager extends Control

@onready var buttonContainer = $VBoxContainer
@export var nameInputContainer : Control
@export var nameInput : LineEdit

var PARTY_SCENE = preload("uid://bide13jrm2qcp").instantiate()
var CREDITS = preload("uid://dbmrc1j6l5flg").instantiate()

func _ready() -> void:
	nameInputContainer.visible = false
	GDSync.connected.connect(_on_connected)
	GDSync.player_data_changed.connect(_on_player_data_changed)
	#GDSync.start_multiplayer()

func _on_connected():
	# When connected show username input
	nameInputContainer.visible = true
	buttonContainer.visible = false
	MinigameManager.local_player_id = GDSync.get_client_id()
	# when username is set, start scene change to next scene
	pass
	
func is_valid_name(name: String) -> bool:
	return name.length() >= 3

func submit_name() -> void:
	var name = nameInput.text.strip_edges()
	if is_valid_name(name):
		GDSync.player_set_username(name)
		nameInputContainer.visible = false
	else:
		nameInputContainer.get_node("ErrorLabel").text = "Name must be at least 3 characters."

func _on_player_data_changed(client_id: int, key: String, value) -> void:
	if client_id == GDSync.get_client_id() and key == "Username" and is_valid_name(value):
		get_tree().change_scene_to_node(PARTY_SCENE)

func _on_party_button_pressed() -> void:
	# load the party scene
	GDSync.start_multiplayer()
	pass # Replace with function body.


func _on_credits_button_pressed() -> void:
	# load the credits scene
	get_tree().change_scene_to_node(CREDITS)
	pass # Replace with function body.


func _on_button_pressed() -> void:
	submit_name()
	pass # Replace with function body.

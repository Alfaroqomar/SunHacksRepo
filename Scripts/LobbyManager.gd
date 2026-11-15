class_name LobbyManager extends Node

@export var lobby_list : VBoxContainer
@export var lobbiesText : RichTextLabel
@export var status_label : RichTextLabel
@export var create_menu : Control
@export var lobby_name_input : LineEdit
@export var lobby_password_input : LineEdit
@export var lobby_players_input : OptionButton
@export var lobby_create_status : RichTextLabel
@export var default_lobby_listing : MarginContainer

@export var join_password_panel : Control
@export var join_password_input : LineEdit
@export var join_password_submit_button : Button

@export var lobby_viewer : Control
@export var lobby_viewer_players: RichTextLabel
@export var lobby_name_label : RichTextLabel

@export var debug : bool = false

@export var start_lobby_button: Button

var _in_lobby: bool = false  # add this at the top with your other vars

var _password_callable : Callable
var _password_button_callable : Callable
var _lobby_members : Array[int] = []

func _ready() -> void:
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	GDSync.lobbies_received.connect(_on_lobbies_received)
	GDSync.client_joined.connect(_on_client_joined)
	GDSync.client_left.connect(_on_client_left)
	GDSync.connected.connect(_on_connected)
	GDSync.host_changed.connect(_on_host_changed)
	if debug and not GDSync.is_active():
		GDSync.start_multiplayer()
		# give random player name for debug purposes
		#GDSync.player_set_username("DebugPlayer%d" % randi())
	refresh_lobbies()

func _on_connected():
	GDSync.player_set_username("DebugPlayer%d" % randi())
	refresh_lobbies()

func refresh_lobbies() -> void:
	status_label.text = "Refreshing..."
	# removed is_in_lobby() — _lobby_members is managed by client_joined/client_left
	GDSync.get_public_lobbies()


func _on_client_joined(client_id: int):
	if not _lobby_members.has(client_id):
		_lobby_members.append(client_id)
	_update_player_names_tag()
	update_lobby_viewer()  # Update the lobby viewer when a new client joins


func _on_client_left(client_id: int):
	_lobby_members.erase(client_id)
	_update_player_names_tag()
	update_lobby_viewer()  # Update the lobby viewer when a client leaves


func _update_player_names_tag():
	if not GDSync.is_host(): return
	var names = []
	for id in _lobby_members:
		names.append(GDSync.player_get_username(id, "Unknown"))
	GDSync.lobby_set_tag("PlayerNames", names)




func _on_lobbies_received(lobbies: Array):
	default_lobby_listing.visible = false

	for child in lobby_list.get_children():
		if child != default_lobby_listing:
			child.queue_free()

	if lobbies.is_empty():
		status_label.text = "No open lobbies found."
		return

	for lobby in lobbies:
		if lobby["PlayerCount"] <= 0:
			continue
		var new_listing = default_lobby_listing.duplicate()

		var has_password = lobby.get("Tags", {}).get("HasPassword", false)
		new_listing.get_node("LobbyNameLabel").text = ("[img]res://addons/at-icons/mesh/lock.svg[/img]" if has_password else "") + lobby["Name"]
		new_listing.get_node("PlayersLabel").text = "%d/%d" % [
			lobby["PlayerCount"],
			lobby["PlayerLimit"]
		]

		var player_names : Array = lobby.get("Tags", {}).get("PlayerNames", [])
		var names_label = new_listing.get_node("Panel/PlayerNamesLabel")
		if player_names.is_empty():
			names_label.text = "Players: —"
		else:
			names_label.text = "Players: " + ", ".join(player_names)

		new_listing.get_node("Panel/JoinLobbyButton").pressed.connect(
			func(): _on_join_lobby_button_pressed(lobby)
		)
		new_listing.get_node("Panel/JoinLobbyButton").disabled = not lobby["Open"]

		new_listing.visible = true
		lobby_list.add_child(new_listing)

	status_label.text = "%d lobbies found." % lobbies.size()


func _on_join_lobby_button_pressed(lobby: Dictionary):
	var has_password = lobby.get("Tags", {}).get("HasPassword", false)
	if has_password:
		join_password_panel.visible = true
		join_password_input.grab_focus()
		join_password_input.text = ""
		_password_callable = func(password: String): _on_join_lobby_with_password(password, lobby)
		_password_button_callable = func(): _on_join_lobby_with_password(join_password_input.text, lobby)
		join_password_submit_button.pressed.connect(_password_button_callable)
		join_password_input.text_submitted.connect(_password_callable)
	else:
		GDSync.lobby_join(lobby["Name"], "")


func _on_join_lobby_with_password(password: String, lobby: Dictionary):
	GDSync.lobby_join(lobby["Name"], password)
	join_password_panel.visible = false
	join_password_input.text_submitted.disconnect(_password_callable)
	join_password_submit_button.pressed.disconnect(_password_button_callable)
	

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GDSync.lobby_leave()


func _on_refresh_lobbies_pressed() -> void:
	refresh_lobbies()


func open_create_menu() -> void:
	create_menu.visible = true


func close_create_menu() -> void:
	create_menu.visible = false


func _on_create_button_pressed() -> void:
	open_create_menu()


func _on_create_lobby_button_pressed() -> void:
	var name = lobby_name_input.text.strip_edges()
	if name.length() < 3:
		lobby_create_status.text = "Name must be at least 3 characters."
		return
	var has_password = lobby_password_input.text.length() > 0
	GDSync.lobby_create(name, lobby_password_input.text, true, lobby_players_input.selected + 2, {
		"Status": "Waiting",
		"HasPassword": has_password
	})


func _on_lobby_creation_failed(lobby_name: String, error: int):
	match error:
		ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS:
			lobby_create_status.text = "Name already taken, try another."
		ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_SHORT:
			lobby_create_status.text = "Name too short (min 3 chars)."
		ENUMS.LOBBY_CREATION_ERROR.NAME_TOO_LONG:
			lobby_create_status.text = "Name too long (max 32 chars)."
		_:
			lobby_create_status.text = "Failed to create lobby (error %d)" % error


func _on_lobby_created(lobby_name: String):
	print("Lobby created: %s" % lobby_name)
	lobby_create_status.text = ""
	GDSync.lobby_join(lobby_name, lobby_password_input.text)
	# add the host to the lobby members list
	_lobby_members.append(GDSync.get_client_id())
	open_lobby_viewer()
	close_create_menu()

func open_lobby_viewer():
	lobby_viewer.visible = true
	# fill in the lobby viewer with current lobby info
	update_lobby_viewer()


func update_lobby_viewer() -> void:
	if _lobby_members.is_empty():
		lobby_viewer_players.text = "Players: - "
		return
	var lines: Array[String] = []
	for id in _lobby_members:
		lines.append(GDSync.player_get_username(id, "Player %d" % id))
		lines.append(", ")
	lines.pop_back()  # Remove the last ", "
	lobby_viewer_players.text = "Players: - " + "".join(lines)
	lobby_name_label.text = "Lobby: " + GDSync.lobby_get_name()

func _on_close_lobby_create_button_pressed() -> void:
	close_create_menu()


func _on_lobby_joined(lobby_name: String) -> void:
	_in_lobby = true
	status_label.text = "Joined: " + lobby_name
	# Add ourselves — client_joined fires for others but we need to add ourselves manually
	var my_id := GDSync.get_client_id()
	if not _lobby_members.has(my_id):
		_lobby_members.append(my_id)
	open_lobby_viewer()    # ← was missing for non-host players
	update_lobby_viewer()
	refresh_lobbies()

func start_button_pressed():
	if GDSync.is_host():
		GDSync.lobby_set_tag("Status", "Starting")
		GDSync.lobby_set_tag("GameStarted", true)


func _on_lobby_join_failed(lobby_name: String, error: int):
	match error:
		ENUMS.LOBBY_JOIN_ERROR.LOBBY_DOES_NOT_EXIST:
			status_label.text = "Lobby no longer exists, refreshing..."
			refresh_lobbies()
		ENUMS.LOBBY_JOIN_ERROR.LOBBY_IS_FULL:
			status_label.text = "Lobby is full."
		ENUMS.LOBBY_JOIN_ERROR.INCORRECT_PASSWORD:
			status_label.text = "Incorrect password."
		_:
			status_label.text = "Couldn't join '%s' (error %d)" % [lobby_name, error]

func _on_host_changed(is_host: bool, new_host_id: int) -> void:
	start_lobby_button.visible = is_host

func set_players_for_game() -> void:
	MinigameManager.set_players(_lobby_members)

func _on_start_lobby_button_pressed() -> void:
	MinigameManager.is_host = GDSync.is_host()
	set_players_for_game()
	GDSync.change_scene("res://GameBoard/test_board.tscn")
	# changing the change scene input later

func close_lobby_viewer():
	lobby_viewer.visible = false

func _on_leave_lobby_button_pressed() -> void:
	GDSync.lobby_leave()
	_in_lobby = false
	_lobby_members.clear()
	close_lobby_viewer()
	refresh_lobbies()
	pass # Replace with function body.

extends Node

var saveData:Dictionary = { # add data that should be saved between reload of the game
	Name = null
}

func _ready() -> void:
	load_from_file()

func save_to_file():
	var file = FileAccess.open("user://save_game.dat", FileAccess.WRITE)
	file.store_var(saveData)

func load_from_file():
	var file = FileAccess.open("user://save_game.dat", FileAccess.READ)
	if file == null:
		print("No save file found")
		return
	saveData = file.get_var()

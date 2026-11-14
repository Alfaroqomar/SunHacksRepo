extends LineEdit

func _ready() -> void:
	if PlayerInfo.saveData["Name"] != null:
		text = PlayerInfo.saveData["Name"]

func _on_editing_toggled(toggled_on: bool) -> void:
	#print(toggled_on)
	if toggled_on:
		PlayerInfo.saveData["Name"] = text

extends Polygon2D

var Path:PathNode


func _on_button_pressed() -> void:
	get_parent().nextPath = Path
	get_parent().arrowSelected.emit()
	pass # Replace with function body.
